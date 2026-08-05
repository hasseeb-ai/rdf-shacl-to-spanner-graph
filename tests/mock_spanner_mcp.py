import asyncio
import os
from mcp.server.mcpserver import MCPServer

server = MCPServer("mock-spanner-mcp")
ATTEMPT_FILE = "tests/attempt_count.txt"

@server.tool(name="execute_ddl", description="Executes DDL statements against Cloud Spanner Graph database")
async def execute_ddl(ddl: str) -> str:
    """Executes DDL statements against Cloud Spanner Graph database.
    
    Args:
        ddl: The DDL statement(s) to execute.
    """
    attempt = 1
    if os.path.exists(ATTEMPT_FILE):
        try:
            with open(ATTEMPT_FILE, "r") as f:
                attempt = int(f.read().strip())
        except:
            pass

    if "SYNTAX_ERROR" in ddl:
        raise ValueError("Syntax error: Unexpected keyword 'PROPERTIES' on line 14")
    elif "LABEL_MISMATCH" in ddl:
        raise ValueError("Google Cloud Spanner DDL parser error: LABEL 'HAS_ASSOCIATED_PARTY' has incompatible properties in different tables.")
    elif "FAIL_VALIDATION" in ddl:
        if attempt == 1:
            with open(ATTEMPT_FILE, "w") as f:
                f.write("2")
            raise ValueError("Error: Primary key of interleaved table 'PersonalSubAccounts' must begin with parent table's primary key 'AccountId'. Found 'ChildAccountId'.")
        else:
            if os.path.exists(ATTEMPT_FILE):
                os.remove(ATTEMPT_FILE)
            return "DDL applied successfully after correction."
        
    return "DDL applied successfully."

async def main():
    await server.run_stdio_async()

if __name__ == "__main__":
    asyncio.run(main())
