# Example Ontologies and Schemas

This directory contains test ontologies (in Turtle `.ttl` syntax) and generated/corrected Google Cloud Spanner SQL schemas used to test and verify the RDF-to-Spanner Graph DDL translation pipeline.

---

## Files Guide

| File | Type | Description |
| :--- | :--- | :--- |
| **`fintech.ttl`** | Input RDF Ontology | A valid, clean sample OWL ontology modeling a financial technology domain. It contains accounts, parties, and relationships designed to exercise all translation rules. |
| **`pharma.ttl`** | Input RDF Ontology | A drug discovery ontology modeling chemical compounds, protein targets, and diseases, useful for testing drug indications and binding affinities. |
| **`entertainment.ttl`** | Input RDF Ontology | An IMDb-like ontology modeling creative works, movies, actors, and directors, designed to test attributes/properties on edge relations (e.g. character name/billing order). |
| **`knowledgebase.ttl`** | Input RDF Ontology | A Wikipedia-style ontology modeling articles, category hierarchies, and linkage networks, testing transitive category relations and symmetric linkages. |
| **`social_fraud.ttl`** | Input RDF Ontology | A social network and fraud detection ontology modeling transactions, device sharing, and phone/IP linking, ideal for testing complex GQL patterns. |

---

## Domain Concepts Covered

The ontologies test the translation logic against key OWL semantics:

1. **Class Inheritance & Hierarchies:**
   - Account/Subclass mappings (Table-Per-Class pattern), with inheritance preserved dynamically via `LABEL` declarations in the logical property graph.
2. **Symmetric Relationships:**
   - The relationship `isPartnerOf` (Organization) and `linkedWith` (Article) are symmetric. The generated SQL uses constraints to store only one direction, while GQL pattern queries traverse it bidirectionally.
3. **Transitive Relationships:**
   - `subCategoryOf` (Wikipedia Category) and `subAccountOf` (Fintech Account) are transitive.
4. **Properties on Edges:**
   - Properties like `affinityKi` on `bindsTo` (Pharma) and `characterName`/`billingOrder` on `actedIn` (Entertainment) map directly to edge properties.

---

## Running Tests with Examples

### 1. Run AI Translation Only
```bash
rdf-spanner-translator translate \
  -i examples/pharma.ttl \
  -o output/pharma_schema.sql
```

### 2. Run Pipeline with Validation & Self-Correction
```bash
export SPANNER_DATABASE="projects/<PROJECT_ID>/instances/<INSTANCE_ID>/databases/<DATABASE_ID>"

rdf-spanner-translator run \
  -i examples/entertainment.ttl \
  -o output/entertainment_schema.sql \
  --mcp-tool "create_database"
```
