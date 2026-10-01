"""Hybrid RDF Triples (ABox) to Cloud Spanner Graph Loader.

Combines:
1. Deterministic DDL & Property Graph schema parser (`parse_spanner_ddl`)
2. Ontology/SHACL + LLM Schema Mapping Spec synthesis (`generate_schema_mapping_spec`)
   with deterministic fallback/grounding (`build_deterministic_mapping_spec`)
3. Deterministic `rdflib` ABox triple extraction, concrete leaf routing,
   URI -> PK normalization, blank-node flattening, reification (`rdf:Statement`)
   resolution, topological sorting, and GoogleSQL `INSERT` generation
4. Execution against Remote Spanner MCP or Local Cloud Spanner Emulator with
   automatic LLM self-correction on constraint failures.
"""

from __future__ import annotations

import dataclasses
import json
import os
import re
import uuid
from collections import defaultdict
from typing import Any

import rdflib
from rdflib.namespace import OWL, RDF, RDFS, SH, XSD
from google.genai import types
from rich.console import Console

from rdf_spanner_translator.config import DEFAULT_GEMINI_MODEL, DEFAULT_MCP_URL
from rdf_spanner_translator.translator import (
    _generate_with_retry,
    _get_client,
    load_skill_instructions,
)
from rdf_spanner_translator.query_verifier import (
    execute_spanner_dml_batch,
    execute_spanner_statement,
    extract_json_payload,
)

console = Console()


# =============================================================================
# 1. DATA STRUCTURES FOR PARSED SPANNER DDL & GRAPH SCHEMA
# =============================================================================

@dataclasses.dataclass
class ColumnDef:
    name: str
    sql_type: str  # e.g., STRING, INT64, NUMERIC, FLOAT64, BOOL, DATE, TIMESTAMP
    is_array: bool = False
    max_length: int | None = None
    not_null: bool = False
    is_generated: bool = False
    default_expr: str | None = None
    allowed_values: list[str] = dataclasses.field(default_factory=list)


@dataclasses.dataclass
class ForeignKeyDef:
    columns: list[str]
    ref_table: str
    ref_columns: list[str]


@dataclasses.dataclass
class TableDef:
    name: str
    columns: dict[str, ColumnDef]
    primary_keys: list[str]
    interleaved_parent: str | None = None
    foreign_keys: list[ForeignKeyDef] = dataclasses.field(default_factory=list)
    no_self_loop_pairs: list[tuple[str, str]] = dataclasses.field(default_factory=list)


@dataclasses.dataclass
class GraphEdgeDef:
    physical_table: str
    alias: str
    source_keys: list[str]
    source_ref_table: str
    source_ref_keys: list[str]
    dest_keys: list[str]
    dest_ref_table: str
    dest_ref_keys: list[str]
    labels: list[str]
    properties: list[str] = dataclasses.field(default_factory=list)


@dataclasses.dataclass
class ParsedSpannerDDL:
    tables: dict[str, TableDef]
    views: set[str]
    graph_name: str | None
    node_table_labels: dict[str, list[str]]  # table_name -> list of LABEL names
    edge_defs: list[GraphEdgeDef]


# =============================================================================
# 2. DETERMINISTIC SPANNER DDL & PROPERTY GRAPH PARSER
# =============================================================================

def _norm(name: str) -> str:
    """Normalizes an identifier for fuzzy matching (lowercase alphanumeric only)."""
    return re.sub(r"[^a-z0-9]", "", name.lower())


def _local_name(uri: str | rdflib.term.Node) -> str:
    """Extracts the local name from an RDF URI or CURIE."""
    s = str(uri).strip()
    if "#" in s:
        return s.rsplit("#", 1)[-1]
    if "/" in s:
        return s.rstrip("/").rsplit("/", 1)[-1]
    if ":" in s:
        return s.rsplit(":", 1)[-1]
    return s


def _split_top_level_commas(text: str) -> list[str]:
    """Splits a SQL block by commas that are not nested inside parentheses."""
    parts = []
    current = []
    depth = 0
    in_quote = False
    quote_char = ""
    for ch in text:
        if in_quote:
            current.append(ch)
            if ch == quote_char:
                in_quote = False
        else:
            if ch in ("'", '"', "`"):
                in_quote = True
                quote_char = ch
                current.append(ch)
            elif ch == "(":
                depth += 1
                current.append(ch)
            elif ch == ")":
                depth = max(0, depth - 1)
                current.append(ch)
            elif ch == "," and depth == 0:
                parts.append("".join(current).strip())
                current = []
            else:
                current.append(ch)
    if current:
        tail = "".join(current).strip()
        if tail:
            parts.append(tail)
    return parts


