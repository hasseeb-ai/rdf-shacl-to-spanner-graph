import asyncio
import shlex
from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client
from mcp.client.sse import sse_client

async def run_mcp_validation(
    ddl: str,
    mcp_url: str | None = None,
    mcp_cmd: str | None = None,
    mcp_tool: str | None = None,
) -> tuple[bool, str | None]:
    """Establishes connection to MCP server, finds DDL tool, and executes it.
    
    Returns a tuple of (success: bool, message: str | None).
    """
    if mcp_url:
        transport_ctx = sse_client(mcp_url)
    elif mcp_cmd:
        parts = shlex.split(mcp_cmd)
        server_params = StdioServerParameters(
            command=parts[0],
            args=parts[1:],
            env=None
        )
        transport_ctx = stdio_client(server_params)
    else:
        return False, "No MCP server transport specified (provide --mcp-url or --mcp-cmd)"
        
    try:
        async with transport_ctx as (read_stream, write_stream):
            async with ClientSession(read_stream, write_stream) as session:
                await session.initialize()
                
                # Fetch available tools
                tools_response = await session.list_tools()
                tools = getattr(tools_response, 'tools', []) or []
                
                if not tools:
                    return False, "No tools exposed by the MCP server"
                
                target_tool = None
                if mcp_tool:
                    for t in tools:
                        if t.name == mcp_tool:
                            target_tool = t
                            break
                    if not target_tool:
                        return False, f"Specified tool '{mcp_tool}' not found on server"
                else:
                    # Dynamically discover DDL execution tools
                    # Prefer tools with 'ddl' in name
                    ddl_tools = [t for t in tools if 'ddl' in t.name.lower()]
                    if ddl_tools:
                        target_tool = ddl_tools[0]
                    else:
                        # Fallback to execute/run/query tools
                        fallback_tools = [t for t in tools if any(k in t.name.lower() for k in ['execute', 'run', 'query'])]
                        if fallback_tools:
                            target_tool = fallback_tools[0]
                            
                if not target_tool:
                    tool_names = [t.name for t in tools]
                    return False, f"Could not automatically discover DDL execution tool. Available tools: {tool_names}"
                
                # Inspect schema to map argument names
                input_schema = getattr(target_tool, 'input_schema', None) or getattr(target_tool, 'inputSchema', None) or {}
                properties = input_schema.get("properties", {})
                
                args = {}
                statements = [s.strip() for s in ddl.split(";") if s.strip()]
                
                for key in properties.keys():
                    key_lower = key.lower()
                    prop_type = properties[key].get("type")
                    
                    if "statement" in key_lower and prop_type == "array":
                        args[key] = statements
                    elif prop_type == "array" and "ddl" in key_lower:
                        args[key] = statements
                    elif any(word in key_lower for word in ["ddl", "sql", "query"]):
                        args[key] = ddl
                        
                # If args still empty, map to first parameter
                if not args and properties:
                    first_key = list(properties.keys())[0]
                    if properties[first_key].get("type") == "array":
                        args[first_key] = statements
                    else:
                        args[first_key] = ddl
                
                # Call the tool
                result = await session.call_tool(target_tool.name, arguments=args)
                
                # Parse response
                is_error = getattr(result, 'is_error', None) or getattr(result, 'isError', None) or False
                content = getattr(result, 'content', [])
                
                text_outputs = []
                for item in content:
                    if hasattr(item, 'text'):
                        text_outputs.append(item.text)
                    elif isinstance(item, dict) and 'text' in item:
                        text_outputs.append(item['text'])
                        
                full_text = "\n".join(text_outputs)
                
                # If the execution returned error or contains typical Spanner compilation errors,
                # mark it as failure.
                if is_error:
                    return False, full_text or "Error executing DDL"
                else:
                    return True, full_text or "DDL executed successfully"
                    
    except Exception as e:
        return False, f"MCP communication error: {e}"

def validate_ddl(
    ddl: str,
    mcp_url: str | None = None,
    mcp_cmd: str | None = None,
    mcp_tool: str | None = None,
) -> tuple[bool, str | None]:
    """Synchronous entry point to run the async MCP validation."""
    return asyncio.run(run_mcp_validation(ddl, mcp_url, mcp_cmd, mcp_tool))
