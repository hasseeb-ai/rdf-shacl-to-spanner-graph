import os

# =============================================================================
# CENTRALIZED CONFIGURATION FOR RDF-TO-SPANNER TRANSLATOR
# =============================================================================

# Default Gemini model used across translation, self-correction, semantic audit, and query verification.
# Can be overridden via GEMINI_MODEL environment variable or CLI --model parameter.
DEFAULT_GEMINI_MODEL: str = os.getenv("GEMINI_MODEL", "gemini-2.5-flash")

# Default Remote Spanner MCP Server URL
DEFAULT_MCP_URL: str = os.getenv("SPANNER_REMOTE_MCP_URL", "https://spanner.googleapis.com/mcp")
