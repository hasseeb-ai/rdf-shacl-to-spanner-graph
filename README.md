# rdf-shacl-to-spanner-graph

A **Antigravity CLI plugin** and standalone CLI tool that translates RDF/OWL ontologies (in Turtle `.ttl` syntax) and SHACL shapes into Google Cloud Spanner schemas (Relational SQL DDL and Logical Property Graph DDL) and validates their syntax using a Spanner Remote MCP server.

---

## Plugin Installation (Antigravity CLI)

To install this as a native plugin in your local **Antigravity CLI** installation:

1. Clone this repository and navigate to the directory:
   ```bash
   git clone <repo-url> rdf-shacl-to-spanner-graph
   cd rdf-shacl-to-spanner-graph
   ```

2. Set up a virtual environment and install the dependencies:
   ```bash
   python3 -m venv .venv
   source .venv/bin/activate
   pip install -r requirements.txt
   ```

3. Install the plugin using the `agy` CLI:
   ```bash
   agy plugin install .
   ```

4. Restart your `agy` session. The plugin will automatically configure:
   - **Native Translation Skill**: The translation skill ([`skills/owl-to-spanner-property-graph-translator/SKILL.md`](file:///Users/hasseeb/rdf-shacl-to-spanner-graph/skills/owl-to-spanner-property-graph-translator/SKILL.md)) teaches the model ontology-to-Spanner mapping rules, inheritance flattening, and property graph DDL constraints dynamically.
   - **Native Semantic Validation Skill**: The validation skill ([`skills/spanner-graph-semantic-validator/SKILL.md`](file:///Users/hasseeb/rdf-shacl-to-spanner-graph/skills/spanner-graph-semantic-validator/SKILL.md)) audits generated schemas across 7 semantic dimensions and generates executive one-pager scorecards.
   - **Native Query Verification Skill**: The query verification skill ([`skills/spanner-graph-query-verifier/SKILL.md`](file:///Users/hasseeb/rdf-shacl-to-spanner-graph/skills/spanner-graph-query-verifier/SKILL.md)) synthesizes coherent test data (SQL `INSERT`s) and 4 GQL query archetypes.
   - **Custom Tools**: Registers `translate_rdf_to_spanner_graph_ddl` and `validate_spanner_graph_ddl` as tools available to the model via the MCP server.

---

## Authentication & Configuration

The plugin and standalone CLI require access to the Gemini API. You can configure authentication using one of two methods:

### 1. Google AI Studio (API Key)
```bash
export GEMINI_API_KEY="your-api-key-here"
```

### 2. Vertex AI (Google Cloud ADC)
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

The CLI supports five primary invocation patterns:

#### Pattern 1: Pure Translation (Offline)
Translates your RDF/OWL Turtle ontology (and optional SHACL shapes) directly to Spanner DDL without running syntax validation.
```bash
# A. Translate ontology only:
rdf-spanner-translator translate \
  --input examples/fintech/fintech.ttl \
  --output output/schema.sql

# B. Translate ontology guided by SHACL shapes:
rdf-spanner-translator translate \
  --input examples/fintech/fintech.ttl \
  --shacl examples/fintech/shacl.ttl \
  --output output/schema.sql
```

#### Pattern 2: DDL Syntactic Validation (Spanner Remote MCP)
Validates the syntax of an existing Spanner DDL SQL file against the official Cloud Spanner MCP server.

```bash
# Set your target database path
export SPANNER_DATABASE="projects/<PROJECT_ID>/instances/<INSTANCE_ID>/databases/<DATABASE_ID>"

# A. Validate by updating schema on an existing database:
rdf-spanner-translator validate \
  --ddl output/schema.sql \
  --mcp-tool "update_database_schema"

# B. Validate by simulating creation of a new database:
rdf-spanner-translator validate \
  --ddl output/schema.sql \
  --mcp-tool "create_database"
```

#### Pattern 3: Semantic Validation Audit (Validation Skill)
Audits a generated schema against the source OWL ontology and SHACL shapes, producing an executive **One-Pager Semantic Validation Report & Scorecard** (`.md`) with renaming matrices, inheritance breakdowns, and visual Mermaid diagrams.

```bash
rdf-spanner-translator validate-semantic \
  --input tests/ontologies/01_simple_inheritance.ttl \
  --ddl output/01_simple_inheritance_schema.sql \
  --output output/01_simple_inheritance_validation_report.md
```

#### Pattern 4: Dynamic Data Ingestion & GQL Query Verification (Query Verifier Skill)
Synthesizes coherent mock relational data (SQL `INSERT`s) and executes 4 representative GQL queries live on Spanner to verify multi-label polymorphism, multi-hop traversal, and property filtering.

```bash
rdf-spanner-translator test-queries \
  --input tests/ontologies/01_simple_inheritance.ttl \
  --ddl output/01_simple_inheritance_schema.sql \
  --database $SPANNER_DATABASE \
  --output output/01_simple_inheritance_query_report.md
```

#### Pattern 5: End-to-End Pipeline (With Self-Correction & Semantic Reporting)
Translates the RDF/OWL ontology, executes syntactic validation on Spanner, self-corrects if compiler errors occur, and optionally generates an executive semantic validation report.

```bash
export SPANNER_DATABASE="projects/<PROJECT_ID>/instances/<INSTANCE_ID>/databases/<DATABASE_ID>"

# Translate, validate against Spanner, self-correct, and generate validation report:
rdf-spanner-translator run \
  --input examples/fintech/fintech.ttl \
  --shacl examples/fintech/shacl.ttl \
  --output output/fintech_schema.sql \
  --report output/fintech_validation_report.md \
  --mcp-tool "create_database"
```

---

## Running the Test Suite

The repository includes a test runner script [`run_tests.py`](file:///Users/hasseeb/rdf-shacl-to-spanner-graph/run_tests.py) to automate translation, syntactic DDL validation on Spanner, semantic scorecard audits, and dynamic GQL query verification across both unit tests ([`tests/ontologies/`](file:///Users/hasseeb/rdf-shacl-to-spanner-graph/tests/ontologies/)) and domain examples ([`examples/`](file:///Users/hasseeb/rdf-shacl-to-spanner-graph/examples/)).

### Execution Guide

```bash
# 1. Create and activate a python virtual environment
python3 -m venv .venv
source .venv/bin/activate

# 2. Install dependencies & translator CLI package
pip install -r requirements.txt
pip install -e . --no-build-isolation

# 3. Configure credentials & target Spanner instance
export GEMINI_API_KEY="your-gemini-api-key"
export SPANNER_INSTANCE="projects/<PROJECT_ID>/instances/<INSTANCE_ID>"

# 4. Run the suite (Outputs generated into output/unit_tests/ or output/examples/)

# A. Run all unit tests with live Spanner validation & semantic reports:
python run_tests.py --unit-only

# B. Run all unit tests including dynamic data ingestion & live GQL query execution:
python run_tests.py --unit-only --verify-queries

# C. Run all domain examples and bundle verified schemas/reports directly into examples/<domain>/:
python run_tests.py --examples-only --bundle-examples

# D. Run a specific test case:
python run_tests.py 01_simple_inheritance --verify-queries

# E. Keep created test databases on Spanner (skip auto-cleanup):
python run_tests.py 01_simple_inheritance --no-cleanup
```