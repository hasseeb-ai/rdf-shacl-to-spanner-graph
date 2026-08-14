# Unit Test Ontologies for Cloud Spanner Graph DDL Translator

This directory contains modular test ontologies and companion SHACL shape definitions. Each test case isolates and verifies specific translation rules and semantic constraints specified in [`owl-to-spanner-property-graph-translator`](../../skills/owl-to-spanner-property-graph-translator/SKILL.md), audited by [`spanner-graph-semantic-validator`](../../skills/spanner-graph-semantic-validator/SKILL.md), and verified dynamically by [`spanner-graph-query-verifier`](../../skills/spanner-graph-query-verifier/SKILL.md).

## Validation Strategy

Validation operates across three comprehensive stages:
- **Dialect & Syntactic Compliance:** Ensures the physical GoogleSQL DDL (`CREATE TABLE`) and Property Graph DDL (`CREATE PROPERTY GRAPH`) compile and execute cleanly on a Google Cloud Spanner instance via the official Spanner MCP server.
- **Semantic Validation & Scorecard:** Audits the schema across 7 semantic dimensions (completeness, renaming traceability, inheritance flattening, property isolation, XSD types, edge connectivity, and Spanner engine invariants), producing an executive one-pager report (`output/unit_tests/<test>_validation_report.md`).
- **Dynamic Data Ingestion & GQL Query Verification:** Generates coherent, connected mock fixtures (SQL `INSERT`s) and executes 4 representative GQL queries live against Cloud Spanner to verify multi-label polymorphism, multi-hop traversal, inverse aliasing, and property filtering, generating `output/unit_tests/<test>_query_report.md`.

## Test Ontology Matrix

