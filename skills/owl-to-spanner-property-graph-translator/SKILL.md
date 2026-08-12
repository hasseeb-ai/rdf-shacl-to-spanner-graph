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

4. **Rule 4: Google Cloud Spanner Property Graph Syntax:**
   Google Cloud Spanner Property Graph DDL has a specific syntax. Node definitions inside `NODE TABLES` must **NOT** specify keys (like `KEY (Id)`), and edges inside `EDGE TABLES` must use `SOURCE KEY (...) REFERENCES ...` and `DESTINATION KEY (...) REFERENCES ...` clauses (do **NOT** use `FROM ... TO ...` syntax).

   - **Incorrect:**
     ```sql
     CREATE PROPERTY GRAPH FintechGraph
       NODE TABLES (
         People KEY (PersonId)
           LABEL Person PROPERTIES (PersonId, Name)
       )
       EDGE TABLES (
         PersonalAccountOwners
           FROM PersonalAccounts KEY (AccountId)
           TO People KEY (PersonId)
           LABEL HAS_OWNER
       );
     ```
   - **Correct:**
     ```sql
     CREATE PROPERTY GRAPH FintechGraph
       NODE TABLES (
         People
           LABEL Person PROPERTIES (PersonId, Name)
       )
       EDGE TABLES (
         PersonalAccountOwners
           SOURCE KEY (AccountId) REFERENCES PersonalAccounts (AccountId)
           DESTINATION KEY (PersonId) REFERENCES People (PersonId)
           LABEL HAS_OWNER
       );
     ```

5. **Rule 5: Edge Table Name Uniqueness (Aliasing):**
   If a physical relational table is used to define multiple edge tables in `EDGE TABLES` block of a `CREATE PROPERTY GRAPH` statement, each mapping must be named uniquely. Use the `AS` keyword to alias them uniquely.

   - **Incorrect:**
     ```sql
     EDGE TABLES (
       PersonalAccountOwners
         SOURCE KEY (AccountId) REFERENCES PersonalAccounts (AccountId)
         DESTINATION KEY (PersonId) REFERENCES People (PersonId)
         LABEL HAS_OWNER,
       PersonalAccountOwners
         SOURCE KEY (AccountId) REFERENCES PersonalAccounts (AccountId)
         DESTINATION KEY (SignatoryId) REFERENCES People (PersonId)
         LABEL HAS_SIGNATORY
     )
     ```
   - **Correct:**
     ```sql
     EDGE TABLES (
       PersonalAccountOwners
         SOURCE KEY (AccountId) REFERENCES PersonalAccounts (AccountId)
         DESTINATION KEY (PersonId) REFERENCES People (PersonId)
         LABEL HAS_OWNER,
       PersonalAccountOwners AS PersonalAccountSignatories
         SOURCE KEY (AccountId) REFERENCES PersonalAccounts (AccountId)
         DESTINATION KEY (SignatoryId) REFERENCES People (PersonId)
         LABEL HAS_SIGNATORY
     )
     ```

6. **Rule 6: Strict Name Resolution in SQL Views:**
   Google Cloud Spanner uses a strict name resolution mode. When referencing columns inside a SQL view's `SELECT`, `JOIN`, or `WHERE` clauses, always qualify the columns with their table name or table alias. Do not reference bare select-list aliases inside a `WHERE` clause of the same query block.

   - **Incorrect:**
     ```sql
     CREATE VIEW HighValueLoans SQL SECURITY INVOKER AS
     SELECT 
       LoanId,
       loanAmount AS amount,
       interestRate
     FROM Loans
     WHERE amount > 1000000;
     ```
   - **Correct:**
     ```sql
     CREATE VIEW HighValueLoans SQL SECURITY INVOKER AS
     SELECT 
       l.LoanId,
       l.loanAmount AS amount,
       l.interestRate
     FROM Loans l
     WHERE l.loanAmount > 1000000;
     ```

