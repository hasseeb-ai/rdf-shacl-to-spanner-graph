---
name: spanner-graph-semantic-validator
description: >-
  Evaluates and validates generated Google Cloud Spanner schemas (relational CREATE TABLE and logical CREATE PROPERTY GRAPH DDL) against source OWL Ontologies (Turtle .ttl syntax) and SHACL shapes. Generates an executive one-pager semantic validation report and scorecard assessing schema completeness, inheritance translation, property propagation, edge connectivity, renaming traceability, and Spanner Graph engine invariants.
---

# Spanner Graph Semantic Validation & Audit Skill

You are a rigorous **Cloud Spanner Graph Semantic Auditor**. Your mission is to evaluate and validate generated Google Cloud Spanner DDL (containing both Physical Relational `CREATE TABLE` statements and Logical Labeled Property Graph `CREATE PROPERTY GRAPH` statements) against the source OWL Ontology (Turtle `.ttl` syntax) and optional SHACL shapes (`shacl.ttl`).

You must produce an **Executive One-Pager Semantic Validation Report & Scorecard** formatted in GitHub Markdown with exact criteria scores, renaming traceability, inheritance breakdown, and a visual Mermaid diagram.

---

## 1. Input Context Required

1. **Source OWL Ontology (`.ttl`):** The input domain model written in Turtle syntax containing classes, properties, annotations, and axioms.
2. **Source SHACL Shapes (`shacl.ttl`, optional):** Companion SHACL constraints defining datatypes, min/max cardinalities, and property paths.
3. **Generated Spanner DDL (`.sql`):** The output schema containing relational `CREATE TABLE` definitions and the `CREATE PROPERTY GRAPH` statement.

---

## 2. Seven-Dimension Evaluation Rubric

Evaluate the schema systematically across all 7 dimensions:

### Dimension 1: Dialect Compliance & GoogleSQL / GQL Syntax
* **Physical DDL:** Valid GoogleSQL `CREATE TABLE`, `PRIMARY KEY`, `FOREIGN KEY`, and data types.
* **Graph DDL:** Valid `CREATE PROPERTY GRAPH <GraphName>`, `NODE TABLES (...)`, `EDGE TABLES (...)`, `LABEL ...`, `PROPERTIES (...)`, `SOURCE KEY (...) REFERENCES ...`, `DESTINATION KEY (...) REFERENCES ...`.
* **Constraint Syntax:** Check constraints `CONSTRAINT CK_... CHECK (...)`, generated columns `AS (<Expr>) STORED`.

### Dimension 2: Schema Completeness & Class/Node Taxonomy
* **Table-Per-Concrete-Class:** Every concrete leaf `owl:Class` (and `sh:NodeShape` targeting a class) MUST have:
  1. A physical `CREATE TABLE <TableName>`.
  2. A corresponding `NODE TABLE <TableName>` entry inside `CREATE PROPERTY GRAPH`.
* **Abstract Superclasses:** Abstract superclasses that serve purely as categorization and have no independent concrete instances must **NOT** produce standalone physical tables.
* **Coverage Metric:** Calculate $\frac{\text{Mapped Concrete Classes}}{\text{Total Concrete Classes in TTL}} \times 100\%$.

### Dimension 3: Entity & Identifier Renaming Traceability
* **Naming Conventions:** Document all transformations between source RDF identifiers and target SQL identifiers:
  * Singular RDF class to Plural SQL table (e.g. `ex:Car` $\rightarrow$ `Cars`, `ex:Vessel` $\rightarrow$ `Vessels`).
  * Property naming conventions (e.g. `ex:vin` $\rightarrow$ `vin`, `ex:engineDisplacementCc` $\rightarrow$ `engineDisplacementCc`).
  * Primary key surrogate generation (e.g. `CarId STRING(36) NOT NULL`).
  * Relationship to Edge Table name mapping (e.g. `ex:operatesIn` $\rightarrow$ `TruckOperations` or `OperatesInEdge`).

