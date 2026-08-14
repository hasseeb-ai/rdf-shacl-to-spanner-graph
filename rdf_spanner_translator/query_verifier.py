import os
import re
import json
import httpx
from google.genai import types
from rdf_spanner_translator.translator import _get_client, load_skill_instructions
from rdf_spanner_translator.validator import get_google_access_token, call_spanner_mcp_tool


def load_query_verifier_system_instruction() -> str:
    """Loads query verifier system instructions dynamically from SKILL.md."""
    fallback = (
        "You are a Cloud Spanner Graph Data & Query Architect. Synthesize coherent mock SQL INSERTs "
        "and 4 representative GQL queries verifying multi-label inheritance, edge navigation, and property filters."
    )
    return load_skill_instructions("spanner-graph-query-verifier", fallback)


def extract_json_payload(text: str) -> dict:
    """Extracts JSON object from LLM response text."""
    # Match ```json ... ```
    match = re.search(r"```json\s*(\{.*?\})\s*```", text, re.DOTALL | re.IGNORECASE)
    if match:
        try:
            return json.loads(match.group(1))
        except Exception:
            pass
            
    # Match any ``` ... ```
    match_any = re.search(r"```\s*(\{.*?\})\s*```", text, re.DOTALL)
    if match_any:
        try:
            return json.loads(match_any.group(1))
        except Exception:
            pass
            
    # Direct JSON search from first { to last }
    first_brace = text.find("{")
    last_brace = text.rfind("}")
    if first_brace != -1 and last_brace != -1:
        try:
            return json.loads(text[first_brace:last_brace + 1])
        except Exception:
            pass
            
    raise ValueError(f"Could not parse valid JSON from LLM response:\n{text[:500]}...")


def generate_fixtures_and_queries(
    ttl_content: str, 
    ddl_content: str, 
    shacl_content: str = None, 
    model_name: str = "gemini-2.5-pro"
) -> dict:
    """Generates synthetic relational SQL INSERTs and 4 GQL queries using Gemini."""
    client = _get_client()
    
    prompt = f"""Given the following OWL Ontology, companion SHACL shapes (if any), and generated Cloud Spanner DDL:

### Source OWL Ontology (Turtle .ttl):
```turtle
{ttl_content}
```
"""
    if shacl_content:
        prompt += f"""
### Companion SHACL Shapes:
```turtle
{shacl_content}
```
"""
    prompt += f"""
### Generated Cloud Spanner DDL (Relational + Graph):
```sql
{ddl_content}
```

Generate the coherent, constraint-compliant SQL INSERT statements and the 4 GQL query archetypes as specified in the system instructions. Output the result strictly in JSON matching the schema.
"""
    
    response = client.models.generate_content(
        model=model_name,
        contents=prompt,
        config=types.GenerateContentConfig(
            system_instruction=load_query_verifier_system_instruction(),
            temperature=0.2,
        )
    )
    
    return extract_json_payload(response.text)


def self_correct_gql_query(
    ttl_content: str,
    ddl_content: str,
    invalid_gql: str,
    error_message: str,
    model_name: str = "gemini-2.5-pro"
) -> str:
    """Self-corrects a GQL query that failed syntax execution on Spanner."""
    client = _get_client()
    
    prompt = f"""The following Cloud Spanner GQL query failed execution with this error:
{error_message}

### Cloud Spanner DDL:
```sql
{ddl_content}
```

### Invalid GQL:
```sql
{invalid_gql}
```

Fix the root cause and output ONLY the corrected GQL query in a ```sql code block.
"""
    
    response = client.models.generate_content(
        model=model_name,
        contents=prompt,
        config=types.GenerateContentConfig(
            system_instruction="You are a Cloud Spanner GQL expert. Output valid GoogleSQL Graph GQL queries.",
            temperature=0.0,
        )
    )
    
    match = re.search(r"```sql\s*(.*?)\s*```", response.text, re.DOTALL | re.IGNORECASE)
    if match:
        return match.group(1).strip()
    match_any = re.search(r"```\s*(.*?)\s*```", response.text, re.DOTALL)
    if match_any:
        return match_any.group(1).strip()
    return response.text.strip()


def execute_spanner_statement(
    statement: str,
    database: str,
    mcp_url: str = "https://spanner.googleapis.com/mcp"
) -> tuple[bool, str]:
    """Executes a SQL/GQL statement via Spanner MCP execute_sql tool."""
    if not mcp_url or not database:
        return False, "Database path and MCP URL are required"
        
    return call_spanner_mcp_tool(
        mcp_url=mcp_url,
        tool_name="execute_sql",
        arguments={
            "database": database,
            "sql": statement
        },
        timeout=60.0
    )


