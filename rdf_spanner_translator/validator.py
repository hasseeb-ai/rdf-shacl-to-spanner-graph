import os
import httpx
from .config import (
    DEFAULT_MCP_URL,
    DEFAULT_EMULATOR_HOST,
    DEFAULT_EMULATOR_PROJECT,
    DEFAULT_EMULATOR_INSTANCE,
)

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

def _normalize_emulator_url(host: str | None) -> str:
    """Ensures emulator host has http:// prefix and default REST port (9020) if needed."""
    h = host or os.getenv("SPANNER_EMULATOR_HOST") or DEFAULT_EMULATOR_HOST or "http://localhost:9020"
    if not h.startswith("http://") and not h.startswith("https://"):
        h = f"http://{h}"
    return h.rstrip("/")

def ensure_emulator_instance(
    emulator_url: str | None = None,
    project_id: str = DEFAULT_EMULATOR_PROJECT,
    instance_id: str = DEFAULT_EMULATOR_INSTANCE,
    timeout: float = 10.0
) -> tuple[bool, str]:
    """Ensures the test instance exists in the local Cloud Spanner Emulator."""
    base_url = _normalize_emulator_url(emulator_url)
    inst_url = f"{base_url}/v1/projects/{project_id}/instances/{instance_id}"
    
    try:
        r = httpx.get(inst_url, timeout=timeout)
        if r.status_code == 200:
            return True, "Instance exists"
    except Exception as e:
        return False, f"Cannot connect to Spanner Emulator at {base_url}. Ensure it is running (e.g. docker run -p 9020:9020 gcr.io/cloud-spanner-emulator/emulator): {e}"
        
    create_url = f"{base_url}/v1/projects/{project_id}/instances"
    payload = {
        "instanceId": instance_id,
        "instance": {
            "name": f"projects/{project_id}/instances/{instance_id}",
            "config": f"projects/{project_id}/instanceConfigs/emulator-config",
            "displayName": "Emulator Test Instance",
            "nodeCount": 1
        }
    }
    try:
        r = httpx.post(create_url, json=payload, timeout=timeout)
        if r.status_code in (200, 201):
            return True, "Instance created successfully"
        return False, f"Failed to create emulator instance: {r.text}"
    except Exception as e:
        return False, f"Failed to create emulator instance at {base_url}: {e}"

def validate_ddl_on_emulator(
    ddl: str,
    emulator_url: str | None = None,
    database_path: str | None = None,
    timeout: float = 60.0
) -> tuple[bool, str]:
    """Validates DDL syntax by executing on local Cloud Spanner Emulator via REST API."""
    base_url = _normalize_emulator_url(emulator_url)
    project_id = DEFAULT_EMULATOR_PROJECT
    instance_id = DEFAULT_EMULATOR_INSTANCE
    db_id = "test_db"
    
    if database_path:
        parts = database_path.split("/")
        if len(parts) >= 6 and parts[0] == "projects" and parts[2] == "instances" and parts[4] == "databases":
            project_id = parts[1]
            instance_id = parts[3]
            db_id = parts[5]
        elif "/" not in database_path:
            db_id = database_path
            
    inst_ok, inst_msg = ensure_emulator_instance(base_url, project_id, instance_id, timeout=10.0)
    if not inst_ok:
        return False, inst_msg
        
    statements = [s.strip() for s in ddl.split(";") if s.strip()]
    db_url = f"{base_url}/v1/projects/{project_id}/instances/{instance_id}/databases"
    
    payload = {
        "createStatement": f"CREATE DATABASE `{db_id}`",
        "extraStatements": statements
    }
    
    try:
        r = httpx.post(db_url, json=payload, timeout=timeout)
        if r.status_code in (200, 201):
            return True, "DDL validated successfully on Cloud Spanner Emulator"
        
        try:
            res_json = r.json()
            err = res_json.get("error", {}).get("message") or r.text
        except Exception:
            err = r.text
        return False, f"Spanner Emulator DDL Error: {err}"
    except Exception as e:
        return False, f"Connection to Spanner Emulator failed: {e}"