def parse_spanner_ddl(ddl_content: str) -> ParsedSpannerDDL:
    """Parses CREATE TABLE, CREATE VIEW, and CREATE PROPERTY GRAPH from Spanner DDL."""
    # Strip single-line SQL comments
    clean_lines = []
    for line in ddl_content.splitlines():
        idx = line.find("--")
        if idx != -1:
            line = line[:idx]
        clean_lines.append(line)
    clean_ddl = "\n".join(clean_lines)

    tables: dict[str, TableDef] = {}
    views: set[str] = set()
    graph_name: str | None = None
    node_table_labels: dict[str, list[str]] = defaultdict(list)
    edge_defs: list[GraphEdgeDef] = []

    # 1. Views
    for m in re.finditer(r"CREATE\s+(?:OR\s+REPLACE\s+)?VIEW\s+`?(\w+)`?", clean_ddl, re.IGNORECASE):
        views.add(m.group(1))

    # 2. Tables
    table_pattern = re.compile(
        r"CREATE\s+TABLE\s+`?(\w+)`?\s*\((.*?)\)\s*PRIMARY\s+KEY\s*\(([^)]+)\)"
        r"(?:\s*,\s*INTERLEAVE\s+IN\s+PARENT\s+`?(\w+)`?)?",
        re.IGNORECASE | re.DOTALL,
    )
    for m in table_pattern.finditer(clean_ddl):
        t_name = m.group(1)
        body = m.group(2)
        pk_raw = m.group(3)
        interleave_parent = m.group(4)

        pks = [
            re.sub(r"\b(ASC|DESC)\b", "", col, flags=re.IGNORECASE).strip(" `")
            for col in pk_raw.split(",")
            if col.strip()
        ]

        cols: dict[str, ColumnDef] = {}
        fks: list[ForeignKeyDef] = []
        no_self_loops: list[tuple[str, str]] = []
        enum_constraints: dict[str, list[str]] = {}

        for item in _split_top_level_commas(body):
            item_s = item.strip()
            if not item_s:
                continue

            # Check for FOREIGN KEY constraint
            fk_m = re.search(
                r"FOREIGN\s+KEY\s*\(([^)]+)\)\s*REFERENCES\s+`?(\w+)`?\s*\(([^)]+)\)",
                item_s,
                re.IGNORECASE,
            )
            if fk_m:
                src_cols = [c.strip(" `") for c in fk_m.group(1).split(",")]
                ref_table = fk_m.group(2)
                ref_cols = [c.strip(" `") for c in fk_m.group(3).split(",")]
                fks.append(ForeignKeyDef(columns=src_cols, ref_table=ref_table, ref_columns=ref_cols))
                continue

            # Check for CHECK constraint
            if re.match(r"^(?:CONSTRAINT\s+`?\w+`?\s+)?CHECK\b", item_s, re.IGNORECASE):
                # Check for enum: col IN ('A', 'B', ...)
                in_m = re.search(r"(\w+)\s+IN\s*\(([^)]+)\)", item_s, re.IGNORECASE)
                if in_m:
                    c_name = in_m.group(1)
                    vals = re.findall(r"'([^']*)'", in_m.group(2))
                    if vals:
                        enum_constraints[c_name] = vals
                # Check for inequality: col1 != col2 or col1 <> col2
                neq_m = re.search(r"(\w+)\s*(?:!=|<>)\s*(\w+)", item_s)
                if neq_m:
                    c1, c2 = neq_m.group(1), neq_m.group(2)
                    if c1.upper() != "NULL" and c2.upper() != "NULL":
                        no_self_loops.append((c1, c2))
                continue

            if item_s.upper().startswith("CONSTRAINT "):
                continue

            # Column definition
            col_m = re.match(
                r"^`?(\w+)`?\s+(ARRAY\s*<\s*[^>]+>|\w+(?:\s*\([^)]+\))?)(.*)$",
                item_s,
                re.IGNORECASE | re.DOTALL,
            )
            if not col_m:
                continue

            c_name = col_m.group(1)
            raw_type = col_m.group(2).strip().upper()
            rest = col_m.group(3).strip()

            is_array = raw_type.startswith("ARRAY")
            inner_type = raw_type
            if is_array:
                inner_m = re.search(r"ARRAY\s*<\s*(.+)\s*>", raw_type)
                if inner_m:
                    inner_type = inner_m.group(1).strip()

            base_type = re.sub(r"\([^)]*\)", "", inner_type).strip()
            max_len: int | None = None
            len_m = re.search(r"\((\d+)\)", inner_type)
            if len_m:
                max_len = int(len_m.group(1))

            not_null = bool(re.search(r"\bNOT\s+NULL\b", rest, re.IGNORECASE))
            is_generated = bool(re.search(r"\bAS\s*\(.*\)\s*STORED\b", rest, re.IGNORECASE | re.DOTALL))

            default_expr: str | None = None
            def_m = re.search(r"\bDEFAULT\s*\(([^)]+)\)", rest, re.IGNORECASE)
            if def_m:
                default_expr = def_m.group(1).strip().strip("'")

            cols[c_name] = ColumnDef(
                name=c_name,
                sql_type=base_type,
                is_array=is_array,
                max_length=max_len,
                not_null=not_null,
                is_generated=is_generated,
                default_expr=default_expr,
            )

        for c_name, allowed in enum_constraints.items():
            for col_key, col_def in cols.items():
                if col_key.lower() == c_name.lower():
                    col_def.allowed_values = allowed

        tables[t_name] = TableDef(
            name=t_name,
            columns=cols,
            primary_keys=pks,
            interleaved_parent=interleave_parent,
            foreign_keys=fks,
            no_self_loop_pairs=no_self_loops,
        )

    # 3. Parse CREATE PROPERTY GRAPH
    pg_m = re.search(
        r"CREATE\s+(?:OR\s+REPLACE\s+)?PROPERTY\s+GRAPH\s+`?(\w+)`?\s+"
        r"NODE\s+TABLES\s*\((.*?)\)"
        r"(?:\s*EDGE\s+TABLES\s*\((.*?)\))?\s*(?:;|$)",
        clean_ddl,
        re.IGNORECASE | re.DOTALL,
    )
    if pg_m:
        graph_name = pg_m.group(1)
        node_block = pg_m.group(2) or ""
        edge_block = pg_m.group(3) or ""

        for node_entry in _split_top_level_commas(node_block):
            header_m = re.match(r"^`?(\w+)`?(?:\s+AS\s+`?\w+`?)?", node_entry.strip(), re.IGNORECASE)
            if not header_m:
                continue
            phys_table = header_m.group(1)
            labels = re.findall(r"\bLABEL\s+`?(\w+)`?", node_entry, re.IGNORECASE)
            if labels:
                node_table_labels[phys_table].extend(labels)

        for edge_entry in _split_top_level_commas(edge_block):
            e_m = re.search(
                r"^`?(\w+)`?(?:\s+AS\s+`?(\w+)`?)?.*?"
                r"SOURCE\s+KEY\s*\(([^)]+)\)\s*REFERENCES\s+`?(\w+)`?\s*\(([^)]+)\).*?"
                r"DESTINATION\s+KEY\s*\(([^)]+)\)\s*REFERENCES\s+`?(\w+)`?\s*\(([^)]+)\)"
                r"(.*)$",
                edge_entry.strip(),
                re.IGNORECASE | re.DOTALL,
            )
            if not e_m:
                continue
            phys_table = e_m.group(1)
            alias = e_m.group(2) or phys_table
            src_keys = [k.strip(" `") for k in e_m.group(3).split(",")]
            src_ref_table = e_m.group(4)
            src_ref_keys = [k.strip(" `") for k in e_m.group(5).split(",")]
            dst_keys = [k.strip(" `") for k in e_m.group(6).split(",")]
            dst_ref_table = e_m.group(7)
            dst_ref_keys = [k.strip(" `") for k in e_m.group(8).split(",")]
            tail = e_m.group(9) or ""
            labels = re.findall(r"\bLABEL\s+`?(\w+)`?", tail, re.IGNORECASE)
            props: list[str] = []
            prop_m = re.search(r"\bPROPERTIES\s*\(([^)]+)\)", tail, re.IGNORECASE)
            if prop_m:
                for p_part in prop_m.group(1).split(","):
                    col_part = re.split(r"\bAS\b", p_part, flags=re.IGNORECASE)[0].strip(" `")
                    if col_part:
                        props.append(col_part)

            edge_defs.append(
                GraphEdgeDef(
                    physical_table=phys_table,
                    alias=alias,
                    source_keys=src_keys,
                    source_ref_table=src_ref_table,
                    source_ref_keys=src_ref_keys,
                    dest_keys=dst_keys,
                    dest_ref_table=dst_ref_table,
                    dest_ref_keys=dst_ref_keys,
                    labels=labels,
                    properties=props,
                )
            )

    return ParsedSpannerDDL(
        tables=tables,
        views=views,
        graph_name=graph_name,
        node_table_labels=dict(node_table_labels),
        edge_defs=edge_defs,
    )


# =============================================================================
# 3. SCHEMA MAPPING SPEC GENERATION (HYBRID DETERMINISTIC + LLM)
# =============================================================================

def load_triple_loader_system_instruction() -> str:
    """Loads system instructions from skills/rdf-triples-to-spanner-loader/SKILL.md."""
    fallback = (
        "You are a Cloud Spanner Graph Data Ingestion & Semantic Mapping Architect. "
        "Synthesize a deterministic JSON Schema Mapping Manifesto binding OWL classes, "
        "datatype properties, embedded foreign keys, and edge tables to Cloud Spanner DDL columns."
    )
    return load_skill_instructions("rdf-triples-to-spanner-loader", fallback)


def _singularize_norms(name: str) -> set[str]:
    """Returns normalized candidate forms (singular/plural) for matching class <-> table names."""
    n = _norm(name)
    candidates = {n}
    if n.endswith("ies") and len(n) > 3:
        candidates.add(n[:-3] + "y")
    if n.endswith("ses") and len(n) > 3:
        candidates.add(n[:-2])
    if n.endswith("s") and len(n) > 1:
        candidates.add(n[:-1])
    if n == "people":
        candidates.add("person")
    return candidates