| File | Primary Semantic Concept | SKILL.md Section / Rule Covered | Key Verification Aspects |
| :--- | :--- | :--- | :--- |
| **`01_simple_inheritance.ttl`** | Single Class Hierarchy | Top-Down Datatype Property Propagation & Table-Per-Concrete-Class (Rule 8) | • Superclass properties (`vin`, `manufacturer`) flatten into leaf tables (`Cars`, `Trucks`).<br>• Subclass properties (`seatingCapacity`) stay strictly isolated (Bottom-up isolation).<br>• Node tables declare full multi-label hierarchy (`LABEL Car LABEL MotorVehicle LABEL Vehicle`). |
| **`02_multiple_inheritance.ttl`** | Multiple Inheritance (Diamond) | Multiple Inheritance Disambiguation (Rule 5) | • Diamond inheritance: `TeachingAssistant` subclasses both `Employee` and `Student`.<br>• Multi-label accumulation: `LABEL TeachingAssistant LABEL Employee LABEL Student LABEL Person`.<br>• Column disambiguation when parent classes declare overlapping attribute names. |
| **`03_cardinality_and_datatypes.ttl`<br>`03_cardinality_and_datatypes_shacl.ttl`** | Cardinality & Datatypes | Spanner Datatypes & Cardinality Rules (SHACL Rules 3, 4, 5) | • `owl:FunctionalProperty`, `owl:cardinality`, `owl:maxCardinality`.<br>• Spanner Datatypes: `STRING`, `INT64`, `NUMERIC`, `FLOAT64`, `BOOL`, `TIMESTAMP`, `DATE`.<br>• SHACL `sh:minCount 1` -> `NOT NULL`, `sh:maxCount 1` -> Scalar, `sh:maxCount > 1` -> `ARRAY<T>`. |
| **`04_object_property_hierarchy.ttl`** | Object Property Hierarchy | Object Property Domain/Range Top-Down & Bottom-Up Rules | • Top-down domain: Domain subclasses inherit the outgoing relationship.<br>• Top-down range: Valid foreign keys/edges target range subclass tables.<br>• Bottom-up isolation: Sub-domain/range relationships do not leak upwards.<br>• Localized range restrictions (`owl:allValuesFrom`). |
| **`05_inverse_properties.ttl`** | Inverse Properties | Inverse Property Deduplication (Rule 4) & Edge Aliasing (Rule 5) | • `owl:inverseOf` relationship pairs (`contractsWith` / `contractedBy`).<br>• Physical storage in a single relational table/FK.<br>• Property graph dual edge mappings with inverted `SOURCE KEY` / `DESTINATION KEY` using the `AS` keyword. |
| **`06_subproperties.ttl`** | Subproperty Hierarchy | Subproperty Label Accumulation (Rule 2) & Broad/Narrow Exclusion | • `rdfs:subPropertyOf` property taxonomy.<br>• Child edge accumulates parent labels: `LABEL WRITES_CODE_FOR LABEL CONTRIBUTES_TO_INITIATIVE LABEL ASSOCIATED_WITH_INITIATIVE`.<br>• Broad-to-narrow exclusion: Generic parent edges do not inherit child labels. |
| **`07_transitive_and_symmetric.ttl`** | Transitive & Symmetric Properties | Transitive Interleaved Tables & Primary Key Alignment (Rule 3) | • `owl:TransitiveProperty`: Hierarchical self-referencing mapped to interleaved tables (`INTERLEAVE IN PARENT ... ON DELETE CASCADE`).<br>• Primary key alignment: Child PK begins with parent PK.<br>• `owl:SymmetricProperty`: Unidirectional physical storage, bidirectional GQL traversal. |
| **`08_disjoint_and_equivalent_classes.ttl`** | Disjointness & Equivalent Classes | Disjoint Class Separation & Stored Generated Columns (Rule 7) | • `owl:disjointWith`: Distinct SQL tables with independent primary key spaces.<br>• `owl:equivalentClass`: Threshold/filter expression translated to GoogleSQL stored generated column (`<Col> <Type> AS (<Expr>) STORED`). |
| **`09_union_domains.ttl`** | Union Domains | Union Domain Propagation (Golden Execution Rule 1) | • `rdfs:domain` with `owl:unionOf (Individual Organization)`.<br>• Top-down propagation ensures every concrete leaf table of each union member receives the property column. |
| **`10_shacl_advanced_constraints.ttl`<br>`10_shacl_advanced_constraints_shacl.ttl`** | SHACL Constraints & Polymorphism | SHACL Enums, Defaults, Nested Shapes & Polymorphic FKs (SHACL Rules 6, 7, 8) | • `sh:in` -> `CONSTRAINT CK_... CHECK (Column IN (...))`.<br>• `sh:hasValue` -> `DEFAULT` / `CHECK`.<br>• `sh:node` -> Flattened embedded attributes.<br>• Polymorphic `sh:class` referencing abstract class -> Omit SQL FK, map multi-target `EDGE TABLES`. |
| **`11_comprehensive_schema.ttl`<br>`11_comprehensive_schema_shacl.ttl`** | Comprehensive Multi-Feature Schema | End-to-End Schema Translation & Full Feature Set | • Multi-tier inheritance, stored columns, inverse properties, subproperties, transitive hierarchies, symmetric edges, and SHACL shapes. |

## Running Unit Tests & Dynamic Query Verification

```bash
# Run all unit tests with live Spanner MCP verification and semantic reports:
python run_tests.py --unit-only

# Run all unit tests including dynamic data ingestion & GQL query verification:
python run_tests.py --unit-only --verify-queries

# Run a specific unit test ontology:
python run_tests.py 01_simple_inheritance --verify-queries

# Standalone dynamic query testing on an existing database:
rdf-spanner-translator validate \
  --input tests/ontologies/01_simple_inheritance.ttl \
  --ddl output/unit_tests/01_simple_inheritance_schema.sql \
  --database $SPANNER_DATABASE \
  --queries-only \
  --output output/unit_tests/01_simple_inheritance_query_report.md
```