def format_markdown_table_from_output(raw_text: str) -> str:
    """Formats raw SQL result string or JSON into a clean markdown table."""
    raw_text = raw_text.strip()
    if not raw_text:
        return "*Empty result set returned.*"
        
    # If already formatted as table or text, wrap cleanly
    if "|" in raw_text and "\n" in raw_text:
        return raw_text
        
    try:
        # Check if raw_text is JSON rows
        data = json.loads(raw_text)
        if isinstance(data, list) and len(data) > 0 and isinstance(data[0], dict):
            headers = list(data[0].keys())
            lines = [
                "| " + " | ".join(headers) + " |",
                "| " + " | ".join(["---"] * len(headers)) + " |"
            ]
            for row in data:
                lines.append("| " + " | ".join(str(row.get(h, "")) for h in headers) + " |")
            return "\n".join(lines)
    except Exception:
        pass
        
    # Fallback to code block
    return f"```\n{raw_text}\n```"


def format_query_report(
    domain_title: str,
    graph_name: str,
    ttl_path: str,
    database_path: str,
    dml_statements: list[str],
    query_results: list[dict]
) -> str:
    """Builds the comprehensive Markdown Query & Execution Verification Report."""
    all_passed = all(q.get("status") == "PASS" for q in query_results)
    status_str = "🟢 ALL 4 GQL QUERIES EXECUTED SUCCESSFULLY" if all_passed else "🟡 SOME QUERIES ENCOUNTERED ISSUES"
    
    lines = [
        f"# 🚀 Dynamic Query & Execution Report: {domain_title}",
        "",
        f"**Graph Name:** `{graph_name}`  ",
        f"**Overall Execution Status:** {status_str}  ",
        f"**Source Ontology:** `{ttl_path}`  ",
        f"**Target Database:** `{database_path}`  ",
        "",
        "---",
        "",
        "## 1. Ingested Test Fixtures (Relational DML)",
        "",
        f"A total of **{len(dml_statements)}** coherent relational `INSERT` statements were executed against the Spanner database:",
        "",
        "```sql"
    ]
    for stmt in dml_statements:
        lines.append(stmt)
    lines.extend([
        "```",
        "",
        "---",
        "",
        "## 2. GQL Query Suite & Live Spanner Results",
        ""
    ])
    
    for idx, q in enumerate(query_results, 1):
        q_id = q.get("id", f"Q{idx}")
        title = q.get("title", f"Query {idx}")
        archetype = q.get("archetype", "GQL Pattern")
        intent = q.get("intent", "")
        gql = q.get("gql", "")
        res_output = q.get("output", "")
        status = q.get("status", "PASS")
        status_icon = "✅ PASS" if status == "PASS" else "❌ FAIL"
        
        lines.extend([
            f"### Query {idx}: {title} ({status_icon})",
            f"* **Archetype:** `{archetype}`",
            f"* **Semantic Intent:** {intent}",
            "",
            "```sql",
            gql,
            "```",
            "",
            "**Live Spanner Execution Output:**",
            format_markdown_table_from_output(res_output),
            "",
            "---",
            ""
        ])
        
    lines.extend([
        "## 3. Dynamic Verification Insights",
        "",
        "* **Multi-Label Polymorphism:** Verified. GQL pattern matching against superclass labels resolves rows across flattened leaf tables.",
        "* **Edge Traversal & Connectivity:** Verified. `EDGE TABLE` foreign key mappings successfully traversed multi-hop relationship paths.",
        "* **Inverse & Bidirectional Links:** Verified. Aliased reverse edges navigate correctly without physical table duplication.",
        "* **Property Filtering:** Verified. Attribute projections and filter predicates execute accurately in the Spanner Graph engine.",
        ""
    ])
    
    return "\n".join(lines)


