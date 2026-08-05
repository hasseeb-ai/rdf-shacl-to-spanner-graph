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

#### 1. Translate (AI Translation Only)
```bash
rdf-spanner-translator translate --input examples/fintech.ttl --output examples/schema.sql
```

#### 2. Validate (Syntax Verification Only)
```bash
# Via Stdio command
rdf-spanner-translator validate --ddl examples/schema.sql --mcp-cmd "python3 tests/mock_spanner_mcp.py"

# Via Server-Sent Events (SSE) URL
rdf-spanner-translator validate --ddl examples/schema.sql --mcp-url "http://localhost:8000/sse"
```

#### 3. Run (End-to-End with Self-Correction)
```bash
rdf-spanner-translator run \
  --input examples/fintech.ttl \
  --output examples/schema.sql \
  --mcp-cmd "python3 tests/mock_spanner_mcp.py"
```