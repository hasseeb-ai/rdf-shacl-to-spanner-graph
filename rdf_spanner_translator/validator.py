import httpx

def get_google_access_token() -> str | None:
    """Helper to retrieve active Google Cloud Access Token using Application Default Credentials (ADC)."""
    try:
        import google.auth
        import google.auth.transport.requests
        credentials, project = google.auth.default()
        auth_req = google.auth.transport.requests.Request()
        credentials.refresh(auth_req)
        return credentials.token
    except Exception:
        return None

def validate_ddl(
    ddl: str,
    mcp_url: str | None = "https://spanner.googleapis.com/mcp",
    mcp_tool: str | None = "update_database_schema",
    database: str | None = None,
) -> tuple[bool, str | None]:
    """Validate Spanner DDL syntax using official Google Spanner MCP server via JSON-RPC."""
    if not mcp_url:
        return False, "No Spanner MCP URL provided"
        
    try:
        token = get_google_access_token()
        headers = {
            "content-type": "application/json",
        }
        if token:
            headers["Authorization"] = f"Bearer {token}"
            
        # 1. Fetch available tools using tools/list to verify tool
        payload_list = {
            "jsonrpc": "2.0",
            "id": 1,
            "method": "tools/list",
            "params": {}
        }
        
        response = httpx.post(mcp_url, json=payload_list, headers=headers, timeout=120.0)
        if response.status_code != 200:
            return False, f"Failed to connect to Spanner MCP (Status: {response.status_code}): {response.text}"
            
        res_json = response.json()
        if "error" in res_json:
            return False, f"Spanner MCP error: {res_json['error'].get('message')}"
            
        tools = res_json.get("result", {}).get("tools", [])
        available_tool_names = [t.get("name") for t in tools]
        
        target_tool_name = mcp_tool or "update_database_schema"
        if target_tool_name not in available_tool_names:
            return False, f"Target tool '{target_tool_name}' not found on Spanner MCP. Available tools: {available_tool_names}"
            
        # 2. Setup arguments
        args = {}
        statements = [s.strip() for s in ddl.split(";") if s.strip()]
        
        if target_tool_name == "create_database":
            if not database:
                return False, "Database path is required for create_database tool (provide --database or set SPANNER_DATABASE)"
            parts = database.split("/")
            if len(parts) >= 6 and parts[0] == "projects" and parts[2] == "instances" and parts[4] == "databases":
                parent = "/".join(parts[:4])
                db_id = parts[5]
            else:
                return False, f"Invalid database path format: {database}. Expected projects/<project>/instances/<instance>/databases/<database_id>"
            
            args["parent"] = parent
            args["createStatement"] = f"CREATE DATABASE `{db_id}`"
            args["extraStatements"] = statements
        elif target_tool_name == "update_database_schema":
            if not database:
                return False, "Database path is required for update_database_schema tool (provide --database or set SPANNER_DATABASE)"
            args["database"] = database
            args["statements"] = statements
        else:
            args["ddl"] = ddl
            
        # 3. Call the tool using tools/call
        payload_call = {
            "jsonrpc": "2.0",
            "id": 2,
            "method": "tools/call",
            "params": {
                "name": target_tool_name,
                "arguments": args
            }
        }
        
        response = httpx.post(mcp_url, json=payload_call, headers=headers, timeout=120.0)
        if response.status_code != 200:
            return False, f"Failed to execute validation tool (Status: {response.status_code}): {response.text}"
            
        res_json = response.json()
        if "error" in res_json:
            return False, f"Spanner MCP execution error: {res_json['error'].get('message')}"
            
        result = res_json.get("result", {})
        is_error = result.get("isError", False) or result.get("is_error", False)
        content = result.get("content", [])
        text_outputs = [item.get("text", "") for item in content if "text" in item]
        full_text = "\n".join(text_outputs)
        
        if is_error:
            return False, full_text or "Error executing DDL"
        else:
            return True, full_text or "DDL executed successfully"
            
    except Exception as e:
        return False, f"Google Spanner MCP execution error: {e}"

def check_database_existence(
    mcp_url: str | None = "https://spanner.googleapis.com/mcp",
    mcp_tool: str | None = None,
    database: str | None = None,
) -> tuple[bool | None, str | None]:
    """Checks if the database exists via Spanner MCP.
    
    Returns a tuple of (exists: bool | None, error_message: str | None).
    """
    if not mcp_url:
        return None, "No remote MCP URL provided for database check"
        
    if not database:
        return None, "No database path provided"
        
    try:
        token = get_google_access_token()
        headers = {
            "content-type": "application/json",
        }
        if token:
            headers["Authorization"] = f"Bearer {token}"
            
        payload = {
            "jsonrpc": "2.0",
            "id": 10,
            "method": "tools/call",
            "params": {
                "name": "get_database_ddl",
                "arguments": {
                    "database": database
                }
            }
        }
        
        response = httpx.post(mcp_url, json=payload, headers=headers, timeout=10.0)
        if response.status_code != 200:
            return None, f"Failed to connect to Spanner MCP (Status: {response.status_code})"
            
        res_json = response.json()
        if "error" in res_json:
            msg = res_json["error"].get("message", "").lower()
            if "not found" in msg or "not_found" in msg or "database not found" in msg:
                return False, None
            else:
                return None, f"Spanner MCP error: {res_json['error'].get('message')}"
                
        # Check Tool execution error
        result = res_json.get("result", {})
        is_error = result.get("isError", False) or result.get("is_error", False)
        if is_error:
            content = result.get("content", [])
            text_outputs = [item.get("text", "") for item in content if "text" in item]
            full_text = "\n".join(text_outputs).lower()
            if "not found" in full_text or "not_found" in full_text:
                return False, None
            return None, f"Spanner MCP tool error: {full_text}"
            
        # If it returned a successful JSON-RPC result without error, the database exists
        return True, None
        
    except Exception as e:
        return None, f"Connection error: {e}"