def build_deterministic_mapping_spec(
    ttl_content: str,
    ddl_content: str,
    shacl_content: str | None = None,
    parsed_ddl: ParsedSpannerDDL | None = None,
) -> dict[str, Any]:
    """Deterministically constructs the Schema Mapping Spec from the DDL, Property Graph, and Ontology."""
    if parsed_ddl is None:
        parsed_ddl = parse_spanner_ddl(ddl_content)

    ont_g = rdflib.Graph()
    ont_g.parse(data=ttl_content, format="turtle")
    if shacl_content:
        ont_g.parse(data=shacl_content, format="turtle")

    # 1. Discover OWL classes & map to concrete tables
    owl_classes: dict[str, str] = {}  # local_name -> full_uri
    for s in set(ont_g.subjects(RDF.type, OWL.Class)) | set(ont_g.subjects(RDF.type, RDFS.Class)):
        if isinstance(s, rdflib.URIRef):
            owl_classes[_local_name(s)] = str(s)
    for _, _, o in ont_g.triples((None, SH.targetClass, None)):
        if isinstance(o, rdflib.URIRef) and _local_name(o) not in owl_classes:
            owl_classes[_local_name(o)] = str(o)

    # Map concrete table -> primary OWL class local name
    table_to_class_local: dict[str, str] = {}
    class_norm_to_table: dict[str, str] = {}

    # First pass: use CREATE PROPERTY GRAPH NODE TABLES first label
    for t_name, labels in parsed_ddl.node_table_labels.items():
        if t_name in parsed_ddl.views or t_name not in parsed_ddl.tables:
            continue
        if labels:
            first_label = labels[0]
            # Match against owl_classes
            matched_cls = first_label
            for cls_local in owl_classes:
                if _norm(cls_local) == _norm(first_label):
                    matched_cls = cls_local
                    break
            table_to_class_local[t_name] = matched_cls
            class_norm_to_table[_norm(matched_cls)] = t_name

    # Second pass: match any remaining physical tables whose name matches an OWL class (e.g., Employments -> Employment)
    for t_name in parsed_ddl.tables:
        if t_name in table_to_class_local:
            continue
        t_norms = _singularize_norms(t_name)
        for cls_local in owl_classes:
            if _norm(cls_local) in t_norms:
                table_to_class_local[t_name] = cls_local
                class_norm_to_table[_norm(cls_local)] = t_name
                break

    classes_spec = []
    for cls_local, cls_uri in sorted(owl_classes.items()):
        t_name = class_norm_to_table.get(_norm(cls_local))
        if t_name and t_name in parsed_ddl.tables:
            t_def = parsed_ddl.tables[t_name]
            gen_cols = [c.name for c in t_def.columns.values() if c.is_generated]
            interleave_info = None
            if t_def.interleaved_parent:
                interleave_info = {
                    "parent_table": t_def.interleaved_parent,
                    "parent_pk_column": t_def.primary_keys[0] if len(t_def.primary_keys) > 1 else None,
                    "via_property_local_name": None,
                }
            classes_spec.append({
                "class_uri": cls_uri,
                "local_name": cls_local,
                "is_concrete": True,
                "table_name": t_name,
                "primary_key_columns": list(t_def.primary_keys),
                "interleaved_parent": interleave_info,
                "generated_columns": gen_cols,
            })
        else:
            classes_spec.append({
                "class_uri": cls_uri,
                "local_name": cls_local,
                "is_concrete": False,
                "table_name": None,
                "primary_key_columns": [],
                "interleaved_parent": None,
                "generated_columns": [],
            })

    # 2. Discover Datatype Properties
    dt_props: dict[str, str] = {}  # local_name -> full_uri
    for s in ont_g.subjects(RDF.type, OWL.DatatypeProperty):
        if isinstance(s, rdflib.URIRef):
            dt_props[_local_name(s)] = str(s)
    for _, _, path_uri in ont_g.triples((None, SH.path, None)):
        if isinstance(path_uri, rdflib.URIRef):
            ln = _local_name(path_uri)
            if ln not in dt_props and (path_uri, RDF.type, OWL.ObjectProperty) not in ont_g:
                dt_props[ln] = str(path_uri)
    # Include rdfs:label as a fallback naming property
    dt_props.setdefault("label", str(RDFS.label))

    datatype_properties_spec = []
    for t_name, t_def in parsed_ddl.tables.items():
        if t_name not in table_to_class_local:
            continue
        for col_name, col_def in t_def.columns.items():
            if col_def.is_generated:
                continue
            col_norm = _norm(col_name)
            col_norms = _singularize_norms(col_name)
            is_pk = col_name in t_def.primary_keys

            # Direct match or suffix/plural match against datatype properties
            matched_prop: tuple[str, str, str | None] | None = None
            for p_local, p_uri in dt_props.items():
                p_norm = _norm(p_local)
                if p_norm in col_norms or (col_def.is_array and (p_norm + "s") == col_norm):
                    matched_prop = (p_local, p_uri, None)
                    break

            # Check for nested blank node column pattern: e.g. BillingAddress_StreetLine -> billingAddress / streetLine
            if not matched_prop and "_" in col_name:
                prefix_part, suffix_part = col_name.split("_", 1)
                pref_norm = _norm(prefix_part)
                suff_norm = _norm(suffix_part)
                outer_local = None
                inner_local = None
                for p_local in list(dt_props.keys()) + [_local_name(s) for s in ont_g.subjects(RDF.type, OWL.ObjectProperty)]:
                    if _norm(p_local) == pref_norm:
                        outer_local = p_local
                    if _norm(p_local) == suff_norm:
                        inner_local = p_local
                if outer_local and inner_local:
                    datatype_properties_spec.append({
                        "property_uri": dt_props.get(outer_local, outer_local),
                        "local_name": outer_local,
                        "nested_path_local_name": inner_local,
                        "table_name": t_name,
                        "column_name": col_name,
                        "sql_type": col_def.sql_type,
                        "is_array": col_def.is_array,
                        "is_primary_key": is_pk,
                    })
                    continue

            # Fallback for DiseaseName / TargetName -> rdfs:label
            if not matched_prop and col_norm.endswith("name") and not is_pk:
                cls_norm = _norm(table_to_class_local[t_name])
                if col_norm == cls_norm + "name":
                    matched_prop = ("label", str(RDFS.label), None)

            if matched_prop:
                p_local, p_uri, nested_ln = matched_prop
                datatype_properties_spec.append({
                    "property_uri": p_uri,
                    "local_name": p_local,
                    "nested_path_local_name": nested_ln,
                    "table_name": t_name,
                    "column_name": col_name,
                    "sql_type": col_def.sql_type,
                    "is_array": col_def.is_array,
                    "is_primary_key": is_pk,
                })

    # 3. Discover Object Properties from CREATE PROPERTY GRAPH EDGE TABLES + DDL FKs
    obj_props: dict[str, str] = {}  # local_name -> full_uri
    for s in (
        set(ont_g.subjects(RDF.type, OWL.ObjectProperty))
        | set(ont_g.subjects(RDF.type, OWL.TransitiveProperty))
        | set(ont_g.subjects(RDF.type, OWL.SymmetricProperty))
        | set(ont_g.subjects(RDF.type, OWL.InverseFunctionalProperty))
    ):
        if isinstance(s, rdflib.URIRef):
            obj_props[_local_name(s)] = str(s)

    object_properties_spec = []
    seen_obj_mappings: set[tuple[str, str, str, str, str]] = set()

    # Map every GraphEdgeDef from CREATE PROPERTY GRAPH
    for ed in parsed_ddl.edge_defs:
        phys_t = ed.physical_table
        src_t = ed.source_ref_table
        dst_t = ed.dest_ref_table
        if phys_t not in parsed_ddl.tables:
            continue
        phys_def = parsed_ddl.tables[phys_t]

        # Match labels on the edge to OWL ObjectProperty local names
        matched_pred_locals: list[str] = []
        for idx_lbl, lbl in enumerate(ed.labels):
            lbl_norm = _norm(lbl)
            for op_local in obj_props:
                if _norm(op_local) == lbl_norm:
                    # Prefer the primary (first) label on the edge table, unless it's an inverse/alias
                    if idx_lbl == 0 or len(ed.labels) == 1 or phys_t in table_to_class_local:
                        matched_pred_locals.append(op_local)
        if not matched_pred_locals and ed.labels:
            for lbl in ed.labels:
                for op_local in obj_props:
                    if _norm(op_local) == _norm(lbl):
                        matched_pred_locals.append(op_local)

        # Determine if phys_t is a Node Table (EMBEDDED_FK) or a Dedicated Edge Table (EDGE_TABLE)
        is_node_table = (phys_t in parsed_ddl.node_table_labels) and (phys_t in (src_t, dst_t))
        # Special case: self-referential node table (e.g. Employees.ManagerId or SystemProcesses.ParentProcessNodeId)
        if phys_t == src_t == dst_t and phys_t in parsed_ddl.node_table_labels:
            is_node_table = True

        # Map reified edge properties if any non-key columns exist on the edge
        reified_map: dict[str, str] = {}
        for col_name, col_def in phys_def.columns.items():
            if col_def.is_generated or col_name in phys_def.primary_keys:
                continue
            if col_name in ed.source_keys or col_name in ed.dest_keys:
                continue
            for dt_local in dt_props:
                dt_norm = _norm(dt_local)
                c_norm = _norm(col_name)
                if dt_norm == c_norm or c_norm.endswith(dt_norm):
                    reified_map[dt_local] = col_name

        for op_local in matched_pred_locals:
            op_uri = obj_props.get(op_local, op_local)
            if is_node_table:
                # Embedded FK on either src_t or dst_t
                if phys_t == src_t and phys_t != dst_t:
                    fk_table = src_t
                    fk_col = ed.dest_keys[0]
                elif phys_t == dst_t and phys_t != src_t:
                    fk_table = dst_t
                    fk_col = ed.source_keys[0]
                else:
                    # Self-referential node table (e.g. Employees: EmployeeId -> ManagerId, or SystemProcesses: ParentProcessNodeId -> SystemProcessId)
                    fk_table = phys_t
                    pk_col = phys_def.primary_keys[0]
                    fk_col = ed.dest_keys[0] if ed.source_keys[0] == pk_col else ed.source_keys[0]

                key_sig = (op_local, src_t, dst_t, fk_table, fk_col)
                if key_sig not in seen_obj_mappings:
                    seen_obj_mappings.add(key_sig)
                    object_properties_spec.append({
                        "property_uri": op_uri,
                        "local_name": op_local,
                        "mapping_type": "EMBEDDED_FK",
                        "subject_table": src_t,
                        "object_table": dst_t,
                        "fk_table": fk_table,
                        "fk_column": fk_col,
                        "fk_on_subject": (ed.source_keys[0] == phys_def.primary_keys[0]) if src_t == dst_t else (fk_table == src_t),
                        "is_array": phys_def.columns[fk_col].is_array if fk_col in phys_def.columns else False,
                        "edge_table": None,
                        "subject_fk_column": None,
                        "object_fk_column": None,
                        "synthetic_edge_pk_column": None,
                        "extra_columns": {},
                        "reified_edge_properties": reified_map,
                    })
            else:
                # Dedicated Edge Table
                src_col = ed.source_keys[0]
                dst_col = ed.dest_keys[0]
                synth_pk = None
                if len(phys_def.primary_keys) == 1 and phys_def.primary_keys[0] not in (src_col, dst_col):
                    synth_pk = phys_def.primary_keys[0]

                key_sig = (op_local, src_t, dst_t, phys_t, f"{src_col}:{dst_col}")
                if key_sig not in seen_obj_mappings:
                    seen_obj_mappings.add(key_sig)
                    object_properties_spec.append({
                        "property_uri": op_uri,
                        "local_name": op_local,
                        "mapping_type": "EDGE_TABLE",
                        "subject_table": src_t,
                        "object_table": dst_t,
                        "fk_table": None,
                        "fk_column": None,
                        "fk_on_subject": True,
                        "is_array": False,
                        "edge_table": phys_t,
                        "subject_fk_column": src_col,
                        "object_fk_column": dst_col,
                        "synthetic_edge_pk_column": synth_pk,
                        "extra_columns": {},
                        "reified_edge_properties": reified_map,
                    })

    # Also check for FKs on concrete tables that were not listed in EDGE TABLES (e.g. Employments in 12_n_ary_relations or Divisions in 07)
    for t_name, t_def in parsed_ddl.tables.items():
        if t_name not in table_to_class_local:
            continue
        # Interleaved parent FK (e.g. Divisions -> Departments via subDepartmentOf)
        if t_def.interleaved_parent and len(t_def.primary_keys) >= 2:
            parent_t = t_def.interleaved_parent
            parent_pk_col = t_def.primary_keys[0]
            for op_local, op_uri in obj_props.items():
                if "department" in _norm(op_local) or "parent" in _norm(op_local) or "sub" in _norm(op_local):
                    key_sig = (op_local, t_name, parent_t, t_name, parent_pk_col)
                    if key_sig not in seen_obj_mappings:
                        seen_obj_mappings.add(key_sig)
                        object_properties_spec.append({
                            "property_uri": op_uri,
                            "local_name": op_local,
                            "mapping_type": "EMBEDDED_FK",
                            "subject_table": t_name,
                            "object_table": parent_t,
                            "fk_table": t_name,
                            "fk_column": parent_pk_col,
                            "fk_on_subject": True,
                            "is_array": False,
                            "edge_table": None,
                            "subject_fk_column": None,
                            "object_fk_column": None,
                            "synthetic_edge_pk_column": None,
                            "extra_columns": {},
                            "reified_edge_properties": {},
                        })

        # Explicit FOREIGN KEYs on node tables (e.g. Employments.PersonId / CompanyId in 12_n_ary_relations)
        for fk in t_def.foreign_keys:
            if len(fk.columns) != 1:
                continue
            fk_col = fk.columns[0]
            ref_t = fk.ref_table
            for op_local, op_uri in obj_props.items():
                op_n = _norm(op_local)
                col_n = _norm(fk_col)
                ref_n = _norm(table_to_class_local.get(ref_t, ref_t))
                # e.g. hasEmployee -> PersonId, hasEmployer -> CompanyId
                if (
                    op_n == col_n
                    or col_n.startswith(op_n)
                    or ref_n in op_n
                    or ("employee" in op_n and "person" in col_n)
                    or ("employer" in op_n and "company" in col_n)
                ):
                    key_sig = (op_local, t_name, ref_t, t_name, fk_col)
                    if key_sig not in seen_obj_mappings:
                        seen_obj_mappings.add(key_sig)
                        object_properties_spec.append({
                            "property_uri": op_uri,
                            "local_name": op_local,
                            "mapping_type": "EMBEDDED_FK",
                            "subject_table": t_name,
                            "object_table": ref_t,
                            "fk_table": t_name,
                            "fk_column": fk_col,
                            "fk_on_subject": True,
                            "is_array": False,
                            "edge_table": None,
                            "subject_fk_column": None,
                            "object_fk_column": None,
                            "synthetic_edge_pk_column": None,
                            "extra_columns": {},
                            "reified_edge_properties": {},
                        })

    return {
        "classes": classes_spec,
        "datatype_properties": datatype_properties_spec,
        "object_properties": object_properties_spec,
    }


