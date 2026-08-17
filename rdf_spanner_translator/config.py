import os

# =============================================================================
# CENTRALIZED CONFIGURATION FOR RDF-TO-SPANNER TRANSLATOR
# =============================================================================

# Default Gemini model used across translation, self-correction, semantic audit, and query verification.
# Can be overridden via GEMINI_MODEL environment variable or CLI --model parameter.
DEFAULT_GEMINI_MODEL: str = os.getenv("GEMINI_MODEL", "gemini-3.7-flash")

# Default fallback Gemini model used automatically if the primary model encounters transient capacity errors (503/429).
FALLBACK_GEMINI_MODEL: str = os.getenv("GEMINI_FALLBACK_MODEL", "gemini-3.6-flash")

# Default Remote Spanner MCP Server URL
DEFAULT_MCP_URL: str = os.getenv("SPANNER_REMOTE_MCP_URL", "https://spanner.googleapis.com/mcp")
