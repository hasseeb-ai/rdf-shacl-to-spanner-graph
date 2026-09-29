# rdf-shacl-to-spanner-graph

An **Antigravity CLI plugin** and standalone CLI tool that translates RDF/OWL ontologies (in Turtle `.ttl` syntax) and SHACL shapes into Google Cloud Spanner schemas (Relational SQL DDL and Logical Property Graph DDL), validates syntax using Spanner Remote MCP or Local Cloud Spanner Emulator, **loads RDF instance triples (ABox `.ttl`, `.nt`, `.rdf`, `.jsonld`) into Spanner**, and generates comprehensive developer-focused HTML validation reports and live GQL query execution reports.

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
  - **Native RDF Triples Loader Skill**: The triples loader skill ([`skills/rdf-triples-to-spanner-loader/SKILL.md`](skills/rdf-triples-to-spanner-loader/SKILL.md)) maps RDF instance triples (ABox) to Spanner physical node/edge tables, embedded foreign keys, flattened blank nodes, inverse properties, and `rdf:Statement` reification, producing topologically sorted GoogleSQL `INSERT` statements.
  - **Native Query Verification Skill**: The query verification skill ([`skills/spanner-graph-query-verifier/SKILL.md`](skills/spanner-graph-query-verifier/SKILL.md)) synthesizes coherent test data (or uses preloaded RDF triples) and executes 4 semantic GQL query archetypes.
  - **Custom Tools**: Registers `translate_rdf_to_spanner_graph_ddl`, `validate_spanner_graph_ddl`, `validate_spanner_graph_semantics`, `load_rdf_triples_to_spanner`, and `verify_spanner_graph_queries` as tools available to the model via the MCP server.

> [!IMPORTANT]
> **Viewing Generated HTML Reports:**
> GitHub's web interface displays raw source code and does not execute JavaScript or render HTML styles.
> * **Local Viewing (Recommended):** Open the generated `.html` files in any web browser (Google Chrome, Safari, Firefox, Edge) or run `open output/report.html` on macOS to view the interactive Mermaid graph diagrams, scorecard KPIs, and developer guides.
> * **Browsing on GitHub:** Download the raw `.html` file from the repository and open it locally in your browser.

---

## Authentication & Configuration

The plugin and standalone CLI interact with the Gemini API (for translation, schema mapping, & semantic auditing) and Google Cloud Spanner / Remote MCP or Local Spanner Emulator (for DDL execution, RDF triples ingestion, & GQL query verification).

### 1. Gemini API (Translation & Semantic Audit)
Set your Google AI Studio API key:
```bash
export GEMINI_API_KEY="your-api-key-here"
```
*(If `GEMINI_API_KEY` is not set, the translator falls back to Vertex AI using Google Cloud ADC).*

### 2. Google Cloud Spanner / Remote MCP (DDL Compilation & Database Lifecycle)
When validating or loading data against Remote Cloud Spanner (using `--instance` or `--database` without `--emulator`), active **Application Default Credentials (ADC)** are required to provision ephemeral test databases, compile DDL statements, and ingest DML rows.