def generate_schema_mapping_spec(
    ttl_content: str,
    ddl_content: str,
    shacl_content: str | None = None,
    use_llm: bool = True,
    model_name: str = DEFAULT_GEMINI_MODEL,
) -> dict[str, Any]:
    """Generates a grounded Schema Mapping Spec by combining deterministic DDL/Graph analysis with Gemini."""
    parsed_ddl = parse_spanner_ddl(ddl_content)
    det_spec = build_deterministic_mapping_spec(
        ttl_content=ttl_content,
        ddl_content=ddl_content,
        shacl_content=shacl_content,
        parsed_ddl=parsed_ddl,
    )

    if not use_llm:
        return det_spec

    try:
        client = _get_client()
        prompt = f"""Analyze the following OWL Ontology, optional SHACL constraints, and target Cloud Spanner DDL, and output the JSON Schema Mapping Manifesto according to your system instructions.

### Source OWL Ontology (.ttl):
```turtle
{ttl_content}
```
"""
        if shacl_content:
            prompt += f"""
### Companion SHACL Shapes (shacl.ttl):
```turtle
{shacl_content}
```
"""
        prompt += f"""
### Target Cloud Spanner Relational & Property Graph DDL (.sql):
```sql
{ddl_content}
```

Output ONLY the valid JSON Schema Mapping Manifesto with keys `"classes"`, `"datatype_properties"`, and `"object_properties"`.
"""
        response = _generate_with_retry(
            client=client,
            model=model_name,
            contents=prompt,
            config=types.GenerateContentConfig(
                system_instruction=load_triple_loader_system_instruction(),
                temperature=0.0,
            ),
        )
        llm_spec = extract_json_payload(response.text)
        return _merge_and_ground_mapping_specs(det_spec, llm_spec, parsed_ddl)
    except Exception:
        # Gracefully fall back to the deterministic DDL + Property Graph spec
        return det_spec


