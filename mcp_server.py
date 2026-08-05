import asyncio
import os
import sys

# Ensure local package folder is in python path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from mcp.server.mcpserver import MCPServer
from rdf_spanner_translator.translator import translate_ontology
from rdf_spanner_translator.validator import validate_ddl

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
        ddl = translate_ontology(ttl_content)
        return ddl
    except Exception as e:
        raise ValueError(f"Translation failed: {e}")

@server.tool(
    name="validate_spanner_graph_ddl",
    description="Validates Google Cloud Spanner DDL statements by executing them against a database/emulator via a Remote Spanner MCP server."
)
async def validate_spanner_graph_ddl(
    ddl: str,
    mcp_url: str | None = None,
    mcp_cmd: str | None = None,
    mcp_tool: str | None = None
) -> str:
    """Validates Spanner DDL syntax using a Remote Spanner MCP server.
    
    Args:
        ddl: The DDL statements to validate.
        mcp_url: SSE URL of the Remote Spanner MCP Server.
        mcp_cmd: Stdio command to spawn the Remote Spanner MCP Server.
        mcp_tool: Explicit name of the tool to call.
    """
    try:
        success, msg = validate_ddl(ddl, mcp_url, mcp_cmd, mcp_tool)
        if success:
            return f"DDL validation successful: {msg}"
        else:
            raise ValueError(f"DDL validation failed: {msg}")
    except Exception as e:
        raise ValueError(f"Validation execution failed: {e}")

async def main():
    await server.run_stdio_async()

if __name__ == "__main__":
    asyncio.run(main())