> [!IMPORTANT]
> **Pre-Step for Remote MCP / Cloud Spanner:**
> Ensure your Google Cloud ADC session is active by running:
> ```bash
> gcloud auth application-default login
> ```
> *If an ADC session has expired or is invalid, the pipeline or validator may encounter authentication failures when connecting to Remote MCP / Cloud Spanner. Running `gcloud auth application-default login` refreshes your local credentials immediately.*

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
| **`pipeline` (Ephemeral)** | Single File or Directory (`evals/ontologies/`) | `--instance` / `$SPANNER_INSTANCE` (or `--emulator`) | **Automated Lifecycle**: Provisions isolated temporary test database (`rdf2lpg_<uuid>`), compiles schema, optionally loads RDF triples (`--triples` / `--load-companion-triples`), verifies GQL queries, and **auto-deletes** upon completion. |
| **`pipeline` (Persistent)** | Single File Only | `--database` / `$SPANNER_DATABASE` | **In-Place Update**: Applies DDL updates and optional RDF triples (`--triples`) directly to your existing database. Database is **never deleted**. |
| **`load-triples`** | Single RDF Triples File (`.ttl`, `.nt`, `.rdf`, `.jsonld`) | `--database` / `$SPANNER_DATABASE` / `--emulator` / `--output-dml` | Translates RDF instance triples into topologically sorted GoogleSQL `INSERT` statements, saves them to `--output-dml`, and/or ingests them into Spanner or Emulator. |
| **`validate`** | Single Schema (`.sql`) | `--database` / `$SPANNER_DATABASE` (or `--emulator`) | Compiles DDL, optionally loads `--triples`, and runs dynamic GQL query verification against the specified database. |
| **`cleanup-databases`** | Instance Level | `--instance` / `$SPANNER_INSTANCE` (or `--emulator`) | Scans the instance via REST API and batch-deletes all stale `rdf2lpg_*` (and legacy `t_*`) databases. |

> [!TIP]
> - **Use `SPANNER_INSTANCE`** for hands-off, automated testing where ephemeral databases are created and destroyed automatically (ideal for CI/CD and batch directory runs).
> - **Use `SPANNER_DATABASE`** when targeting a specific persistent development or staging database that you maintain.

---

## Standalone CLI Usage

You can also run the translator, triples loader, and validator directly as a standalone CLI tool without launching the full `agy` shell.

### Installation for Standalone CLI
With the virtual environment active, install the package in editable mode:
```bash
pip install -e . --no-build-isolation
```

### CLI Commands

The CLI is organized into **5 core commands** (`translate`, `load-triples`, `validate`, `pipeline`, and `cleanup-databases`):

| Command | Operational Usage | Key Parameters & Flags | Description |
| :--- | :--- | :--- | :--- |
| **`translate`** | **Offline Translation** | `--input <ont.ttl>`<br>`--shacl <shacl.ttl>`<br>`--output <schema.sql>`<br>`--model <model>` | Translates OWL Turtle ontologies and companion SHACL shapes into GoogleSQL & Spanner Property Graph DDL offline. |
| **`load-triples`** | **RDF Triples to Spanner DML & Ingestion** | `--triples <triples.ttl>`<br>`--ddl <schema.sql>`<br>`--ontology <ont.ttl>`<br>`--shacl <shacl.ttl>`<br>`--output-dml <dml.sql>`<br>`--database <db_path>`<br>`--emulator`<br>`--deterministic-only` | Parses RDF instance triples (`.ttl`, `.nt`, `.rdf`, `.jsonld`), maps classes and properties to concrete physical node/edge tables and embedded FKs, emits topologically sorted GoogleSQL `INSERT` statements, and loads them into Cloud Spanner or Local Emulator. |
| **`validate`** | **Syntax Compilation Check** | `--ddl <schema.sql>`<br>`--database <db_path>`<br>`--emulator`<br>`--syntax-only` | Validates that physical and logical DDL compiles cleanly against Cloud Spanner via Remote MCP or Local Emulator. |
| | **Semantic Audit & Mapping Guide** | `--input <ont.ttl>`<br>`--ddl <schema.sql>`<br>`--shacl <shacl.ttl>`<br>`--output <report.html>`<br>`--semantic-only` | Audits generated DDL against 7 semantic dimensions producing an interactive 5-section standalone HTML report with visual topology diagrams, node/edge mapping tables, GQL cheatsheet, and collapsible raw source inspector. |
| | **Dynamic GQL Query Verification** | `--input <ont.ttl>`<br>`--ddl <schema.sql>`<br>`--triples <triples.ttl>`<br>`--database <db_path>`<br>`--emulator`<br>`--output <report.md>`<br>`--queries-only` | Ingests RDF triples (when `--triples` is provided) or synthesizes linked test fixtures (DML), executes 4 GQL queries live, and synthesizes an executive execution report. |
| | **Full Multi-Level Validation** | `--input <ont.ttl>`<br>`--ddl <schema.sql>`<br>`--triples <triples.ttl>`<br>`--database <db_path>`<br>`--mode all` (Default) | Runs all validation stages sequentially (Syntax Check $\to$ Semantic HTML Report $\to$ Optional RDF Triples Load $\to$ Dynamic GQL Queries). |
| **`pipeline`** | **Automated End-to-End** | `--input <ont.ttl \| dir>`<br>`--shacl <shacl.ttl>`<br>`--triples <triples.ttl>`<br>`--load-companion-triples`<br>`--output-dml <dml.sql>`<br>`--instance <instance_path>`<br>`--database <db_path>`<br>`--emulator`<br>`--verify-queries`<br>`--cleanup / --no-cleanup` | Complete automated workflow: Translates ontology (or entire directory in batch mode), validates syntax on Spanner/Emulator, auto-corrects compiler errors, audits semantics into HTML reports, loads RDF triples, executes GQL queries, and cleans up test databases. |
| **`cleanup-databases`** | **Instance Database Pruner** | `--instance <instance_path>`<br>`--emulator`<br>`--prefix <prefix>` (default: `rdf2lpg_`)<br>`--all-temp / --no-all-temp` | Lists and batch-deletes accumulated temporary test databases from a Spanner instance or Emulator via REST API to prevent hitting instance limits. |

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

