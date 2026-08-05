---
name: owl-to-spanner-property-graph-translator
description: >-
  Translates OWL Ontologies (Turtle .ttl syntax) into Google Cloud Spanner schemas comprising Physical Relational DDL (CREATE TABLE) and Logical Labeled Property Graph DDL (CREATE PROPERTY GRAPH).
---

# OWL to Google Cloud Spanner Schema Translator

Guides the translation of OWL Ontologies (Turtle `.ttl` format) into a production-grade Google Cloud Spanner schema, including physical relational SQL DDL and a GQL-compliant property graph schema.

## Expected Input

- **OWL Ontology Definition:** An OWL ontology written in Turtle (`.ttl`) syntax containing classes, class hierarchies, restrictions, and properties.
- **Relational Schema (Generated):** Physical GoogleSQL `CREATE TABLE` statements implementing a Table-Per-Class pattern.
- **Property Graph Schema (Generated):** A GoogleSQL `CREATE PROPERTY GRAPH` statement mapping nodes and edges with multi-label hierarchies.

## Mapping Strategy

1. **Class Taxonomy to Spanner Table Mapping:**
   - **Table-Per-Class Design:** Map each concrete leaf `owl:Class` to a dedicated physical Spanner table. Superclass properties (`rdfs:subClassOf`) are flattened into child tables as physical columns.
   - **Disjointness (`owl:disjointWith`):** Enforced via physical separation into distinct SQL tables with independent primary key spaces, guaranteeing non-overlap.
   - **Equivalent Classes (`owl:equivalentClass`):** Represent dynamic class rules or threshold expressions as `STORED` Generated Columns in SQL (e.g., `ColumnName AS (Expression) STORED`).
   - **Multi-Label Class Hierarchies:** Model class inheritance in the Property Graph by attaching multiple `LABEL` declarations to a `NODE TABLE` (e.g., `LABEL PersonalAccount LABEL Account`).

2. **Property Mapping & Hierarchy:**
   - **Localized Property Ranges (`owl:allValuesFrom`):** Enforce range restrictions using explicit foreign key constraints targeting dedicated physical child tables (e.g., `CONSTRAINT FK_Name FOREIGN KEY (...) REFERENCES ChildTable(...)`).
   - **Transitive Properties (`owl:TransitiveProperty`):** Map parent-child hierarchy edges to physical Interleaved Tables (`INTERLEAVE IN PARENT ParentTable ON DELETE CASCADE`). Evaluate paths via GQL variable-length path matching.
   - **Symmetric Properties (`owl:SymmetricProperty`):** Store single directional rows in relational storage; traverse bidirectionally in GQL queries.
   - **Inverse Properties (`owl:inverseOf`):** Store physically in one direction; query in reverse using GQL directed pattern matching.

## Critical Spanner Graph DDL Rules

To avoid Spanner DDL parser failures, observe the following rules:

1. **Rule 1: Individual Label Binding (Multi-Label Rule):**
   Google Cloud Spanner's DDL parser evaluates property scope clauses strictly per label declaration. A `PROPERTIES (...)` block binds **EXCLUSIVELY** to the single `LABEL` statement immediately preceding it. Unattached preceding labels silently default to `PROPERTIES ALL COLUMNS`, leading to signature mismatch errors.

   - **Incorrect:**
     ```sql
     LABEL HAS_LEGAL_OWNER 
     LABEL HAS_OWNER 
     LABEL HAS_ASSOCIATED_PARTY PROPERTIES (AccountId, PartyId)
     ```
   - **Correct:**
     ```sql
     LABEL HAS_LEGAL_OWNER PROPERTIES (AccountId, Balance, OwnerId) 
     LABEL HAS_OWNER PROPERTIES (AccountId, Balance, OwnerId) 
     LABEL HAS_ASSOCIATED_PARTY PROPERTIES (AccountId, PartyId)
     ```

2. **Rule 2: Shared Label Uniformity Across Tables:**
   If a `LABEL` name is declared across multiple edge or node tables, **EVERY** instance of that label MUST expose an identical property signature (identical property names and compatible types).

   - **Incorrect:**
     ```sql
     -- Table A
     LABEL HAS_ASSOCIATED_PARTY PROPERTIES (AccountId, OwnerPersonId AS PartyId) 
     -- Table B
     LABEL HAS_ASSOCIATED_PARTY PROPERTIES (AccountId, SignatoryPersonId)
     ```
   - **Correct:**
     ```sql
     -- Table A
     LABEL HAS_ASSOCIATED_PARTY PROPERTIES (AccountId, OwnerPersonId AS PartyId) 
     -- Table B
     LABEL HAS_ASSOCIATED_PARTY PROPERTIES (AccountId, SignatoryPersonId AS PartyId)
     ```

3. **Rule 3: Primary Key Alignment in Interleaved Tables:**
   The primary key of an interleaved child table MUST begin with the exact column name(s) of the parent table's primary key.

   - **Incorrect:** Parent PK is `EntityId`, Child PK is `(ParentEntityId, ChildEntityId)`.
   - **Correct:** Parent PK is `EntityId`, Child PK is `(EntityId, ChildEntityId)`.

## Non-Translatable OWL Capabilities (System Gaps)

Flag the following constructs as requiring application logic, database triggers, or query-time execution:
- **Cardinality Constraints (`owl:maxCardinality`, `owl:cardinality`):** Cannot be enforced natively in Spanner DDL; requires application-level validation or triggers.
- **Disjoint Properties (`owl:propertyDisjointWith`):** Spanner cannot natively prevent identical entity pairs from existing across two edge tables simultaneously.
- **Property Chain Axioms (`owl:propertyChainAxiom`):** Multi-hop inferences are not automatically materialized; evaluate dynamically via GQL path pattern matching.
- **Property Characteristics (`owl:IrreflexiveProperty`, `owl:AsymmetricProperty`):** Must be enforced via SQL `CHECK` constraints or query-time filters.
