# rdf-shacl-to-spanner-graph

A **Antigravity CLI plugin** and standalone CLI tool that translates RDF/OWL ontologies (in Turtle `.ttl` syntax) and SHACL shapes into Google Cloud Spanner schemas (Relational SQL DDL and Logical Property Graph DDL), validates syntax using Spanner Remote MCP, and generates comprehensive developer-focused HTML validation reports with visual graph diagrams.

---

## Plugin Installation (Antigravity CLI)

To install this as a native plugin in your local **Antigravity CLI** installation:

- Clone this repository and navigate to the directory:
  ```bash
  git clone <repo-url> rdf-shacl-to-spanner-graph
  cd rdf-shacl-to-spanner-graph
  ```

- Set up a virtual environment and install the dependencies:
  ```bash
  python3 -m venv .venv
  source .venv/bin/activate
  pip install -r requirements.txt
  ```

- Install the plugin using the `agy` CLI:
  ```bash
  agy plugin install .
  ```

- Restart your `agy` session. The plugin will automatically configure:
  - **Native Translation Skill**: The translation skill ([`skills/owl-to-spanner-property-graph-translator/SKILL.md`](skills/owl-to-spanner-property-graph-translator/SKILL.md)) teaches the model ontology-to-Spanner mapping rules, inheritance flattening, and property graph DDL constraints dynamically.
  - **Native Semantic Validation Skill**: The validation skill ([`skills/spanner-graph-semantic-validator/SKILL.md`](skills/spanner-graph-semantic-validator/SKILL.md)) audits generated schemas across 7 semantic dimensions and generates standalone 5-section styled HTML reports with visual Mermaid diagrams, mapping matrices, GQL query cheatsheets, and collapsible code inspectors.
  - **Native Query Verification Skill**: The query verification skill ([`skills/spanner-graph-query-verifier/SKILL.md`](skills/spanner-graph-query-verifier/SKILL.md)) synthesizes coherent test data (SQL `INSERT`s) and 4 GQL query archetypes.
  - **Custom Tools**: Registers `translate_rdf_to_spanner_graph_ddl` and `validate_spanner_graph_ddl` as tools available to the model via the MCP server.

---

## Authentication & Configuration

The plugin and standalone CLI require access to the Gemini API and Google Cloud Spanner. You can configure authentication using one of two methods:

### Google AI Studio (API Key)
```bash
export GEMINI_API_KEY="your-api-key-here"
```

### Vertex AI (Google Cloud ADC)
If `GEMINI_API_KEY` is not set, the tool falls back to Vertex AI. Authenticate using Application Default Credentials:
```bash
gcloud auth application-default login
```

---

## Standalone CLI Usage

You can also run the translator and validator directly as a standalone CLI tool without launching the full `agy` shell.

### Installation for Standalone CLI
With the virtual environment active, install the package in editable mode:
```bash
pip install -e . --no-build-isolation
```

### CLI Commands

The CLI is organized into **4 core commands** (`translate`, `validate`, `pipeline`, and `cleanup-databases`):

