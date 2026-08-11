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
   - **Native Agent Skill**: The translation skill (`skills/owl-to-spanner-property-graph-translator/SKILL.md`) is automatically loaded. This teaches the model the ontology-to-spanner mapping rules and critical Graph DDL constraints dynamically when a relevant translation task is active.
   - **Custom Tools**: Registers `translate_rdf_to_spanner_graph_ddl` (translates Turtle OWL ontologies to Spanner Graph DDL) and `validate_spanner_graph_ddl` (validates Spanner DDL syntax using a Remote Spanner MCP server) as tools available to the model via the MCP server.

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

The CLI supports three primary invocation patterns. Note that `GEMINI_API_KEY` (or Vertex AI Cloud credentials) must be set in your environment prior to running translation commands.

#### Pattern 1: Pure Translation (Offline)
Translates your RDF/OWL Turtle ontology directly to Spanner DDL without running any syntax validation.
```bash
rdf-spanner-translator translate \
  --input examples/fintech.ttl \
  --output examples/schema.sql
```

#### Pattern 2: DDL Validation Only Using Official Google Spanner MCP
Validates an existing Spanner DDL file syntax using the official Cloud Spanner MCP server.

```bash
# Set your target database path
export SPANNER_DATABASE="projects/<PROJECT_ID>/instances/<INSTANCE_ID>/databases/<DATABASE_ID>"

# Validate by updating schema on an existing DB
rdf-spanner-translator validate \
  --ddl examples/schema.sql \
  --mcp-tool "update_database_schema"
```

#### Pattern 3: End-to-End Pipeline (With Self-Correction Loop)
Translates the ontology, validates the output, and automatically corrects the SQL schema if Spanner reports compilation errors.

```bash
# Set your target database path
export SPANNER_DATABASE="projects/<PROJECT_ID>/instances/<INSTANCE_ID>/databases/<DATABASE_ID>"

# Translate, validate database creation, and self-correct
rdf-spanner-translator run \
  --input examples/fintech.ttl \
  --output examples/schema.sql \
  --mcp-tool "create_database"
```