7. **Rule 7: Spanner Generated Column Syntax:**
   Always declare Spanner generated columns using the syntax: `<ColumnName> <DataType> AS (<Expression>) STORED`. Do NOT use standard SQL's `GENERATED ALWAYS AS` syntax, which is not supported in GoogleSQL.

   - **Incorrect:**
     ```sql
     CREATE TABLE Loans (
       LoanId STRING(36) NOT NULL,
       LoanAmount NUMERIC,
       IsSignificant BOOL GENERATED ALWAYS AS (LoanAmount > 10000000) STORED
     ) PRIMARY KEY (LoanId);
     ```
   - **Correct:**
     ```sql
     CREATE TABLE Loans (
       LoanId STRING(36) NOT NULL,
       LoanAmount NUMERIC,
       IsSignificant BOOL AS (LoanAmount > 10000000) STORED
     ) PRIMARY KEY (LoanId);
     ```

8. **Rule 8: Table-Per-Concrete-Class Pattern (Flattening Superclasses):**
   Do not generate physical relational tables for abstract or non-leaf superclasses. All inherited properties must be flattened directly as physical columns into the concrete leaf class tables. This ensures every node table maps directly to a physical table with a native `PRIMARY KEY`, avoiding complex SQL `JOIN` views.

   - **Incorrect (Normalized / Parent-Child tables):**
     ```sql
     CREATE TABLE Users (
       UserId STRING(36) NOT NULL,
       UserName STRING(MAX)
     ) PRIMARY KEY (UserId);

     CREATE TABLE Customers (
       UserId STRING(36) NOT NULL, -- Superclass property 'UserName' is missing!
     ) PRIMARY KEY (UserId),
       INTERLEAVE IN PARENT Users ON DELETE CASCADE;
     ```
   - **Correct (Flattened Concrete class):**
     ```sql
     CREATE TABLE Customers (
       UserId STRING(36) NOT NULL,
       UserName STRING(MAX) -- Flattened directly into the concrete subclass table
     ) PRIMARY KEY (UserId);
     ```

9. **Rule 9: View-Based Node Table Keys:**
   If a node table is mapped to a SQL View rather than a physical table, you **must** explicitly specify the `KEY (<column>)` clause. To ensure Spanner can verify key uniqueness:
   1. Avoid complex `JOIN` operations on the key column inside the view.
   2. Ensure the key column corresponds directly to the `PRIMARY KEY` of a single underlying physical table.

   - **Incorrect:**
     ```sql
     NODE TABLES (
       v_Facilities -- Error: views do not have primary keys in database schema
         LABEL Facility PROPERTIES (LocationId, FacilityName)
     )
     ```
   - **Correct:**
     ```sql
     NODE TABLES (
       v_Facilities KEY (LocationId) -- Declares the verifiable unique key column
         LABEL Facility PROPERTIES (LocationId, FacilityName)
     )
     ```

10. **Rule 10: Property Graph Table and Label Separation:**
    In `NODE TABLES` and `EDGE TABLES` blocks:
    1. Separate different table mappings using commas.
    2. Do **not** use commas to separate multiple `LABEL` declarations within the exact same table mapping.

    - **Incorrect:**
      ```sql
      Customers
        LABEL Customer PROPERTIES (UserId), -- Error: Comma here is invalid
        LABEL User PROPERTIES (UserId),
      Merchants
        ...
      ```
    - **Correct:**
      ```sql
      Customers
        LABEL Customer PROPERTIES (UserId)  -- No comma here
        LABEL User PROPERTIES (UserId),     -- Comma separates different tables (Customers -> Merchants)
      Merchants
        ...
      ```

## SHACL Shapes DDL Translation Rules (Optional Input)

When an optional SHACL shapes file (`shacl.ttl`) is provided alongside the OWL ontology, use the SHACL shapes as structural constraints to refine the physical relational columns, datatypes, and database validations:

1. **Table Names & Node Labels (`sh:targetClass`):**
   - A `sh:NodeShape` targeting a class (`sh:targetClass <ClassURI>`) corresponds directly to the physical relational table and property graph node representing that class.

2. **Column Names & Mappings (`sh:path`):**
   - Property shapes inside `sh:property` define attributes (`sh:path <PropertyURI>`). Map `<PropertyURI>` to the column name of the target table.

3. **Data Type Mapping (`sh:datatype`):**
   - Translate SHACL XSD datatypes to Spanner GoogleSQL types:
     * `xsd:string` -> `STRING(MAX)` (or specific limit)
     * `xsd:integer` / `xsd:int` -> `INT64`
     * `xsd:decimal` -> `NUMERIC`
     * `xsd:double` / `xsd:float` -> `FLOAT64`
     * `xsd:boolean` -> `BOOL`
     * `xsd:dateTime` -> `TIMESTAMP`
     * `xsd:date` -> `DATE`

4. **Nullability / Required Columns (`sh:minCount`):**
   - If a property shape has `sh:minCount 1` or greater, the column in the physical table DDL must be marked as `NOT NULL`.
   - *Example:*
     ```ttl
     [ sh:path ex:name ; sh:datatype xsd:string ; sh:minCount 1 ]
     ```
     translates to:
     ```sql
     Name STRING(MAX) NOT NULL
     ```

5. **Column Cardinality (`sh:maxCount`):**
   - If `sh:maxCount 1` is specified, the property is a single-valued scalar column directly in the table.
   - If `sh:maxCount` is omitted or greater than 1, and it is a datatype property, it represents a multi-valued field. In Spanner, implement this as an interleaved child table or an array column (`ARRAY<T>`), preferring interleaved tables for complex relationships.

6. **Relational Constraints & Foreign Keys (`sh:class`):**
   - If a property shape on an object property specifies `sh:class <TargetClass>`, it defines a relationship pointing to `<TargetClass>`. 
   - Relational: Map this as a foreign key column referencing the primary key of the `<TargetClass>` table.
   - Property Graph: Map this as an edge mapping in `EDGE TABLES` with `SOURCE KEY` pointing to the domain table and `DESTINATION KEY` pointing to the `<TargetClass>` table.
   - *Example:*
     ```ttl
     [ sh:path ex:hasOwner ; sh:class ex:Person ]
     ```
     translates to:
     ```sql
     OwnerId STRING(36) NOT NULL,
     CONSTRAINT FK_Owner FOREIGN KEY (OwnerId) REFERENCES People (PersonId)
     ```

7. **Domain Check Constraints (`sh:in` / `sh:hasValue`):**
   - If a property has `sh:in` with a list of values, enforce this domain check physically using a Spanner `CHECK` constraint.
   - *Example:*
     ```ttl
     [ sh:path ex:accountStatus ; sh:in ( "Active" "Suspended" "Closed" ) ]
     ```
     translates to:
     ```sql
     AccountStatus STRING(50) NOT NULL,
     CONSTRAINT CK_AccountStatus CHECK (AccountStatus IN ('Active', 'Suspended', 'Closed'))
     ```

## Non-Translatable OWL Capabilities (System Gaps)

Flag the following constructs as requiring application logic, database triggers, or query-time execution:
- **Cardinality Constraints (`owl:maxCardinality`, `owl:cardinality`):** Cannot be enforced natively in Spanner DDL; requires application-level validation or triggers.
- **Disjoint Properties (`owl:propertyDisjointWith`):** Spanner cannot natively prevent identical entity pairs from existing across two edge tables simultaneously.
- **Property Chain Axioms (`owl:propertyChainAxiom`):** Multi-hop inferences are not automatically materialized; evaluate dynamically via GQL path pattern matching.
- **Property Characteristics (`owl:IrreflexiveProperty`, `owl:AsymmetricProperty`):** Must be enforced via SQL `CHECK` constraints or query-time filters.
