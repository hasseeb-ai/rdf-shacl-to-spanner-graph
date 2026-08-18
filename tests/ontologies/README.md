# Unit Test Ontologies for Cloud Spanner Graph DDL Translator

This directory contains modular test ontologies and companion SHACL shape definitions. Each test case isolates and verifies specific translation rules and semantic constraints specified in [`owl-to-spanner-property-graph-translator`](../../skills/owl-to-spanner-property-graph-translator/SKILL.md), audited by [`spanner-graph-semantic-validator`](../../skills/spanner-graph-semantic-validator/SKILL.md), and verified dynamically by [`spanner-graph-query-verifier`](../../skills/spanner-graph-query-verifier/SKILL.md).

## Validation Strategy

Validation operates across three comprehensive stages:
- **Dialect & Syntactic Compliance:** Ensures the physical GoogleSQL DDL (`CREATE TABLE`) and Property Graph DDL (`CREATE PROPERTY GRAPH`) compile and execute cleanly on a Google Cloud Spanner instance via the official Spanner MCP server.
- **Semantic Validation & Scorecard:** Audits the schema across 7 semantic dimensions (completeness, renaming traceability, inheritance flattening, property isolation, XSD types, edge connectivity, and Spanner engine invariants), producing an executive one-pager report (`output/unit_tests/<test>_validation_report.md`).
- **Dynamic Data Ingestion & GQL Query Verification:** Generates coherent, connected mock fixtures (SQL `INSERT`s) and executes 4 representative GQL queries live against Cloud Spanner to verify multi-label polymorphism, multi-hop traversal, inverse aliasing, and property filtering, generating `output/unit_tests/<test>_query_report.md`.

## Test Ontology Matrix