#### `load-triples` (RDF Instance Triples to Spanner DML & Ingestion)
```bash
# 1. Generate topologically sorted Spanner SQL INSERT statements offline:
rdf-spanner-translator load-triples \
  --triples industry_ontologies/cybersecurity_threat/triples.ttl \
  --ddl industry_ontologies/cybersecurity_threat/cybersecurity_threat_schema.sql \
  --ontology industry_ontologies/cybersecurity_threat/cybersecurity_threat.ttl \
  --shacl industry_ontologies/cybersecurity_threat/shacl.ttl \
  --output-dml output/industry_ontologies/cybersecurity_threat_dml.sql \
  --deterministic-only

# 2. Translate RDF triples and ingest directly into a Cloud Spanner database:
rdf-spanner-translator load-triples \
  --triples industry_ontologies/fintech/triples.ttl \
  --ddl industry_ontologies/fintech/fintech_schema.sql \
  --ontology industry_ontologies/fintech/fintech.ttl \
  --shacl industry_ontologies/fintech/shacl.ttl \
  --output-dml output/industry_ontologies/fintech_dml.sql \
  --database $SPANNER_DATABASE

# 3. Load RDF triples into the Local Cloud Spanner Emulator:
rdf-spanner-translator load-triples \
  --triples evals/ontologies/11_comprehensive_schema_triples.ttl \
  --ddl evals/ontologies/11_comprehensive_schema_schema.sql \
  --ontology evals/ontologies/11_comprehensive_schema.ttl \
  --emulator
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

# Load RDF triples & run live GQL query verification against the loaded triples
rdf-spanner-translator validate \
  --input industry_ontologies/fintech/fintech.ttl \
  --shacl industry_ontologies/fintech/shacl.ttl \
  --ddl industry_ontologies/fintech/fintech_schema.sql \
  --triples industry_ontologies/fintech/triples.ttl \
  --output-dml output/industry_ontologies/fintech_dml.sql \
  --database $SPANNER_DATABASE \
  --output output/industry_ontologies/fintech_query_report.md \
  --queries-only

# Full validation (Syntax + Semantic HTML Report + RDF Triples Load + 4 GQL Queries) in one command:
rdf-spanner-translator validate \
  --input industry_ontologies/fintech/fintech.ttl \
  --shacl industry_ontologies/fintech/shacl.ttl \
  --ddl industry_ontologies/fintech/fintech_schema.sql \
  --triples industry_ontologies/fintech/triples.ttl \
  --database $SPANNER_DATABASE \
  --mode all
```