| Command | Operational Usage | Key Parameters & Flags | Description |
| :--- | :--- | :--- | :--- |
| **`translate`** | **Offline Translation** | `--input <ont.ttl>`<br>`--shacl <shacl.ttl>`<br>`--output <schema.sql>`<br>`--model <model>` | Translates OWL Turtle ontologies and companion SHACL shapes into GoogleSQL & Spanner Property Graph DDL offline. |
| **`validate`** | **Syntax Compilation Check** | `--ddl <schema.sql>`<br>`--database <db_path>`<br>`--syntax-only`<br>`--mcp-tool <tool_name>` | Validates that physical and logical DDL compiles cleanly against Cloud Spanner via the Remote Spanner MCP server. |
| | **Semantic Audit & Mapping Guide** | `--input <ont.ttl>`<br>`--ddl <schema.sql>`<br>`--shacl <shacl.ttl>`<br>`--output <report.html>`<br>`--semantic-only` | Audits generated DDL against 7 semantic dimensions producing an interactive 5-section standalone HTML report with visual topology diagrams, node/edge mapping tables, GQL cheatsheet, and collapsible raw source inspector. |
| | **Dynamic GQL Query Verification** | `--input <ont.ttl>`<br>`--ddl <schema.sql>`<br>`--database <db_path>`<br>`--output <report.md>`<br>`--queries-only` | Synthesizes linked test fixtures (DML), ingests them into Spanner, executes 4 GQL queries live, and synthesizes an executive execution report. |
| | **Full Multi-Level Validation** | `--input <ont.ttl>`<br>`--ddl <schema.sql>`<br>`--database <db_path>`<br>`--mode all` (Default) | Runs all validation stages sequentially (Syntax Check $\to$ Semantic HTML Report $\to$ Dynamic GQL Queries). |
| **`pipeline`** | **Automated End-to-End** | `--input <ont.ttl \| dir>`<br>`--instance <instance_path>`<br>`--database <db_path>`<br>`--shacl <shacl.ttl>`<br>`--output <schema.sql>`<br>`--report <report.html>`<br>`--verify-queries`<br>`--cleanup / --no-cleanup` | Complete automated workflow: Translates ontology (or entire directory in batch mode), validates syntax on Spanner, auto-corrects compiler errors, audits semantics into HTML reports, tests queries, and cleans up test databases. |
| **`cleanup-databases`** | **Instance Database Pruner** | `--instance <instance_path>`<br>`--prefix <prefix>` (default: `t_`)<br>`--all-temp / --no-all-temp` | Lists and batch-deletes accumulated temporary test databases from a Spanner instance via direct REST API to prevent hitting instance limits. |

---

### Command Examples

#### `translate` (Offline Generation)
```bash
# Translate ontology and SHACL shapes to Spanner DDL:
rdf-spanner-translator translate \
  --input examples/fintech/fintech.ttl \
  --shacl examples/fintech/shacl.ttl \
  --output output/examples/fintech_schema.sql
```

#### `validate` (Targeted or Comprehensive Validation)
```bash
export SPANNER_DATABASE="projects/<PROJECT>/instances/<INSTANCE>/databases/<DATABASE>"

# Syntax compilation check only
rdf-spanner-translator validate \
  --ddl output/examples/fintech_schema.sql \
  --database $SPANNER_DATABASE \
  --syntax-only

# Static semantic audit & HTML developer mapping guide
rdf-spanner-translator validate \
  --input examples/fintech/fintech.ttl \
  --ddl output/examples/fintech_schema.sql \
  --output output/examples/fintech_validation_report.html \
  --semantic-only

# Dynamic data ingestion & live GQL query testing
rdf-spanner-translator validate \
  --input examples/fintech/fintech.ttl \
  --ddl output/examples/fintech_schema.sql \
  --database $SPANNER_DATABASE \
  --output output/examples/fintech_query_report.md \
  --queries-only

# Full validation in one command:
rdf-spanner-translator validate \
  --input examples/fintech/fintech.ttl \
  --ddl output/examples/fintech_schema.sql \
  --database $SPANNER_DATABASE \
  --mode all
```

#### `pipeline` (End-to-End Automated Pipeline)
```bash
export SPANNER_DATABASE="projects/<PROJECT>/instances/<INSTANCE>/databases/<DATABASE>"
export SPANNER_INSTANCE="projects/<PROJECT>/instances/<INSTANCE>"

# Single ontology end-to-end pipeline:
rdf-spanner-translator pipeline \
  --input examples/fintech/fintech.ttl \
  --shacl examples/fintech/shacl.ttl \
  --output output/examples/fintech_schema.sql \
  --report output/examples/fintech_validation_report.html \
  --database $SPANNER_DATABASE \
  --verify-queries

# Batch pipeline for all unit test ontologies (with summary scorecard & cleanup):
rdf-spanner-translator pipeline \
  --input tests/ontologies/ \
  --instance $SPANNER_INSTANCE \
  --verify-queries

# Batch pipeline for all domain examples with self-contained bundling:
rdf-spanner-translator pipeline \
  --input examples/ \
  --instance $SPANNER_INSTANCE \
  --bundle-examples
```

#### `cleanup-databases` (Instance Pruning)
```bash
export SPANNER_INSTANCE="projects/<PROJECT>/instances/<INSTANCE>"

# List and purge all temporary test databases (t_*) from the Spanner instance:
rdf-spanner-translator cleanup-databases --instance $SPANNER_INSTANCE
```