| Test Suite & Artifacts | Primary Semantic Concept | Key Verification Aspects |
| :--- | :--- | :--- |
| **`01_simple_inheritance`**<br>• [OWL (`.ttl`)](01_simple_inheritance.ttl)<br>• [Schema (`.sql`)](01_simple_inheritance_schema.sql)<br>• [HTML Report (`.html`)](01_simple_inheritance_validation_report.html) | Single Class Hierarchy & Table-Per-Concrete | • Superclass properties (`vin`, `manufacturer`) flatten into leaf tables (`Cars`, `Trucks`).<br>• Subclass properties (`seatingCapacity`) stay strictly isolated (Bottom-up isolation).<br>• Node tables declare full multi-label hierarchy (`LABEL Car LABEL MotorVehicle LABEL Vehicle`). |
| **`02_multiple_inheritance`**<br>• [OWL (`.ttl`)](02_multiple_inheritance.ttl)<br>• [Schema (`.sql`)](02_multiple_inheritance_schema.sql)<br>• [HTML Report (`.html`)](02_multiple_inheritance_validation_report.html) | Multiple Inheritance (Diamond) | • Diamond inheritance: `TeachingAssistant` subclasses both `Employee` and `Student`.<br>• Multi-label accumulation: `LABEL TeachingAssistant LABEL Employee LABEL Student LABEL Person`.<br>• Column disambiguation when parent classes declare overlapping attribute names. |
| **`03_cardinality_and_datatypes`**<br>• [OWL (`.ttl`)](03_cardinality_and_datatypes.ttl)<br>• [SHACL (`.ttl`)](03_cardinality_and_datatypes_shacl.ttl)<br>• [Schema (`.sql`)](03_cardinality_and_datatypes_schema.sql)<br>• [HTML Report (`.html`)](03_cardinality_and_datatypes_validation_report.html) | Cardinality & Datatypes | • `owl:FunctionalProperty`, `owl:cardinality`, `owl:maxCardinality`.<br>• Spanner Datatypes: `STRING`, `INT64`, `NUMERIC`, `FLOAT64`, `BOOL`, `TIMESTAMP`, `DATE`.<br>• SHACL `sh:minCount 1` -> `NOT NULL`, `sh:maxCount 1` -> Scalar, `sh:maxCount > 1` -> `ARRAY<T>`. |
| **`04_object_property_hierarchy`**<br>• [OWL (`.ttl`)](04_object_property_hierarchy.ttl)<br>• [Schema (`.sql`)](04_object_property_hierarchy_schema.sql)<br>• [HTML Report (`.html`)](04_object_property_hierarchy_validation_report.html) | Object Property Hierarchy | • Top-down domain: Domain subclasses inherit outgoing relationships.<br>• Top-down range: Foreign keys/edges target range subclass tables.<br>• Bottom-up isolation: Sub-domain/range relationships do not leak upwards. |
| **`05_inverse_properties`**<br>• [OWL (`.ttl`)](05_inverse_properties.ttl)<br>• [Schema (`.sql`)](05_inverse_properties_schema.sql)<br>• [HTML Report (`.html`)](05_inverse_properties_validation_report.html) | Inverse Properties | • `owl:inverseOf` relationship pairs (`contractsWith` / `contractedBy`).<br>• Physical storage deduplicated into a single relational table/FK.<br>• Property graph dual edge mappings with inverted `SOURCE KEY` / `DESTINATION KEY` using the `AS` keyword. |
| **`06_subproperties`**<br>• [OWL (`.ttl`)](06_subproperties.ttl)<br>• [Schema (`.sql`)](06_subproperties_schema.sql)<br>• [HTML Report (`.html`)](06_subproperties_validation_report.html) | Subproperty Hierarchy | • `rdfs:subPropertyOf` property taxonomy.<br>• Child edge accumulates parent labels: `LABEL WRITES_CODE_FOR LABEL CONTRIBUTES_TO_INITIATIVE LABEL ASSOCIATED_WITH_INITIATIVE`.<br>• Broad-to-narrow exclusion: Generic parent edges do not inherit child labels. |
| **`07_transitive_and_symmetric`**<br>• [OWL (`.ttl`)](07_transitive_and_symmetric.ttl)<br>• [Schema (`.sql`)](07_transitive_and_symmetric_schema.sql)<br>• [HTML Report (`.html`)](07_transitive_and_symmetric_validation_report.html) | Transitive & Symmetric Properties | • `owl:TransitiveProperty`: Hierarchical self-referencing mapped to interleaved tables (`INTERLEAVE IN PARENT ... ON DELETE CASCADE`).<br>• Primary key alignment: Child PK begins with parent PK.<br>• `owl:SymmetricProperty`: Unidirectional physical storage, bidirectional GQL traversal. |
| **`08_disjoint_and_equivalent_classes`**<br>• [OWL (`.ttl`)](08_disjoint_and_equivalent_classes.ttl)<br>• [Schema (`.sql`)](08_disjoint_and_equivalent_classes_schema.sql)<br>• [HTML Report (`.html`)](08_disjoint_and_equivalent_classes_validation_report.html) | Disjointness & Equivalent Classes | • `owl:disjointWith`: Distinct SQL tables with independent primary key spaces.<br>• `owl:equivalentClass`: Filter expression translated to GoogleSQL stored generated column (`<Col> <Type> AS (<Expr>) STORED`). |
| **`09_union_domains`**<br>• [OWL (`.ttl`)](09_union_domains.ttl)<br>• [Schema (`.sql`)](09_union_domains_schema.sql)<br>• [HTML Report (`.html`)](09_union_domains_validation_report.html) | Union Domains & Multi-Target Propagation | • `rdfs:domain` with `owl:unionOf (Individual Organization)`.<br>• Top-down propagation ensures every concrete leaf table of each union member receives the property column. |
| **`10_shacl_advanced_constraints`**<br>• [OWL (`.ttl`)](10_shacl_advanced_constraints.ttl)<br>• [SHACL (`.ttl`)](10_shacl_advanced_constraints_shacl.ttl)<br>• [Schema (`.sql`)](10_shacl_advanced_constraints_schema.sql)<br>• [HTML Report (`.html`)](10_shacl_advanced_constraints_validation_report.html) | SHACL Constraints & Polymorphism | • `sh:in` -> `CONSTRAINT CK_... CHECK (Column IN (...))`.<br>• `sh:hasValue` -> `DEFAULT` / `CHECK`.<br>• `sh:node` -> Flattened embedded attributes.<br>• Polymorphic `sh:class` referencing abstract class -> Omit SQL FK, map multi-target `EDGE TABLES`. |
| **`11_comprehensive_schema`**<br>• [OWL (`.ttl`)](11_comprehensive_schema.ttl)<br>• [SHACL (`.ttl`)](11_comprehensive_schema_shacl.ttl)<br>• [Schema (`.sql`)](11_comprehensive_schema_schema.sql)<br>• [HTML Report (`.html`)](11_comprehensive_schema_validation_report.html) | Comprehensive Multi-Feature Schema | • Diamond inheritance, generated stored columns, inverse properties, subproperties, transitive hierarchies, symmetric edges, and SHACL shapes. |
| **`12_n_ary_relations`**<br>• [OWL (`.ttl`)](12_n_ary_relations.ttl)<br>• [SHACL (`.ttl`)](12_n_ary_relations_shacl.ttl) | Attributed Edges & Association Entities | • W3C N-ary relationship pattern (`Employment` connecting `Person` and `Company`).<br>• Mapped as Spanner Edge Table with Properties (`PROPERTIES (JobTitle, SalaryAmount, StartDate)`). |
| **`13_recursive_graphs`**<br>• [OWL (`.ttl`)](13_recursive_graphs.ttl) | Recursive Adjacency & Org Charts | • Self-referencing entity relationships (`reportsTo` manager, `dependsOn` component).<br>• Mapped as self-loop edge tables supporting variable-length GQL path queries (`->{1,5}`). |
| **`14_property_chains`**<br>• [OWL (`.ttl`)](14_property_chains.ttl) | Complex Property Chains | • `owl:propertyChainAxiom` shortcuts (`worksAt` o `facilityOf` -> `employedByOrg`).<br>• Omits redundant physical FK columns while supporting multi-hop GQL navigation. |
| **`15_qualified_cardinalities`**<br>• [OWL (`.ttl`)](15_qualified_cardinalities.ttl)<br>• [SHACL (`.ttl`)](15_qualified_cardinalities_shacl.ttl) | Qualified Cardinality Restrictions (QCRs) | • Subclass-specific cardinality (`Bicycle` exactly 2 `Wheel`s, `Car` exactly 4 `Wheel`s).<br>• Localized column constraints and qualified SHACL shape validation. |
| **`16_subproperty_dag`**<br>• [OWL (`.ttl`)](16_subproperty_dag.ttl) | Multi-Parent Subproperty DAG | • Subproperties with multiple orthogonal parent properties.<br>• Edge table multi-label accumulation across dual taxonomic branches (`LABEL DIRECT_NONSTOP_FLIGHT LABEL OPERATES_COMMERCIAL_ROUTE LABEL SCHEDULES_DIRECT_ROUTE`). |
| **`17_temporal_validity`**<br>• [OWL (`.ttl`)](17_temporal_validity.ttl)<br>• [SHACL (`.ttl`)](17_temporal_validity_shacl.ttl) | Temporal Validity Windows & Intervals | • W3C Time interval modeling (`validFrom`, `validTo`, `isActive`).<br>• GoogleSQL `TIMESTAMP` check constraints (`ValidTo IS NULL OR ValidTo >= ValidFrom`) and point-in-time traversal. |
| **`18_heterogeneous_subproperties`**<br>• [OWL (`.ttl`)](18_heterogeneous_subproperties.ttl)<br>• [SHACL (`.ttl`)](18_heterogeneous_subproperties_shacl.ttl)<br>• [Schema (`.sql`)](18_heterogeneous_subproperties_schema.sql)<br>• [HTML Report (`.html`)](18_heterogeneous_subproperties_validation_report.html) | Heterogeneous Subproperties & Containment | • Abstract universal `contains` relationship with specialized multi-domain subproperties (`buildingContainsApartment` and `stateContainsCity`).<br>• Label-scoped property lists (`PROPERTIES (...)` vs `NO PROPERTIES`) with backtick escaping for reserved keywords (`` `CONTAINS` ``). |
| **`19_attributed_abstract_entities`**<br>• [OWL (`.ttl`)](19_attributed_abstract_entities.ttl)<br>• [SHACL (`.ttl`)](19_attributed_abstract_entities_shacl.ttl) | Attributed Abstract Superclass & Subproperties | • Abstract superclass `SpatialEntity` with common properties (`spatialEntityId`, `displayName`) inherited by all 4 leaf tables.<br>• Uniform Signature Rule enforcement across node tables sharing `LABEL SpatialEntity PROPERTIES (SpatialEntityId, DisplayName)` alongside heterogeneous subproperty edges. |

