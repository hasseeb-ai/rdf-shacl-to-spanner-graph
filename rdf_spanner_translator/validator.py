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

def call_spanner_mcp_tool(
    mcp_url: str,
    tool_name: str,
    arguments: dict,
    timeout: float = 120.0
) -> tuple[bool, str]:
    """Executes a tool on the Remote Spanner MCP server via JSON-RPC 2.0.
    
    Returns (success: bool, output_text_or_error: str).
    """
    if not mcp_url:
        return False, "No Spanner MCP URL provided"
        
    try:
        token = get_google_access_token()
        headers = {"content-type": "application/json"}
        if token:
            headers["Authorization"] = f"Bearer {token}"
            
        payload = {
            "jsonrpc": "2.0",
            "id": 1,
            "method": "tools/call",
            "params": {
                "name": tool_name,
                "arguments": arguments
            }
        }
        
        response = httpx.post(mcp_url, json=payload, headers=headers, timeout=timeout)
        if response.status_code != 200:
            return False, f"Failed to connect to Spanner MCP (Status: {response.status_code}): {response.text}"
            
        res_json = response.json()
        if "error" in res_json:
            return False, f"Spanner MCP error: {res_json['error'].get('message', 'Unknown error')}"
            
        result = res_json.get("result", {})
        is_error = result.get("isError", False) or result.get("is_error", False)
        content = result.get("content", [])
        text_outputs = [item.get("text", "") for item in content if "text" in item]
        full_text = "\n".join(text_outputs)
        
        if is_error:
            return False, full_text or "Error executing MCP tool"
            
        return True, full_text or "Tool executed successfully"
        
    except Exception as e:
        return False, f"Google Spanner MCP execution error: {e}"


def validate_ddl(
    ddl: str,
    mcp_url: str | None = "https://spanner.googleapis.com/mcp",
    mcp_tool: str | None = "update_database_schema",
    database: str | None = None,
) -> tuple[bool, str | None]:
    """Validate Spanner DDL syntax using official Google Spanner MCP server via JSON-RPC."""
    if not mcp_url:
        return False, "No Spanner MCP URL provided"
        
    args = {}
    statements = [s.strip() for s in ddl.split(";") if s.strip()]
    target_tool_name = mcp_tool or "update_database_schema"
    
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
        
    return call_spanner_mcp_tool(mcp_url, target_tool_name, args, timeout=120.0)


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
        
    success, msg = call_spanner_mcp_tool(
        mcp_url=mcp_url,
        tool_name="get_database_ddl",
        arguments={"database": database},
        timeout=10.0
    )
    
    if success:
        return True, None
        
    msg_lower = msg.lower()
    if "not found" in msg_lower or "not_found" in msg_lower or "database not found" in msg_lower:
        return False, None
        
    return None, msg


def drop_spanner_database(project_id: str, instance_id: str, db_id: str) -> tuple[bool, str]:
    """Drops a Cloud Spanner database using Google Cloud Spanner REST API, with gcloud fallback."""
    token = get_google_access_token()
    if token:
        url = f"https://spanner.googleapis.com/v1/projects/{project_id}/instances/{instance_id}/databases/{db_id}"
        headers = {
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json"
        }
        try:
            resp = httpx.delete(url, headers=headers, timeout=30.0)
            if resp.status_code in (200, 204):
                return True, "Database deleted successfully"
            elif resp.status_code == 404:
                return True, "Database already deleted or not found"
        except Exception:
            pass

    # Fallback to gcloud CLI
    import subprocess
    cmd = [
        "gcloud", "spanner", "databases", "delete", db_id,
        "--instance", instance_id,
        "--project", project_id,
        "--quiet"
    ]
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode == 0:
        return True, "Database deleted successfully via gcloud"
    return False, (res.stderr or res.stdout or "Failed to delete database via gcloud").strip()


def list_spanner_databases(project_id: str, instance_id: str) -> tuple[list[str], str | None]:
    """Lists all database IDs in a Cloud Spanner instance using REST API / gcloud."""
    token = get_google_access_token()
    if token:
        url = f"https://spanner.googleapis.com/v1/projects/{project_id}/instances/{instance_id}/databases"
        headers = {"Authorization": f"Bearer {token}"}
        try:
            resp = httpx.get(url, headers=headers, timeout=30.0)
            if resp.status_code == 200:
                data = resp.json()
                databases = data.get("databases", [])
                db_ids = [db["name"].split("/")[-1] for db in databases if "name" in db]
                return db_ids, None
        except Exception as ex:
            pass

    # Fallback to gcloud CLI
    import subprocess
    import json
    cmd = [
        "gcloud", "spanner", "databases", "list",
        "--instance", instance_id,
        "--project", project_id,
        "--format=json"
    ]
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode == 0:
        try:
            data = json.loads(res.stdout)
            db_ids = [db["name"].split("/")[-1] for db in data if "name" in db]
            return db_ids, None
        except Exception as ex:
            pass
    return [], (res.stderr or "Failed to list databases").strip()

