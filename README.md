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

> [!IMPORTANT]
> **Viewing Generated HTML Reports:**
> GitHub's web interface displays raw source code and does not execute JavaScript or render HTML styles.
> * **Local Viewing (Recommended):** Open the generated `.html` files in any web browser (Google Chrome, Safari, Firefox, Edge) or run `open output/report.html` on macOS to view the interactive Mermaid graph diagrams, scorecard KPIs, and developer guides.
> * **Browsing on GitHub:** Download the raw `.html` file from the repository and open it locally in your browser.

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

### Spanner Targets & Resolution Precedence

You can target Spanner instances or specific databases using environment variables or CLI flags:

```bash
# Instance path (Used for automated ephemeral test databases & batch processing)
export SPANNER_INSTANCE="projects/<PROJECT_ID>/instances/<INSTANCE_ID>"

# Specific database path (Used for targeted updates to a pre-existing persistent database)
export SPANNER_DATABASE="projects/<PROJECT_ID>/instances/<INSTANCE_ID>/databases/<DATABASE_ID>"
```

#### Flag & Target Precedence Matrix

| Command / Workflow | Scope | Primary Target Parameter | Provisioning Behavior & Database Lifecycle |
| :--- | :--- | :--- | :--- |
| **`pipeline` (Ephemeral)** | Single File or Directory (`evals/ontologies/`) | `--instance` / `$SPANNER_INSTANCE` | **Automated Lifecycle**: Provisions isolated temporary test database (`rdf2lpg_<uuid>`), compiles schema, verifies queries, and **auto-deletes** upon completion. |
| **`pipeline` (Persistent)** | Single File Only | `--database` / `$SPANNER_DATABASE` | **In-Place Update**: Applies DDL updates directly to your existing database. Database is **never deleted**. |
| **`validate`** | Single Schema (`.sql`) | `--database` / `$SPANNER_DATABASE` | Compiles DDL or runs dynamic GQL query verification against the specified existing database. |
| **`cleanup-databases`** | Instance Level | `--instance` / `$SPANNER_INSTANCE` | Scans the instance via REST API and batch-deletes all stale `rdf2lpg_*` (and legacy `t_*`) databases. |

> [!TIP]
> - **Use `SPANNER_INSTANCE`** for hands-off, automated testing where ephemeral databases are created and destroyed automatically (ideal for CI/CD and batch directory runs).
> - **Use `SPANNER_DATABASE`** when targeting a specific persistent development or staging database that you maintain.

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
| **`cleanup-databases`** | **Instance Database Pruner** | `--instance <instance_path>`<br>`--prefix <prefix>` (default: `rdf2lpg_`)<br>`--all-temp / --no-all-temp` | Lists and batch-deletes accumulated temporary test databases from a Spanner instance via direct REST API to prevent hitting instance limits. |

---

### Command Examples

#### `translate` (Offline Generation)
```bash
# Translate ontology and SHACL shapes to Spanner DDL:
rdf-spanner-translator translate \
  --input industry_ontologies/fintech/fintech.ttl \
  --shacl industry_ontologies/fintech/shacl.ttl \
  --output output/industry_ontologies/fintech_schema.sql
```

#### `validate` (Targeted or Comprehensive Validation)
```bash
export SPANNER_DATABASE="projects/<PROJECT>/instances/<INSTANCE>/databases/<DATABASE>"

# Syntax compilation check only
rdf-spanner-translator validate \
  --ddl output/industry_ontologies/fintech_schema.sql \
  --database $SPANNER_DATABASE \
  --syntax-only

# Static semantic audit & HTML developer mapping guide
rdf-spanner-translator validate \
  --input industry_ontologies/fintech/fintech.ttl \
  --ddl output/industry_ontologies/fintech_schema.sql \
  --output output/industry_ontologies/fintech_validation_report.html \
  --semantic-only

# Dynamic data ingestion & live GQL query testing
rdf-spanner-translator validate \
  --input industry_ontologies/fintech/fintech.ttl \
  --ddl output/industry_ontologies/fintech_schema.sql \
  --database $SPANNER_DATABASE \
  --output output/industry_ontologies/fintech_query_report.md \
  --queries-only

# Full validation in one command:
rdf-spanner-translator validate \
  --input industry_ontologies/fintech/fintech.ttl \
  --ddl output/industry_ontologies/fintech_schema.sql \
  --database $SPANNER_DATABASE \
  --mode all
```

#### `pipeline` (End-to-End Automated Pipeline)
```bash
export SPANNER_DATABASE="projects/<PROJECT>/instances/<INSTANCE>/databases/<DATABASE>"
export SPANNER_INSTANCE="projects/<PROJECT>/instances/<INSTANCE>"

# Single ontology end-to-end pipeline:
rdf-spanner-translator pipeline \
  --input industry_ontologies/fintech/fintech.ttl \
  --shacl industry_ontologies/fintech/shacl.ttl \
  --output output/industry_ontologies/fintech_schema.sql \
  --report output/industry_ontologies/fintech_validation_report.html \
  --database $SPANNER_DATABASE \
  --verify-queries

# Batch pipeline for all evaluation test ontologies (with summary scorecard & cleanup):
rdf-spanner-translator pipeline \
  --input evals/ontologies/ \
  --instance $SPANNER_INSTANCE \
  --verify-queries

# Batch pipeline for all industry domain ontologies with self-contained bundling:
rdf-spanner-translator pipeline \
  --input industry_ontologies/ \
  --instance $SPANNER_INSTANCE \
  --bundle-examples
```

#### `validate` & `pipeline` using Local Spanner Emulator (`--emulator`)
If you want to validate schemas locally without connecting to Google Cloud Spanner or Remote MCP, use the local Cloud Spanner Emulator:

1. **Start the Spanner Emulator via Docker:**
   ```bash
   docker run -d -p 9010:9010 -p 9020:9020 gcr.io/cloud-spanner-emulator/emulator
   ```

2. **Run validation or pipeline with `--emulator`:**
   ```bash
   # Syntax check on emulator:
   rdf-spanner-translator validate \
     --ddl output/industry_ontologies/fintech_schema.sql \
     --emulator \
     --syntax-only

   # End-to-end translation & validation on emulator:
   rdf-spanner-translator pipeline \
     --input industry_ontologies/fintech/fintech.ttl \
     --emulator
   ```

3. **Or set the environment variable:**
   ```bash
   export SPANNER_EMULATOR_HOST="http://localhost:9020"
   # All commands will automatically use the emulator
   rdf-spanner-translator pipeline --input evals/ontologies/
   ```

#### `cleanup-databases` (Instance Pruning)
```bash
export SPANNER_INSTANCE="projects/<PROJECT>/instances/<INSTANCE>"

# List and purge all temporary test databases (rdf2lpg_*) from the Spanner instance:
rdf-spanner-translator cleanup-databases --instance $SPANNER_INSTANCE

# Or clean up databases on the local emulator:
rdf-spanner-translator cleanup-databases --emulator
```