## Running Unit Tests & Dynamic Query Verification

```bash
export SPANNER_INSTANCE="projects/<PROJECT>/instances/<INSTANCE>"
export SPANNER_DATABASE="projects/<PROJECT>/instances/<INSTANCE>/databases/<DATABASE>"

# Run all unit tests with live Spanner MCP verification, semantic reports, and cleanup:
rdf-spanner-translator pipeline \
  --input tests/ontologies/ \
  --instance $SPANNER_INSTANCE

# Run all unit tests including dynamic data ingestion & GQL query verification:
rdf-spanner-translator pipeline \
  --input tests/ontologies/ \
  --instance $SPANNER_INSTANCE \
  --verify-queries

# Run a specific unit test ontology:
rdf-spanner-translator pipeline \
  --input tests/ontologies/01_simple_inheritance.ttl \
  --shacl tests/ontologies/01_simple_inheritance_shacl.ttl \
  --database $SPANNER_DATABASE \
  --verify-queries

# Standalone dynamic query testing on an existing database:
rdf-spanner-translator validate \
  --input tests/ontologies/01_simple_inheritance.ttl \
  --ddl output/unit_tests/01_simple_inheritance_schema.sql \
  --database $SPANNER_DATABASE \
  --queries-only \
  --output output/unit_tests/01_simple_inheritance_query_report.md
```