#### `pipeline` (End-to-End Automated Pipeline)
```bash
# 1. Ensure active Google Cloud ADC authentication (Pre-step for Remote Spanner / MCP)
gcloud auth application-default login

# 2. Set environment variables
export GEMINI_API_KEY="your-gemini-api-key"
export SPANNER_DATABASE="projects/<PROJECT>/instances/<INSTANCE>/databases/<DATABASE>"
export SPANNER_INSTANCE="projects/<PROJECT>/instances/<INSTANCE>"

# Single ontology end-to-end pipeline (Translate DDL -> Validate -> Load RDF Triples -> Verify 4 GQL Queries):
rdf-spanner-translator pipeline \
  --input industry_ontologies/fintech/fintech.ttl \
  --shacl industry_ontologies/fintech/shacl.ttl \
  --triples industry_ontologies/fintech/triples.ttl \
  --output output/industry_ontologies/fintech_schema.sql \
  --output-dml output/industry_ontologies/fintech_dml.sql \
  --report output/industry_ontologies/fintech_validation_report.html \
  --database $SPANNER_DATABASE \
  --verify-queries

# Batch pipeline for all 19 evaluation test ontologies (with companion RDF triples & GQL query verification):
rdf-spanner-translator pipeline \
  --input evals/ontologies/ \
  --instance $SPANNER_INSTANCE \
  --load-companion-triples \
  --verify-queries

# Batch pipeline for all 14 industry domain ontologies with companion RDF triples & self-contained bundling:
rdf-spanner-translator pipeline \
  --input industry_ontologies/ \
  --instance $SPANNER_INSTANCE \
  --load-companion-triples \
  --bundle-examples
```

#### `validate`, `load-triples`, & `pipeline` using Local Spanner Emulator (`--emulator`)
If you want to validate schemas, load RDF triples, and execute GQL queries locally without connecting to Google Cloud Spanner or Remote MCP, use the local Cloud Spanner Emulator:

1. **Start the Spanner Emulator via Docker:**
   ```bash
   docker run -d -p 9010:9010 -p 9020:9020 gcr.io/cloud-spanner-emulator/emulator
   ```

2. **Run validation, triple loading, or pipeline with `--emulator`:**
   ```bash
   # Syntax check + load RDF triples + run GQL queries on emulator:
   rdf-spanner-translator validate \
     --input industry_ontologies/fintech/fintech.ttl \
     --shacl industry_ontologies/fintech/shacl.ttl \
     --ddl industry_ontologies/fintech/fintech_schema.sql \
     --triples industry_ontologies/fintech/triples.ttl \
     --emulator \
     --mode all

   # End-to-end translation, DDL validation, RDF triples load, and query verification on emulator:
   rdf-spanner-translator pipeline \
     --input industry_ontologies/fintech/fintech.ttl \
     --shacl industry_ontologies/fintech/shacl.ttl \
     --triples industry_ontologies/fintech/triples.ttl \
     --verify-queries \
     --emulator
   ```

3. **Or set the environment variable:**
   ```bash
   export SPANNER_EMULATOR_HOST="http://localhost:9020"
   # All commands will automatically use the emulator
   rdf-spanner-translator pipeline --input evals/ontologies/ --load-companion-triples
   ```

#### `cleanup-databases` (Instance Pruning)
```bash
export SPANNER_INSTANCE="projects/<PROJECT>/instances/<INSTANCE>"

# List and purge all temporary test databases (rdf2lpg_*) from the Spanner instance:
rdf-spanner-translator cleanup-databases --instance $SPANNER_INSTANCE

# Or clean up databases on the local emulator:
rdf-spanner-translator cleanup-databases --emulator
```