def _merge_and_ground_mapping_specs(
    det_spec: dict[str, Any],
    llm_spec: dict[str, Any],
    parsed_ddl: ParsedSpannerDDL,
) -> dict[str, Any]:
    """Merges Gemini's Schema Mapping Spec with the deterministic spec, verifying every table/column against parsed_ddl."""
    merged = {
        "classes": list(det_spec.get("classes", [])),
        "datatype_properties": list(det_spec.get("datatype_properties", [])),
        "object_properties": list(det_spec.get("object_properties", [])),
    }

    det_cls_names = {_norm(c["local_name"]) for c in merged["classes"] if c.get("is_concrete")}
    for c in llm_spec.get("classes", []):
        t_name = c.get("table_name")
        ln = c.get("local_name", "")
        if c.get("is_concrete") and t_name in parsed_ddl.tables and _norm(ln) not in det_cls_names:
            t_def = parsed_ddl.tables[t_name]
            merged["classes"].append({
                "class_uri": c.get("class_uri", ln),
                "local_name": ln,
                "is_concrete": True,
                "table_name": t_name,
                "primary_key_columns": list(t_def.primary_keys),
                "interleaved_parent": c.get("interleaved_parent"),
                "generated_columns": [col.name for col in t_def.columns.values() if col.is_generated],
            })
            det_cls_names.add(_norm(ln))

    det_dt_keys = {
        (_norm(d["local_name"]), _norm(d.get("nested_path_local_name") or ""), d["table_name"], d["column_name"])
        for d in merged["datatype_properties"]
    }
    for d in llm_spec.get("datatype_properties", []):
        t_name = d.get("table_name")
        c_name = d.get("column_name")
        ln = d.get("local_name", "")
        nested_ln = d.get("nested_path_local_name")
        if t_name in parsed_ddl.tables and c_name in parsed_ddl.tables[t_name].columns:
            col_def = parsed_ddl.tables[t_name].columns[c_name]
            if col_def.is_generated:
                continue
            k = (_norm(ln), _norm(nested_ln or ""), t_name, c_name)
            if k not in det_dt_keys:
                merged["datatype_properties"].append({
                    "property_uri": d.get("property_uri", ln),
                    "local_name": ln,
                    "nested_path_local_name": nested_ln,
                    "table_name": t_name,
                    "column_name": c_name,
                    "sql_type": col_def.sql_type,
                    "is_array": col_def.is_array,
                    "is_primary_key": c_name in parsed_ddl.tables[t_name].primary_keys,
                })
                det_dt_keys.add(k)

    det_obj_keys = {
        (_norm(o["local_name"]), o.get("subject_table"), o.get("object_table"))
        for o in merged["object_properties"]
    }
    for o in llm_spec.get("object_properties", []):
        ln = o.get("local_name", "")
        st = o.get("subject_table")
        ot = o.get("object_table")
        mtype = o.get("mapping_type")
        if st not in parsed_ddl.tables or ot not in parsed_ddl.tables:
            continue
        if (_norm(ln), st, ot) in det_obj_keys:
            continue
        if mtype == "EMBEDDED_FK":
            fkt = o.get("fk_table")
            fkc = o.get("fk_column")
            if fkt in parsed_ddl.tables and fkc in parsed_ddl.tables[fkt].columns:
                merged["object_properties"].append({
                    "property_uri": o.get("property_uri", ln),
                    "local_name": ln,
                    "mapping_type": "EMBEDDED_FK",
                    "subject_table": st,
                    "object_table": ot,
                    "fk_table": fkt,
                    "fk_column": fkc,
                    "fk_on_subject": fkt == st,
                    "is_array": parsed_ddl.tables[fkt].columns[fkc].is_array,
                    "edge_table": None,
                    "subject_fk_column": None,
                    "object_fk_column": None,
                    "synthetic_edge_pk_column": None,
                    "extra_columns": o.get("extra_columns") or {},
                    "reified_edge_properties": o.get("reified_edge_properties") or {},
                })
                det_obj_keys.add((_norm(ln), st, ot))
        elif mtype == "EDGE_TABLE":
            et = o.get("edge_table")
            sc = o.get("subject_fk_column")
            oc = o.get("object_fk_column")
            if et in parsed_ddl.tables and sc in parsed_ddl.tables[et].columns and oc in parsed_ddl.tables[et].columns:
                merged["object_properties"].append({
                    "property_uri": o.get("property_uri", ln),
                    "local_name": ln,
                    "mapping_type": "EDGE_TABLE",
                    "subject_table": st,
                    "object_table": ot,
                    "fk_table": None,
                    "fk_column": None,
                    "fk_on_subject": True,
                    "is_array": False,
                    "edge_table": et,
                    "subject_fk_column": sc,
                    "object_fk_column": oc,
                    "synthetic_edge_pk_column": o.get("synthetic_edge_pk_column"),
                    "extra_columns": o.get("extra_columns") or {},
                    "reified_edge_properties": o.get("reified_edge_properties") or {},
                })
                det_obj_keys.add((_norm(ln), st, ot))

    return merged


# =============================================================================
# 4. DETERMINISTIC RDFLIB TRIPLE ENGINE -> SPANNER SQL DML
# =============================================================================

TBOX_SYSTEM_CLASSES = {
    OWL.Ontology,
    OWL.Class,
    RDFS.Class,
    OWL.ObjectProperty,
    OWL.DatatypeProperty,
    OWL.TransitiveProperty,
    OWL.SymmetricProperty,
    OWL.FunctionalProperty,
    OWL.InverseFunctionalProperty,
    OWL.Restriction,
    OWL.AllDisjointClasses,
    SH.NodeShape,
    SH.PropertyShape,
}


def _guess_rdf_format(filepath: str) -> str:
    ext = os.path.splitext(filepath)[1].lower()
    return {
        ".ttl": "turtle",
        ".nt": "nt",
        ".rdf": "xml",
        ".xml": "xml",
        ".owl": "xml",
        ".jsonld": "json-ld",
        ".n3": "n3",
    }.get(ext, "turtle")


def _normalize_pk_value(raw_id: str, max_len: int | None = 36) -> str:
    """Normalizes an identifier or URI local name to fit within Spanner PK column length."""
    limit = max_len or 36
    if len(raw_id) <= limit:
        return raw_id
    hashed = str(uuid.uuid5(uuid.NAMESPACE_URL, raw_id))
    return hashed[:limit]


def _format_sql_literal(value: Any, col_def: ColumnDef) -> str:
    """Formats a Python/RDF literal value into a GoogleSQL literal for Cloud Spanner."""
    if value is None:
        return "NULL"

    if col_def.is_array:
        items = value if isinstance(value, (list, tuple, set)) else [value]
        elem_col = dataclasses.replace(col_def, is_array=False)
        formatted_items = [_format_sql_literal(v, elem_col) for v in items if v is not None]
        return "[" + ", ".join(formatted_items) + "]"

    sql_t = col_def.sql_type.upper()
    s_val = str(value).strip()

    if sql_t in ("INT64", "INT", "INTEGER"):
        try:
            return str(int(float(s_val)))
        except Exception:
            return str(abs(hash(s_val)) % 1000000)

    if sql_t in ("FLOAT64", "FLOAT", "DOUBLE"):
        try:
            return str(float(s_val))
        except Exception:
            return "0.0"

    if sql_t in ("NUMERIC", "BIGNUMERIC", "DECIMAL"):
        try:
            num_v = float(s_val)
            return f"NUMERIC '{num_v:.2f}'"
        except Exception:
            return "NUMERIC '0.00'"

    if sql_t in ("BOOL", "BOOLEAN"):
        if isinstance(value, bool):
            return "TRUE" if value else "FALSE"
        return "TRUE" if s_val.lower() in ("true", "1", "yes") else "FALSE"

    if sql_t == "DATE":
        date_part = s_val[:10] if len(s_val) >= 10 else "2025-01-01"
        return f"DATE '{date_part}'"

    if sql_t == "TIMESTAMP":
        ts = s_val
        if len(ts) == 10 and re.match(r"^\d{4}-\d{2}-\d{2}$", ts):
            ts = f"{ts}T00:00:00Z"
        elif not ts.endswith("Z") and "+" not in ts[10:] and "-" not in ts[10:]:
            ts = f"{ts}Z"
        return f"TIMESTAMP '{ts}'"

    # Default: STRING
    if col_def.allowed_values and s_val not in col_def.allowed_values:
        s_val = col_def.allowed_values[0]
    if col_def.max_length and len(s_val) > col_def.max_length:
        s_val = s_val[: col_def.max_length]
    escaped = s_val.replace("\\", "\\\\").replace("'", "\\'")
    return f"'{escaped}'"


