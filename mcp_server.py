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
from rdf_spanner_translator.translator import translate_ontology
from rdf_spanner_translator.validator import validate_ddl

# Initialize the MCP server instance
server = MCPServer("rdf-shacl-to-spanner-graph")

@server.tool(
    name="translate_rdf_to_spanner_graph_ddl",
    description="Translates RDF/OWL ontology in Turtle (.ttl) format to Google Cloud Spanner Relational + Property Graph DDL."
)
async def translate_rdf_to_spanner_graph_ddl(ttl_content: str) -> str:
    """Translates RDF/OWL ontology in Turtle syntax to Cloud Spanner Graph DDL.
    
    Args:
        ttl_content: The full content of the Turtle (.ttl) file.
    """
    try:
        # Call the core Gemini translation logic
        ddl = translate_ontology(ttl_content)
        return ddl
    except Exception as e:
        # Raising an exception here tells the MCP server to return is_error=True
        # and exposes the exception message to the model.
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
        # Fallback to extension settings/env vars if parameters are not provided
        url = mcp_url or os.environ.get("SPANNER_REMOTE_MCP_URL") or "https://spanner.googleapis.com/mcp"
        tool = mcp_tool or os.environ.get("SPANNER_MCP_TOOL_NAME") or "update_database_schema"
        db = database or os.environ.get("SPANNER_DATABASE")
        
        # Call the validation harness
        success, msg = validate_ddl(ddl, url, tool, db)
        if success:
            return f"DDL validation successful: {msg}"
        else:
            raise ValueError(f"DDL validation failed: {msg}")
    except Exception as e:
        raise ValueError(f"Validation execution failed: {e}")

async def main():
    # Run the MCP server over standard input/output (stdio transport)
    await server.run_stdio_async()

if __name__ == "__main__":
    asyncio.run(main())
