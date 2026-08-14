# rdf-shacl-to-spanner-graph

A **Antigravity CLI plugin** and standalone CLI tool that translates RDF/OWL ontologies (in Turtle `.ttl` syntax) and SHACL shapes into Google Cloud Spanner schemas (Relational SQL DDL and Logical Property Graph DDL) and validates their syntax using a Spanner Remote MCP server.

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
  - **Native Translation Skill**: The translation skill ([`skills/owl-to-spanner-property-graph-translator/SKILL.md`](file:///Users/hasseeb/rdf-shacl-to-spanner-graph/skills/owl-to-spanner-property-graph-translator/SKILL.md)) teaches the model ontology-to-Spanner mapping rules, inheritance flattening, and property graph DDL constraints dynamically.
  - **Native Semantic Validation Skill**: The validation skill ([`skills/spanner-graph-semantic-validator/SKILL.md`](file:///Users/hasseeb/rdf-shacl-to-spanner-graph/skills/spanner-graph-semantic-validator/SKILL.md)) audits generated schemas across 7 semantic dimensions and generates executive one-pager scorecards.
  - **Native Query Verification Skill**: The query verification skill ([`skills/spanner-graph-query-verifier/SKILL.md`](file:///Users/hasseeb/rdf-shacl-to-spanner-graph/skills/spanner-graph-query-verifier/SKILL.md)) synthesizes coherent test data (SQL `INSERT`s) and 4 GQL query archetypes.
  - **Custom Tools**: Registers `translate_rdf_to_spanner_graph_ddl` and `validate_spanner_graph_ddl` as tools available to the model via the MCP server.

---

## Authentication & Configuration

The plugin and standalone CLI require access to the Gemini API. You can configure authentication using one of two methods:

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

The CLI is organized into **3 core commands** (`translate`, `validate`, and `pipeline`):

| Command | Operational Usage | Key Parameters & Flags | Description |
| :--- | :--- | :--- | :--- |
| **`translate`** | **Offline Translation** | `-i, --input <ont.ttl>`<br>`-s, --shacl <shacl.ttl>`<br>`-o, --output <schema.sql>`<br>`-m, --model <gemini-3.5-flash>` | Translates OWL Turtle ontologies and companion SHACL shapes into GoogleSQL & Spanner Property Graph DDL offline. |
| **`validate`** | **Syntax Compilation Check** | `-d, --ddl <schema.sql>`<br>`--syntax-only` (or `--mode syntax`)<br>`--database <db_path>`<br>`-t, --mcp-tool <tool_name>` | Validates that physical and logical DDL compiles cleanly against Cloud Spanner via the Remote Spanner MCP server. |
| | **Semantic Audit Scorecard** | `-i, --input <ont.ttl>`<br>`-d, --ddl <schema.sql>`<br>`-s, --shacl <shacl.ttl>`<br>`--semantic-only` (or `--mode semantic`)<br>`-o, --output <report.md>` | Audits generated DDL against 7 semantic dimensions (completeness, inheritance, edge connections, invariants) producing an executive scorecard. |
| | **Dynamic GQL Query Verification** | `-i, --input <ont.ttl>`<br>`-d, --ddl <schema.sql>`<br>`--database <db_path>`<br>`--queries-only` (or `--mode queries`)<br>`-o, --output <report.md>` | Synthesizes linked test fixtures (DML), ingests them into Spanner, executes 4 GQL queries live, and synthesizes an executive execution report. |
| | **Full Multi-Level Validation** | `-i, --input <ont.ttl>`<br>`-d, --ddl <schema.sql>`<br>`--database <db_path>`<br>`--mode all` (Default) | Runs all validation stages sequentially (Syntax Check $\to$ Semantic Scorecard $\to$ Dynamic GQL Queries). |
| **`pipeline`** | **Automated End-to-End** | `-i, --input <ont.ttl>`<br>`-s, --shacl <shacl.ttl>`<br>`-o, --output <schema.sql>`<br>`--database <db_path>`<br>`-r, --report <report.md>`<br>`--verify-queries` | Complete automated workflow: Translates ontology, validates syntax on Spanner, auto-corrects compiler errors (up to 3x), audits semantics, and tests queries. |

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

# Static semantic audit scorecard
rdf-spanner-translator validate \
  --input examples/fintech/fintech.ttl \
  --ddl output/examples/fintech_schema.sql \
  --output output/examples/fintech_validation_report.md \
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

# Translate, validate live on Spanner, auto-correct if needed, and generate reports:
rdf-spanner-translator pipeline \
  --input examples/fintech/fintech.ttl \
  --shacl examples/fintech/shacl.ttl \
  --output output/examples/fintech_schema.sql \
  --report output/examples/fintech_validation_report.md \
  --database $SPANNER_DATABASE \
  --verify-queries
```

---

## Running the Test Suite

The repository includes a test runner script [`run_tests.py`](file:///Users/hasseeb/rdf-shacl-to-spanner-graph/run_tests.py) to automate translation, syntactic DDL validation on Spanner, semantic scorecard audits, and dynamic GQL query verification across both unit tests ([`tests/ontologies/`](file:///Users/hasseeb/rdf-shacl-to-spanner-graph/tests/ontologies/)) and domain examples ([`examples/`](file:///Users/hasseeb/rdf-shacl-to-spanner-graph/examples/)).

### Execution Guide

```bash
# Create and activate a python virtual environment
python3 -m venv .venv
source .venv/bin/activate

# Install dependencies & translator CLI package
pip install -r requirements.txt
pip install -e . --no-build-isolation

# Configure credentials & target Spanner instance
export GEMINI_API_KEY="your-gemini-api-key"
export SPANNER_INSTANCE="projects/<PROJECT_ID>/instances/<INSTANCE_ID>"

# Run all unit tests with live Spanner validation & semantic reports:
python run_tests.py --unit-only

# Run all unit tests with dynamic data ingestion & live GQL query execution:
python run_tests.py --unit-only --verify-queries

# Run all domain examples and bundle verified schemas/reports directly into examples/<domain>/:
python run_tests.py --examples-only --bundle-examples

# Run a specific test case:
python run_tests.py 01_simple_inheritance --verify-queries

# Keep created test databases on Spanner (skip auto-cleanup):
python run_tests.py 01_simple_inheritance --no-cleanup
```