def _default_for_not_null(col_def: ColumnDef, row_pk: str) -> Any:
    """Synthesizes a constraint-compliant fallback value when a NOT NULL column is omitted in RDF."""
    if col_def.default_expr is not None:
        return col_def.default_expr
    if col_def.allowed_values:
        return col_def.allowed_values[0]
    if col_def.is_array:
        return []
    sql_t = col_def.sql_type.upper()
    if sql_t in ("INT64", "INT", "INTEGER"):
        return 1
    if sql_t in ("FLOAT64", "FLOAT", "DOUBLE"):
        return 1.0
    if sql_t in ("NUMERIC", "BIGNUMERIC", "DECIMAL"):
        return "1.00"
    if sql_t in ("BOOL", "BOOLEAN"):
        return False
    if sql_t == "DATE":
        return "2025-01-01"
    if sql_t == "TIMESTAMP":
        return "2025-01-01T00:00:00Z"
    fallback = f"{col_def.name}_{row_pk}"
    if col_def.max_length:
        fallback = fallback[: col_def.max_length]
    return fallback


def translate_triples_to_dml(
    triples_path: str,
    ddl_content: str,
    mapping_spec: dict[str, Any],
    parsed_ddl: ParsedSpannerDDL | None = None,
) -> tuple[list[str], dict[str, int]]:
    """Deterministically converts an RDF triples file into topologically sorted GoogleSQL INSERTs.

    Returns:
        (dml_statements, table_row_counts)
    """
    if parsed_ddl is None:
        parsed_ddl = parse_spanner_ddl(ddl_content)

    g = rdflib.Graph()
    g.parse(triples_path, format=_guess_rdf_format(triples_path))

    # 1. Index mapping spec
    concrete_class_to_table: dict[str, str] = {}
    for c in mapping_spec.get("classes", []):
        if c.get("is_concrete") and c.get("table_name") in parsed_ddl.tables:
            concrete_class_to_table[_norm(c["local_name"])] = c["table_name"]

    # Map (table_name, prop_norm, nested_norm) -> column_name
    dt_map: dict[tuple[str, str, str], dict[str, Any]] = {}
    pk_prop_by_table: dict[str, str] = {}  # table_name -> prop_norm that sets PK
    for d in mapping_spec.get("datatype_properties", []):
        t_name = d["table_name"]
        p_norm = _norm(d["local_name"])
        n_norm = _norm(d.get("nested_path_local_name") or "")
        dt_map[(t_name, p_norm, n_norm)] = d
        if d.get("is_primary_key") and not n_norm:
            pk_prop_by_table[t_name] = p_norm

    # Map (prop_norm, subject_table, object_table) -> list of object_property specs
    obj_map: dict[tuple[str, str, str], list[dict[str, Any]]] = defaultdict(list)
    obj_by_prop: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for o in mapping_spec.get("object_properties", []):
        p_norm = _norm(o["local_name"])
        st = o["subject_table"]
        ot = o["object_table"]
        obj_map[(p_norm, st, ot)].append(o)
        obj_by_prop[p_norm].append(o)

    # 2. Extract ABox instances, literals, nested blank-node literals, object triples, and reifications
    tbox_subjects: set[rdflib.term.Node] = set()
    statement_subjects: set[rdflib.term.Node] = set()
    entity_classes: dict[str, list[str]] = defaultdict(list)

    for s, _, o in g.triples((None, RDF.type, None)):
        if o in TBOX_SYSTEM_CLASSES:
            tbox_subjects.add(s)
        elif o == RDF.Statement:
            statement_subjects.add(s)
        elif isinstance(s, rdflib.URIRef):
            if o != OWL.NamedIndividual:
                entity_classes[str(s)].append(_local_name(o))

    # Extract RDF Reification statements: (subj_str, pred_norm, obj_str) -> {edge_prop_norm: value}
    reified_props: dict[tuple[str, str, str], dict[str, Any]] = defaultdict(dict)
    for stmt_node in statement_subjects:
        s_val = g.value(stmt_node, RDF.subject)
        p_val = g.value(stmt_node, RDF.predicate)
        o_val = g.value(stmt_node, RDF.object)
        if s_val is not None and p_val is not None and o_val is not None:
            key = (str(s_val), _norm(_local_name(p_val)), str(o_val))
            for _, ep, eo in g.triples((stmt_node, None, None)):
                if ep in (RDF.type, RDF.subject, RDF.predicate, RDF.object):
                    continue
                if isinstance(eo, rdflib.Literal):
                    reified_props[key][_norm(_local_name(ep))] = str(eo)

    # Resolve concrete table for each subject URI
    entity_table: dict[str, str] = {}
    for subj_str, cls_locals in entity_classes.items():
        for cls_ln in cls_locals:
            t_name = concrete_class_to_table.get(_norm(cls_ln))
            if t_name:
                entity_table[subj_str] = t_name
                break

    # Collect literals & object relationships
    entity_literals: dict[str, dict[tuple[str, str], list[str]]] = defaultdict(lambda: defaultdict(list))
    object_triples: list[tuple[str, str, str]] = []

    for s, p, o in g:
        if s in tbox_subjects or s in statement_subjects or isinstance(s, rdflib.BNode):
            continue
        if p == RDF.type:
            continue
        s_str = str(s)
        p_norm = _norm(_local_name(p))

        if isinstance(o, rdflib.Literal):
            entity_literals[s_str][(p_norm, "")].append(str(o))
        elif isinstance(o, rdflib.BNode):
            # 2-hop blank node value object (e.g. ex:billingAddress [ ex:streetLine "..." ])
            for _, np, no in g.triples((o, None, None)):
                if isinstance(no, rdflib.Literal):
                    np_norm = _norm(_local_name(np))
                    entity_literals[s_str][(p_norm, np_norm)].append(str(no))
        elif isinstance(o, rdflib.URIRef):
            if o in TBOX_SYSTEM_CLASSES:
                continue
            object_triples.append((s_str, p_norm, str(o)))

    # Infer entity_table for any untyped URIs via <ClassName>_<ID> URI prefix convention or unambiguous object_triples
    all_candidate_uris = set(entity_literals.keys())
    for s_str, _, o_str in object_triples:
        all_candidate_uris.add(s_str)
        all_candidate_uris.add(o_str)
    for u_str in all_candidate_uris:
        if u_str not in entity_table:
            ln = _local_name(u_str)
            if "_" in ln:
                prefix_norm = _norm(ln.split("_", 1)[0])
                if prefix_norm in concrete_class_to_table:
                    entity_table[u_str] = concrete_class_to_table[prefix_norm]

    for s_str, p_norm, o_str in object_triples:
        candidates = obj_by_prop.get(p_norm, [])
        if s_str not in entity_table and len({c["subject_table"] for c in candidates}) == 1:
            entity_table[s_str] = candidates[0]["subject_table"]
        if o_str not in entity_table and len({c["object_table"] for c in candidates}) == 1:
            entity_table[o_str] = candidates[0]["object_table"]

    # 3. Resolve Primary Keys for all known entities
    resolved_pk: dict[str, str] = {}
    for subj_str, t_name in entity_table.items():
        t_def = parsed_ddl.tables[t_name]
        own_pk_col = t_def.primary_keys[-1]
        max_len = t_def.columns[own_pk_col].max_length if own_pk_col in t_def.columns else 36

        # Check if a datatype property explicitly sets the PK column
        pk_prop = pk_prop_by_table.get(t_name)
        nat_vals = entity_literals[subj_str].get((pk_prop, ""), []) if pk_prop else []
        if nat_vals and (max_len is None or len(nat_vals[0]) <= max_len):
            resolved_pk[subj_str] = nat_vals[0]
        else:
            resolved_pk[subj_str] = _normalize_pk_value(_local_name(subj_str), max_len)

    # 4. Build Node Table Rows & Populate Datatype Properties
    node_rows: dict[str, dict[str, dict[str, Any]]] = defaultdict(dict)  # table_name -> {subj_str -> {col: val}}
    for subj_str, t_name in entity_table.items():
        t_def = parsed_ddl.tables[t_name]
        own_pk_col = t_def.primary_keys[-1]
        row: dict[str, Any] = {own_pk_col: resolved_pk[subj_str]}

        for (p_norm, n_norm), vals in entity_literals[subj_str].items():
            d_spec = dt_map.get((t_name, p_norm, n_norm))
            if not d_spec:
                continue
            col_name = d_spec["column_name"]
            if col_name == own_pk_col:
                continue
            if d_spec.get("is_array"):
                row[col_name] = list(dict.fromkeys(vals))
            else:
                row[col_name] = vals[0]

        node_rows[t_name][subj_str] = row

    # 5. Process Object Triples -> Embedded FKs & Edge Table Rows
    edge_rows: dict[str, dict[tuple[Any, ...], dict[str, Any]]] = defaultdict(dict)
    synthetic_edge_counters: dict[str, int] = defaultdict(int)

    for s_str, p_norm, o_str in object_triples:
        st = entity_table.get(s_str)
        ot = entity_table.get(o_str)
        if not st or not ot:
            continue

        specs = obj_map.get((p_norm, st, ot), [])
        if not specs:
            continue

        s_pk = resolved_pk[s_str]
        o_pk = resolved_pk[o_str]
        r_props = reified_props.get((s_str, p_norm, o_str), {})

        for spec in specs:
            mtype = spec["mapping_type"]
            if mtype == "EMBEDDED_FK":
                fkt = spec["fk_table"]
                fkc = spec["fk_column"]
                fk_on_subj = spec.get("fk_on_subject", fkt == st)
                target_entity = s_str if fk_on_subj else o_str
                ref_pk_val = o_pk if fk_on_subj else s_pk

                if target_entity in node_rows[fkt]:
                    if spec.get("is_array"):
                        arr = node_rows[fkt][target_entity].setdefault(fkc, [])
                        if ref_pk_val not in arr:
                            arr.append(ref_pk_val)
                    else:
                        node_rows[fkt][target_entity][fkc] = ref_pk_val

                    # Populate any reified edge properties stored on the node table (e.g., Accounts.DeviceFirstUsed)
                    for rp_local, rp_col in (spec.get("reified_edge_properties") or {}).items():
                        rp_val = r_props.get(_norm(rp_local))
                        if rp_val is not None:
                            node_rows[fkt][target_entity][rp_col] = rp_val

            elif mtype == "EDGE_TABLE":
                et = spec["edge_table"]
                sc = spec["subject_fk_column"]
                oc = spec["object_fk_column"]
                et_def = parsed_ddl.tables[et]

                # Skip self-loops if table has a no-self-loop CHECK constraint
                if s_pk == o_pk and et_def.no_self_loop_pairs:
                    continue

                erow: dict[str, Any] = {sc: s_pk, oc: o_pk}
                for ex_col, ex_val in (spec.get("extra_columns") or {}).items():
                    erow[ex_col] = ex_val
                for rp_local, rp_col in (spec.get("reified_edge_properties") or {}).items():
                    rp_val = r_props.get(_norm(rp_local))
                    if rp_val is not None:
                        erow[rp_col] = rp_val

                synth_pk_col = spec.get("synthetic_edge_pk_column")
                if synth_pk_col:
                    dedup_key = (s_pk, o_pk, p_norm)
                    if dedup_key not in edge_rows[et]:
                        synthetic_edge_counters[et] += 1
                        erow[synth_pk_col] = f"edge_{synthetic_edge_counters[et]:04d}"
                        edge_rows[et][dedup_key] = erow
                    else:
                        edge_rows[et][dedup_key].update(erow)
                else:
                    pk_tuple = tuple(erow.get(pk_c) for pk_c in et_def.primary_keys)
                    # For symmetric tables where both (A, B) and (B, A) might violate single-direction storage if desired,
                    # keep exact PK tuple deduplicated
                    if pk_tuple not in edge_rows[et]:
                        edge_rows[et][pk_tuple] = erow
                    else:
                        edge_rows[et][pk_tuple].update(erow)

    # 6. Ensure all NOT NULL columns and Foreign Keys on Node/Edge rows are satisfied
    for t_name, subj_dict in node_rows.items():
        t_def = parsed_ddl.tables[t_name]
        # Build quick lookup of FK column -> referenced table's available PKs
        fk_col_to_ref_table: dict[str, str] = {}
        for fk in t_def.foreign_keys:
            if len(fk.columns) == 1:
                fk_col_to_ref_table[fk.columns[0]] = fk.ref_table
        if t_def.interleaved_parent and len(t_def.primary_keys) >= 2:
            fk_col_to_ref_table[t_def.primary_keys[0]] = t_def.interleaved_parent

        own_pk_col = t_def.primary_keys[-1]
        for subj_str, row in subj_dict.items():
            row_pk = str(row.get(own_pk_col, _local_name(subj_str)))
            for col_name, col_def in t_def.columns.items():
                if col_def.is_generated:
                    row.pop(col_name, None)
                    continue
                if col_def.not_null and (col_name not in row or row[col_name] is None):
                    if col_name in fk_col_to_ref_table:
                        ref_t = fk_col_to_ref_table[col_name]
                        ref_rows = node_rows.get(ref_t, {})
                        if ref_rows:
                            first_ref_subj = next(iter(ref_rows))
                            row[col_name] = resolved_pk[first_ref_subj]
                            continue
                    row[col_name] = _default_for_not_null(col_def, row_pk)

    # 7. Topologically Sort Tables (Interleaved Parents & Foreign Key Targets First)
    sorted_tables = _topological_sort_tables(parsed_ddl)

    # 8. Emit GoogleSQL INSERT Statements (with self-referential parent-first row ordering)
    dml_statements: list[str] = []
    table_row_counts: dict[str, int] = {}

    for t_name in sorted_tables:
        t_def = parsed_ddl.tables[t_name]
        insertable_cols = [c.name for c in t_def.columns.values() if not c.is_generated]

        rows_to_emit: list[dict[str, Any]] = []
        if t_name in node_rows and node_rows[t_name]:
            rows_to_emit.extend(_order_self_referential_rows(list(node_rows[t_name].values()), t_def))
        if t_name in edge_rows and edge_rows[t_name]:
            rows_to_emit.extend(list(edge_rows[t_name].values()))

        if not rows_to_emit:
            continue

        table_row_counts[t_name] = len(rows_to_emit)
        for row in rows_to_emit:
            present_cols = [c for c in insertable_cols if c in row and row[c] is not None]
            vals_sql = [_format_sql_literal(row[c], t_def.columns[c]) for c in present_cols]
            stmt = f"INSERT INTO {t_name} ({', '.join(present_cols)}) VALUES ({', '.join(vals_sql)});"
            dml_statements.append(stmt)

    return dml_statements, table_row_counts