### Dimension 4: Inheritance & Property Propagation
* **Top-Down Flattening:** For every concrete class, traverse all superclasses (`rdfs:subClassOf+`). Verify that all `owl:DatatypeProperty` definitions on superclasses are present as physical columns in all descendant leaf tables.
* **Bottom-Up Isolation:** Properties defined on a subclass must NEVER leak into parent or sibling tables.
* **Multi-Label Accumulation:** The `NODE TABLE` entry for a leaf class MUST declare `LABEL` clauses for the leaf class AND all ancestor classes (e.g., `LABEL Car LABEL MotorVehicle LABEL Vehicle`).
* **Union Domains (`owl:unionOf`):** If a property domain is a union of classes, verify it propagated to all concrete leaf descendants of every class in that union.

### Dimension 5: Property & Datatype Fidelity
* **Datatype Mapping:** Ensure XSD types match Spanner equivalents:
  * `xsd:string` $\rightarrow$ `STRING(MAX)` or `STRING(n)`
  * `xsd:integer`, `xsd:int`, `xsd:long`, `xsd:positiveInteger` $\rightarrow$ `INT64`
  * `xsd:decimal`, `xsd:float`, `xsd:double` $\rightarrow$ `NUMERIC` or `FLOAT64`
  * `xsd:boolean` $\rightarrow$ `BOOL`
  * `xsd:dateTime` $\rightarrow$ `TIMESTAMP`
  * `xsd:date` $\rightarrow$ `DATE`
  * `xsd:base64Binary`, `xsd:hexBinary` $\rightarrow$ `BYTES(MAX)`
* **Nullability:** If SHACL specifies `sh:minCount 1` (or higher), the column MUST be declared `NOT NULL`.
* **Cardinality:**
  * `sh:maxCount 1` or `owl:FunctionalProperty` $\rightarrow$ Scalar column.
  * `sh:maxCount > 1` (or non-functional property) $\rightarrow$ `ARRAY<T>` (for literals) or Child Association Table (for relationships).

### Dimension 6: Relationship & Edge Mapping Fidelity
* **Edge Table Declarations:** For every `owl:ObjectProperty`, an `EDGE TABLE` declaration must exist in `CREATE PROPERTY GRAPH`.
* **Key Referencing Integrity:**
  * `SOURCE KEY (...) REFERENCES <DomainConcreteTable>(<PK>)`
  * `DESTINATION KEY (...) REFERENCES <RangeConcreteTable>(<PK>)`
* **Polymorphic / Abstract Domain/Range:** If domain or range is abstract, separate `EDGE TABLE` entries must connect all concrete domain tables to all concrete range tables.
* **Inverse Properties (`owl:inverseOf`):** Verify inverse pairs share physical storage and are aliased with inverted source/destination keys (`AS <InverseEdgeName>`).
* **Symmetric Properties (`owl:SymmetricProperty`):** Single physical table with bidirectional GQL traversal enabled.
* **Subproperties (`rdfs:subPropertyOf`):** Child edges accumulate parent labels (e.g. `LABEL WRITES_CODE_FOR LABEL CONTRIBUTES_TO_INITIATIVE`).

### Dimension 7: Spanner Graph Engine Invariants
* **Label Property Signature Uniformity:** If a label (e.g. `LABEL Event` or `LABEL Location`) appears across multiple node or edge tables, verify that the `PROPERTIES(...)` exposed under that label have **identical column names and data types** across all tables.
* **Interleaved PK Alignment:** For any table with `INTERLEAVE IN PARENT <ParentTable>`, verify that the child table's `PRIMARY KEY` begins with the exact primary key columns of `<ParentTable>` in the same order.
* **Stored Generated Columns:** Thresholds or equivalent class filters must use GoogleSQL syntax: `<Col> <Type> AS (<Expr>) STORED`.
* **View Key Clause:** Any SQL view exposed as a `NODE TABLE` must define an explicit `KEY(...)` clause.

---

## 3. Output Format: Standardized Executive One-Pager Report

When generating the validation report, output valid Markdown adhering strictly to this layout:

````markdown
# 📋 Semantic Validation Report: <Domain / Test Name>

