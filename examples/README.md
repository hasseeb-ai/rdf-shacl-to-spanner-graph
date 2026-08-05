# Example Ontologies and Schemas

This directory contains test ontologies (in Turtle `.ttl` syntax) and generated/corrected Google Cloud Spanner SQL schemas used to test and verify the RDF-to-Spanner Graph DDL translation pipeline.

---

## Files Guide

| File | Type | Description |
| :--- | :--- | :--- |
| **`fintech.ttl`** | Input RDF Ontology | A valid, clean sample OWL ontology modeling a financial technology domain. It contains accounts, parties, and relationships designed to exercise all translation rules. |
| **`fintech_err.ttl`** | Input RDF Ontology | A modified version of `fintech.ttl` designed to trigger Spanner compilation errors during testing of the pipeline's **Self-Correction Loop**. |
| **`schema.sql`** | Output Spanner DDL | The compiled relational table schemas and logical graph definition translated directly from `fintech.ttl`. |
| **`schema_corrected.sql`** | Output Spanner DDL | A corrected Spanner DDL output created by the self-repair loop during validation testing. |
| **`schema_run.sql`** | Output Spanner DDL | A temporary target file generated during validation runs. |

---

## Domain Concepts Covered

The **`fintech.ttl`** ontology tests the translation logic against key OWL semantics:

1. **Class Inheritance & Hierarchies:**
   - `Account` (Parent) has child subclasses `PersonalAccount` and `CorporateAccount`.
   - `Party` (Parent) has child subclasses `Person` and `Organization`.
   - Concrete leaf classes are mapped to relational tables (Table-Per-Class pattern), while inheritance is preserved dynamically via `LABEL` declarations in the logical property graph.

2. **Symmetric Relationships:**
   - The relationship `isPartnerOf` between organizations is symmetric. The generated SQL uses a `CHECK` constraint to store only one direction `(OrgA < OrgB)` in the relational database, while allowing GQL pattern queries to traverse it bidirectionally.

3. **Transitive Relationships:**
   - The relationship `subAccountOf` represents a transitive account-subaccount tree. It maps to an interleaved table setup or hierarchical path tracking table.

4. **Multi-Label Entity Binding (Rule 1 & Rule 2):**
   - The property graph handles uniform label property binding to ensure property signatures match exactly across nodes and edges (e.g. mapping `PersonId` and `OrganizationId` to a uniform `PartyId` property on the `Party` node label).

---

## Running Tests with Examples

### 1. Run AI Translation Only
```bash
rdf-spanner-translator translate -i examples/fintech.ttl -o examples/schema.sql
```

### 2. Run Pipeline with Mock Validation
To run the full pipeline and test validation using the offline mock server:
```bash
rdf-spanner-translator run \
  -i examples/fintech.ttl \
  -o examples/schema.sql \
  -c "python3 tests/mock_spanner_mcp.py"
```