def _topological_sort_tables(parsed_ddl: ParsedSpannerDDL) -> list[str]:
    """Topologically orders tables so parent/referenced tables precede child/referencing tables."""
    deps: dict[str, set[str]] = {t: set() for t in parsed_ddl.tables}
    for t_name, t_def in parsed_ddl.tables.items():
        if t_def.interleaved_parent and t_def.interleaved_parent in deps and t_def.interleaved_parent != t_name:
            deps[t_name].add(t_def.interleaved_parent)
        for fk in t_def.foreign_keys:
            if fk.ref_table in deps and fk.ref_table != t_name:
                deps[t_name].add(fk.ref_table)

    ordered: list[str] = []
    visited: set[str] = set()
    temp_mark: set[str] = set()

    def visit(n: str):
        if n in visited:
            return
        if n in temp_mark:
            return
        temp_mark.add(n)
        for parent in sorted(deps.get(n, [])):
            visit(parent)
        temp_mark.remove(n)
        visited.add(n)
        ordered.append(n)

    for t_name in parsed_ddl.tables:
        visit(t_name)
    return ordered


def _order_self_referential_rows(rows: list[dict[str, Any]], t_def: TableDef) -> list[dict[str, Any]]:
    """Orders rows within a self-referential table so parent records are inserted before child records."""
    self_fk_cols = [
        fk.columns[0]
        for fk in t_def.foreign_keys
        if fk.ref_table == t_def.name and len(fk.columns) == 1
    ]
    if not self_fk_cols or not t_def.primary_keys:
        return rows

    pk_col = t_def.primary_keys[-1]
    by_pk = {r.get(pk_col): r for r in rows if r.get(pk_col) is not None}

    ordered: list[dict[str, Any]] = []
    visited: set[Any] = set()
    visiting: set[Any] = set()

    def visit_row(pk_val: Any):
        if pk_val in visited or pk_val not in by_pk:
            return
        visiting.add(pk_val)
        row = by_pk[pk_val]
        for fk_col in self_fk_cols:
            parent_pk = row.get(fk_col)
            if isinstance(parent_pk, list) or parent_pk is None:
                continue
            if parent_pk == pk_val:
                # Check if self-loop is disallowed by CHECK constraint
                for c1, c2 in t_def.no_self_loop_pairs:
                    if {c1, c2} == {pk_col, fk_col}:
                        row[fk_col] = None
                continue
            if parent_pk not in by_pk:
                row[fk_col] = None
                continue
            if parent_pk in visiting:
                # Back-edge in DFS cycle: pk_val will be emitted before parent_pk, so clear back-edge on pk_val
                row[fk_col] = None
            elif parent_pk not in visited:
                visit_row(parent_pk)
        visiting.remove(pk_val)
        visited.add(pk_val)
        ordered.append(row)

    for r in rows:
        pk_val = r.get(pk_col)
        if pk_val is not None:
            visit_row(pk_val)
        else:
            ordered.append(r)
    return ordered