def drop_emulator_database(
    database_path: str,
    emulator_url: str | None = None,
    timeout: float = 10.0
) -> tuple[bool, str]:
    """Deletes an ephemeral database on Cloud Spanner Emulator."""
    base_url = _normalize_emulator_url(emulator_url)
    project_id = DEFAULT_EMULATOR_PROJECT
    instance_id = DEFAULT_EMULATOR_INSTANCE
    db_id = database_path
    
    if database_path.startswith("projects/"):
        parts = database_path.split("/")
        if len(parts) >= 6:
            project_id = parts[1]
            instance_id = parts[3]
            db_id = parts[5]
            
    del_url = f"{base_url}/v1/projects/{project_id}/instances/{instance_id}/databases/{db_id}"
    try:
        r = httpx.delete(del_url, timeout=timeout)
        if r.status_code in (200, 204, 404):
            return True, "Database deleted from emulator"
        return False, f"Failed to delete emulator database: {r.text}"
    except Exception as e:
        return False, str(e)

def list_emulator_databases(
    emulator_url: str | None = None,
    project_id: str = DEFAULT_EMULATOR_PROJECT,
    instance_id: str = DEFAULT_EMULATOR_INSTANCE,
    timeout: float = 10.0
) -> tuple[list[str], str | None]:
    """Lists all database IDs on Cloud Spanner Emulator."""
    base_url = _normalize_emulator_url(emulator_url)
    url = f"{base_url}/v1/projects/{project_id}/instances/{instance_id}/databases"
    try:
        r = httpx.get(url, timeout=timeout)
        if r.status_code == 200:
            data = r.json()
            databases = data.get("databases", [])
            db_ids = [db["name"].split("/")[-1] for db in databases if "name" in db]
            return db_ids, None
        return [], r.text
    except Exception as e:
        return [], str(e)

def call_spanner_mcp_tool(
    mcp_url: str,
    tool_name: str,
    arguments: dict,
    timeout: float = 120.0
) -> tuple[bool, str]:
    """Executes a tool on the Remote Spanner MCP server via JSON-RPC 2.0."""
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
    mcp_url: str | None = DEFAULT_MCP_URL,
    mcp_tool: str | None = "update_database_schema",
    database: str | None = None,
    use_emulator: bool = False,
    emulator_host: str | None = None,
) -> tuple[bool, str | None]:
    """Validate Spanner DDL syntax using official Google Spanner MCP server or local Spanner Emulator."""
    if use_emulator or os.getenv("SPANNER_EMULATOR_HOST"):
        return validate_ddl_on_emulator(ddl, emulator_url=emulator_host, database_path=database)

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
    mcp_url: str | None = DEFAULT_MCP_URL,
    mcp_tool: str | None = None,
    database: str | None = None,
    use_emulator: bool = False,
    emulator_host: str | None = None,
) -> tuple[bool | None, str | None]:
    """Checks if the database exists via Spanner MCP or Spanner Emulator."""
    if use_emulator or os.getenv("SPANNER_EMULATOR_HOST"):
        db_ids, err = list_emulator_databases(emulator_url=emulator_host)
        if err:
            return None, err
        target_id = database.split("/")[-1] if database else ""
        return target_id in db_ids, None

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

def drop_spanner_database(
    project_id: str,
    instance_id: str,
    db_id: str,
    use_emulator: bool = False,
    emulator_host: str | None = None
) -> tuple[bool, str]:
    """Drops a Cloud Spanner database using REST API, with emulator and gcloud fallbacks."""
    if use_emulator or os.getenv("SPANNER_EMULATOR_HOST"):
        return drop_emulator_database(f"projects/{project_id}/instances/{instance_id}/databases/{db_id}", emulator_url=emulator_host)

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

def list_spanner_databases(
    project_id: str,
    instance_id: str,
    use_emulator: bool = False,
    emulator_host: str | None = None
) -> tuple[list[str], str | None]:
    """Lists all database IDs in a Cloud Spanner instance using REST API / gcloud / emulator."""
    if use_emulator or os.getenv("SPANNER_EMULATOR_HOST"):
        return list_emulator_databases(emulator_url=emulator_host, project_id=project_id, instance_id=instance_id)

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
        except Exception:
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
        except Exception:
            pass
    return [], (res.stderr or "Failed to list databases").strip()

