"""Model Context Protocol (MCP) Server for the Antigravity CLI Plugin.

This file acts as the local MCP server launched by the Antigravity CLI. It registers
and exposes custom tools to the underlying AI model, enabling it to perform
automated RDF translation and Spanner DDL validation.
"""

import asyncio
import os
import sys

# Ensure local package folder is in python path to resolve imports correctly
# when spawned by the Antigravity CLI from another working directory.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from mcp.server.mcpserver import MCPServer
from rdf_spanner_translator.translator import translate_ontology, audit_spanner_schema
from rdf_spanner_translator.validator import validate_ddl
from rdf_spanner_translator.query_verifier import run_query_verification

# Initialize the MCP server instance
server = MCPServer("rdf-shacl-to-spanner-graph")

@server.tool(
    name="translate_rdf_to_spanner_graph_ddl",
    description="Translates RDF/OWL ontology in Turtle (.ttl) format to Google Cloud Spanner Relational + Property Graph DDL."
)
async def translate_rdf_to_spanner_graph_ddl(ttl_content: str, shacl_content: str | None = None) -> str:
    """Translates RDF/OWL ontology in Turtle syntax to Cloud Spanner Graph DDL.
    
    Args:
        ttl_content: The full content of the Turtle (.ttl) file.
        shacl_content: Optional SHACL shapes content for constraint mapping.
    """
    try:
        ddl = translate_ontology(ttl_content, shacl_content=shacl_content)
        return ddl
    except Exception as e:
        raise ValueError(f"Translation failed: {e}")

@server.tool(
    name="validate_spanner_graph_ddl",
    description="Validates Google Cloud Spanner DDL statements by executing them against a database/emulator via the official Spanner MCP server."
)
async def validate_spanner_graph_ddl(
    ddl: str,
    mcp_url: str | None = None,
    mcp_tool: str | None = None,
    database: str | None = None
) -> str:
    """Validates Spanner DDL syntax using the official Spanner MCP server.
    
    Args:
        ddl: The DDL statements to validate.
        mcp_url: URL of the Remote Spanner MCP Server.
        mcp_tool: Explicit name of the tool to call (e.g. update_database_schema).
        database: Full Spanner database resource path.
    """
    try:
        url = mcp_url or os.environ.get("SPANNER_REMOTE_MCP_URL") or "https://spanner.googleapis.com/mcp"
        tool = mcp_tool or os.environ.get("SPANNER_MCP_TOOL_NAME") or "update_database_schema"
        db = database or os.environ.get("SPANNER_DATABASE")
        
        success, msg = validate_ddl(ddl, url, tool, db)
        if success:
            return f"DDL validation successful: {msg}"
        else:
            raise ValueError(f"DDL validation failed: {msg}")
    except Exception as e:
        raise ValueError(f"Validation execution failed: {e}")

@server.tool(
    name="validate_spanner_graph_semantics",
    description="Performs rigorous semantic validation of generated Spanner DDL against source OWL/SHACL, producing an executive scorecard report."
)
async def validate_spanner_graph_semantics(
    ttl_content: str,
    ddl_content: str,
    shacl_content: str | None = None
) -> str:
    """Performs semantic audit of Spanner DDL against source ontology using the Validation Skill.
    
    Args:
        ttl_content: Source Turtle ontology content.
        ddl_content: Generated Spanner DDL statements.
        shacl_content: Optional companion SHACL shapes content.
    """
    try:
        report = audit_spanner_schema(
            ttl_content=ttl_content,
            ddl_content=ddl_content,
            shacl_content=shacl_content
        )
        return report
    except Exception as e:
        raise ValueError(f"Semantic validation failed: {e}")

@server.tool(
    name="verify_spanner_graph_queries",
    description="Synthesizes coherent relational mock data, ingests it into Spanner, executes 4 GQL queries live, and generates an executive query report."
)
async def verify_spanner_graph_queries(
    ttl_path: str,
    ddl_path: str,
    database: str,
    shacl_path: str | None = None,
    mcp_url: str | None = None
) -> str:
    """Executes dynamic data ingestion and GQL query verification against a Cloud Spanner database.
    
    Args:
        ttl_path: Path to source Turtle (.ttl) file.
        ddl_path: Path to Spanner SQL DDL file.
        database: Full Spanner database resource path.
        shacl_path: Optional path to SHACL shapes file.
        mcp_url: URL of the Remote Spanner MCP Server.
    """
    try:
        url = mcp_url or os.environ.get("SPANNER_REMOTE_MCP_URL") or "https://spanner.googleapis.com/mcp"
        success, report = run_query_verification(
            ttl_path=ttl_path,
            ddl_path=ddl_path,
            database=database,
            shacl_path=shacl_path,
            mcp_url=url
        )
        return report
    except Exception as e:
        raise ValueError(f"Query verification failed: {e}")

async def main():
    # Run the MCP server over standard input/output (stdio transport)
    await server.run_stdio_async()

if __name__ == "__main__":
    asyncio.run(main())