# =============================================================================
# 5. END-TO-END ORCHESTRATION & LLM SELF-CORRECTION
# =============================================================================

def self_correct_dml_statement(
    ddl_content: str,
    failed_stmt: str,
    error_message: str,
    model_name: str = DEFAULT_GEMINI_MODEL,
) -> str:
    """Uses Gemini to repair a single failed SQL INSERT statement against the Spanner DDL."""
    client = _get_client()
    prompt = f"""The following GoogleSQL INSERT statement failed execution on Cloud Spanner:

Error:
{error_message}

Failed Statement:
```sql
{failed_stmt}
```

Target Cloud Spanner DDL:
```sql
{ddl_content}
```

Output ONLY the corrected single SQL INSERT statement inside a ```sql code block.
"""
    response = _generate_with_retry(
        client=client,
        model=model_name,
        contents=prompt,
        config=types.GenerateContentConfig(
            system_instruction=load_triple_loader_system_instruction(),
            temperature=0.0,
        ),
    )
    m = re.search(r"```sql\s*(.*?)\s*```", response.text, re.DOTALL | re.IGNORECASE)
    if m:
        return m.group(1).strip()
    return response.text.strip()


def run_triple_loader(
    triples_path: str,
    ddl_path: str,
    ontology_path: str | None = None,
    shacl_path: str | None = None,
    database: str | None = None,
    output_dml: str | None = None,
    mcp_url: str = DEFAULT_MCP_URL,
    use_emulator: bool = False,
    emulator_host: str | None = None,
    use_llm_mapping: bool = True,
    model_name: str = DEFAULT_GEMINI_MODEL,
) -> tuple[bool, list[str], dict[str, int], str]:
    """Translates an RDF triples file into Spanner DML and optionally loads it into Spanner/Emulator.

    Returns:
        (success, dml_statements, table_row_counts, summary_message)
    """
    with open(ddl_path, "r", encoding="utf-8") as f:
        ddl_content = f.read()

    ttl_content = ""
    if ontology_path and os.path.exists(ontology_path):
        with open(ontology_path, "r", encoding="utf-8") as f:
            ttl_content = f.read()
    else:
        with open(triples_path, "r", encoding="utf-8") as f:
            ttl_content = f.read()

    shacl_content = None
    if shacl_path and os.path.exists(shacl_path):
        with open(shacl_path, "r", encoding="utf-8") as f:
            shacl_content = f.read()

    parsed_ddl = parse_spanner_ddl(ddl_content)

    with console.status("[cyan]Synthesizing RDF-to-Spanner Schema Mapping Manifesto...[/cyan]"):
        mapping_spec = generate_schema_mapping_spec(
            ttl_content=ttl_content,
            ddl_content=ddl_content,
            shacl_content=shacl_content,
            use_llm=use_llm_mapping,
            model_name=model_name,
        )

    with console.status(f"[cyan]Parsing RDF triples from {os.path.basename(triples_path)} & generating GoogleSQL DML...[/cyan]"):
        dml_statements, table_row_counts = translate_triples_to_dml(
            triples_path=triples_path,
            ddl_content=ddl_content,
            mapping_spec=mapping_spec,
            parsed_ddl=parsed_ddl,
        )

    if output_dml:
        out_dir = os.path.dirname(os.path.abspath(output_dml))
        if out_dir:
            os.makedirs(out_dir, exist_ok=True)
        with open(output_dml, "w", encoding="utf-8") as f:
            f.write("-- Generated by rdf-spanner-translator triple_loader\n")
            f.write(f"-- Source Triples: {triples_path}\n\n")
            f.write("\n".join(dml_statements) + "\n")
        console.print(f"[green]✓ Wrote {len(dml_statements)} SQL INSERT statements to {output_dml}[/green]")

    # If no database or emulator target was requested, translation-only succeeds
    is_emu = use_emulator or bool(os.getenv("SPANNER_EMULATOR_HOST"))
    if not database and not is_emu:
        msg = f"Generated {len(dml_statements)} DML statements across {len(table_row_counts)} tables (offline mode)."
        return True, dml_statements, table_row_counts, msg

    target_db = database or "test_db"
    target_label = "Spanner Emulator" if is_emu else "Cloud Spanner"
    console.print(
        f"[cyan]• Loading {len(dml_statements)} RDF triple INSERT statements into "
        f"{target_label} ({target_db})...[/cyan]"
    )

    with console.status(f"[cyan]Executing batch DML on {target_label} (0/{len(dml_statements)})...[/cyan]") as status:
        def _on_progress(processed: int, total: int, ok_count: int) -> None:
            status.update(
                f"[cyan]Executing batch DML on {target_label}: {processed}/{total} statements processed ({ok_count} committed)...[/cyan]"
            )

        succeeded, failures = execute_spanner_dml_batch(
            statements=dml_statements,
            database=target_db,
            mcp_url=mcp_url,
            use_emulator=is_emu,
            emulator_host=emulator_host,
            progress_callback=_on_progress,
        )

    # Attempt LLM self-correction on any failed statements (up to 10 statements)
    if failures and use_llm_mapping:
        console.print(f"[yellow]• Attempting self-correction on {min(len(failures), 10)} failed DML statement(s)...[/yellow]")
        remaining_failures: list[tuple[int, str, str]] = []
        for idx, failed_stmt, err_msg in failures[:10]:
            try:
                fixed_stmt = self_correct_dml_statement(
                    ddl_content=ddl_content,
                    failed_stmt=failed_stmt,
                    error_message=err_msg,
                    model_name=model_name,
                )
                ok, retry_msg = execute_spanner_statement(
                    statement=fixed_stmt,
                    database=target_db,
                    mcp_url=mcp_url,
                    use_emulator=is_emu,
                    emulator_host=emulator_host,
                )
                if ok:
                    dml_statements[idx] = fixed_stmt
                    succeeded += 1
                else:
                    remaining_failures.append((idx, failed_stmt, retry_msg))
            except Exception:
                remaining_failures.append((idx, failed_stmt, err_msg))
        remaining_failures.extend(failures[10:])
        failures = remaining_failures

    all_ok = len(failures) == 0
    if all_ok:
        msg = f"Successfully loaded all {succeeded}/{len(dml_statements)} RDF triple rows across {len(table_row_counts)} tables."
        console.print(f"[green]✓ {msg}[/green]")
    else:
        sample_err = failures[0][2] if failures else "Unknown error"
        msg = (
            f"Loaded {succeeded}/{len(dml_statements)} rows ({len(failures)} failed). "
            f"First error: {sample_err}"
        )
        console.print(f"[yellow]⚠ {msg}[/yellow]")

    return all_ok, dml_statements, table_row_counts, msg