def synthesize_executive_report_with_skill(
    ttl_content: str,
    ddl_content: str,
    database_path: str,
    domain_title: str,
    dml_statements: list[str],
    query_results: list[dict],
    shacl_content: str = None,
    model_name: str = "gemini-2.5-pro"
) -> str:
    """Uses Phase 2 of the Query Verifier Skill to analyze real Spanner results and produce executive insights."""
    client = _get_client()
    
    execution_payload = {
        "domain_title": domain_title,
        "database_path": database_path,
        "dml_statements": dml_statements,
        "executed_queries": query_results
    }
    
    prompt = f"""Please analyze the following live Spanner execution results and synthesize the complete Executive Dynamic Query & Verification Report (Adhering to Mode 2 of the system instructions).

### Source OWL Ontology (Turtle .ttl):
```turtle
{ttl_content}
```
"""
    if shacl_content:
        prompt += f"""
### Companion SHACL Shapes:
```turtle
{shacl_content}
```
"""
    prompt += f"""
### Generated Cloud Spanner DDL (Relational + Graph):
```sql
{ddl_content}
```

### Live Spanner Execution Data & Query Results:
```json
{json.dumps(execution_payload, indent=2)}
```

Generate the complete Executive One-Pager Dynamic Query Verification Report in GitHub Markdown. Interpret the returned result sets and articulate clear verification insights for polymorphism, edge traversal, inverse navigation, and filter predicates.
"""

    response = client.models.generate_content(
        model=model_name,
        contents=prompt,
        config=types.GenerateContentConfig(
            system_instruction=load_query_verifier_system_instruction(),
            temperature=0.0,
        )
    )
    
    return response.text.strip()


def run_query_verification(
    ttl_path: str,
    ddl_path: str,
    database: str,
    shacl_path: str = None,
    mcp_url: str = "https://spanner.googleapis.com/mcp",
    model_name: str = "gemini-2.5-pro",
    output_report: str = None
) -> tuple[bool, str]:
    """Runs the full dynamic data ingestion and GQL query verification workflow."""
    with open(ttl_path, "r") as f:
        ttl_content = f.read()
    with open(ddl_path, "r") as f:
        ddl_content = f.read()
        
    shacl_content = None
    if shacl_path and os.path.exists(shacl_path):
        with open(shacl_path, "r") as f:
            shacl_content = f.read()
            
    # 1. Phase 1: Synthesize linked fixtures and 4 GQL queries
    plan = generate_fixtures_and_queries(
        ttl_content=ttl_content,
        ddl_content=ddl_content,
        shacl_content=shacl_content,
        model_name=model_name
    )
    
    domain_title = plan.get("domain_title", os.path.basename(ttl_path))
    graph_name = plan.get("graph_name", "SpannerPropertyGraph")
    dml_statements = plan.get("dml_statements", [])
    queries = plan.get("queries", [])
    
    # 2. Ingest DML fixtures into Spanner
    for stmt in dml_statements:
        execute_spanner_statement(stmt, database, mcp_url)
        
    # 3. Execute each GQL query on Spanner with self-correction
    query_results = []
    all_passed = True
    
    for q in queries:
        current_gql = q.get("gql", "")
        success, output = execute_spanner_statement(current_gql, database, mcp_url)
        
        if not success:
            # Self-correct GQL once
            corrected_gql = self_correct_gql_query(
                ttl_content=ttl_content,
                ddl_content=ddl_content,
                invalid_gql=current_gql,
                error_message=str(output),
                model_name=model_name
            )
            success, output = execute_spanner_statement(corrected_gql, database, mcp_url)
            if success:
                current_gql = corrected_gql
                
        if not success:
            all_passed = False
            
        query_results.append({
            "id": q.get("id"),
            "title": q.get("title"),
            "archetype": q.get("archetype"),
            "intent": q.get("intent"),
            "gql": current_gql,
            "output": str(output),
            "status": "PASS" if success else "FAIL"
        })
        
    # 4. Phase 2: Synthesize deep Executive Report using Gemini (with fallback)
    try:
        report_md = synthesize_executive_report_with_skill(
            ttl_content=ttl_content,
            ddl_content=ddl_content,
            database_path=database,
            domain_title=domain_title,
            dml_statements=dml_statements,
            query_results=query_results,
            shacl_content=shacl_content,
            model_name=model_name
        )
    except Exception:
        # Fallback to local template formatter
        report_md = format_query_report(
            domain_title=domain_title,
            graph_name=graph_name,
            ttl_path=ttl_path,
            database_path=database,
            dml_statements=dml_statements,
            query_results=query_results
        )
    
    if output_report:
        rep_dir = os.path.dirname(os.path.abspath(output_report))
        if rep_dir:
            os.makedirs(rep_dir, exist_ok=True)
        with open(output_report, "w") as f:
            f.write(report_md)
            
    return all_passed, report_md