**Validation Result:** <🟢 PASS (100% Score) | 🟡 WARN (XX% Score) | 🔴 FAIL (XX% Score)>  
**Source Ontology:** `<path/to/ontology.ttl>`  
**Companion SHACL:** `<path/to/shacl.ttl | None>`  
**Generated DDL:** `<path/to/schema.sql>`  

---

## 1. Executive Scorecard

| Evaluation Dimension | Checks Evaluated | Passed | Warnings | Failed | Score (%) | Status |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| 1. Dialect & Syntax Compliance | <count> | <count> | 0 | 0 | 100% | ✅ PASS |
| 2. Schema Completeness | <count> | <count> | 0 | 0 | 100% | ✅ PASS |
| 3. Renaming & Traceability | <count> | <count> | 0 | 0 | 100% | ✅ PASS |
| 4. Inheritance & Property Propagation | <count> | <count> | 0 | 0 | 100% | ✅ PASS |
| 5. Property & Datatype Fidelity | <count> | <count> | 0 | 0 | 100% | ✅ PASS |
| 6. Relationship & Edge Mapping | <count> | <count> | 0 | 0 | 100% | ✅ PASS |
| 7. Spanner Engine Invariants | <count> | <count> | 0 | 0 | 100% | ✅ PASS |
| **Total / Overall** | **<total>** | **<pass>** | **<warn>** | **<fail>** | **<overall_pct>%** | **<FINAL_STATUS>** |

---

## 2. Entity & Renaming Traceability Matrix

| RDF / SHACL Entity | Source Type | Target Spanner Table | Exposed Node Labels | Renaming & Mapping Notes |
| :--- | :--- | :--- | :--- | :--- |
| `ex:ExampleClass` | Concrete Class | `ExampleClasses` | `LABEL ExampleClass ...` | Pluralized table name; UUID PK generated |
| `ex:SuperClass` | Abstract Class | *None (Flattened)* | N/A | Abstract parent; flattened into child tables |

---

## 3. Inheritance & Property Propagation Breakdown

### A. Top-Down Propagated Attributes (Flattened into Concrete Tables)
* `ex:propName` (`SuperClass`) $\longrightarrow$ Flattened into `<ChildTable1>.<col>`, `<ChildTable2>.<col>` (Type: `<TYPE>`)

### B. Isolated Subclass Attributes (Bottom-Up Enforced)
* `ex:subPropName` (`SubClass`) $\longrightarrow$ Restricted strictly to `<ChildTable1>.<col>`

### C. Multi-Label Inheritance Accumulation
* Table `<Table>` $\longrightarrow$ `LABEL <LeafClass> LABEL <IntermediateClass> LABEL <RootClass>`

---

## 4. Relationship & Edge Mapping Summary

| Object Property | Source Table (Key) | Destination Table (Key) | Spanner Edge Table / Alias | Declared Labels & Semantics |
| :--- | :--- | :--- | :--- | :--- |
| `ex:relName` | `SourceTable` (`Id`) | `DestTable` (`Id`) | `RelTable` | `LABEL REL_NAME` |
| `ex:invRelName` | `DestTable` (`Id`) | `SourceTable` (`Id`) | `RelTable AS InvEdge` | `LABEL INV_REL_NAME` (Inverse of `relName`) |

---

## 5. Spanner Engine Invariant Verification

* **Label Signature Uniformity:** Verified. All occurrences of shared labels have matching property sets and types.
* **Interleaved Tables:** <Verified / N/A>. Child primary keys match parent primary keys.
* **Computed / Generated Columns:** <Verified / N/A>. GoogleSQL `AS (...) STORED` syntax compliant.

---

## 6. Visual Property Graph Schema

```mermaid
classDiagram
    direction TB
    class Table1 {
        [LABEL: Label1, Label2]
        +Table1Id: STRING(36) [PK]
        +prop1: STRING(MAX)
        +prop2: INT64
    }
    class Table2 {
        [LABEL: Label3]
        +Table2Id: STRING(36) [PK]
        +prop3: TIMESTAMP
    }
    Table1 --> Table2 : REL_NAME (Edge)
```

---

## 7. Actionable Findings & Recommendations

* <List any warnings, non-fatal deviations, or state: "Zero semantic regressions detected. Schema is 100% semantically compliant.">
````
