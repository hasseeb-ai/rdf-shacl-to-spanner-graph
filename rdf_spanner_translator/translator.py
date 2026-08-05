import os
import re
from google import genai
from google.genai import types

def load_system_instruction() -> str:
    """Loads translation system instructions dynamically from SKILL.md.
    
    This ensures that the rules and constraints declared in the Agent Skill are
    reused as the single source of truth for both Gemini CLI and python API.
    """
    project_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    skill_path = os.path.join(
        project_root, 
        "skills", 
        "owl-to-spanner-property-graph-translator", 
        "SKILL.md"
    )
    
    if os.path.exists(skill_path):
        try:
            with open(skill_path, "r") as f:
                content = f.read()
            # Strip YAML frontmatter block (starts and ends with ---)
            content_clean = re.sub(r"^---.*?---", "", content, flags=re.DOTALL)
            return content_clean.strip()
        except Exception:
            pass
            
    # Standard translation prompt fallback if file is not readable or missing
    return (
        "You are a Cloud Spanner Graph DDL architect. Your task is to translate OWL Ontologies "
        "(in Turtle .ttl format) into a production-grade Google Cloud Spanner database schema consisting of "
        "Physical Relational DDL (CREATE TABLE statements) and Logical Labeled Property Graph DDL (CREATE PROPERTY GRAPH)."
    )

def _get_client() -> genai.Client:
    """Initializes the GenAI client.
    
    Tries GEMINI_API_KEY first (AI Studio), then falls back to Vertex AI (ADC).
    """
    import os
    api_key = os.environ.get("GEMINI_API_KEY")
    if api_key:
        return genai.Client(api_key=api_key)
        
    project = os.environ.get("GCP_PROJECT") or os.environ.get("GCLOUD_PROJECT")
    location = os.environ.get("GCP_LOCATION") or "us-central1"
    
    try:
        return genai.Client(vertexai=True, project=project, location=location)
    except Exception as e:
        raise ValueError(
            "Gemini Client initialization failed. Please set the GEMINI_API_KEY "
            "environment variable for Google AI Studio, or configure Google Application "
            "Default Credentials (ADC) for Vertex AI."
        ) from e

def translate_ontology(ttl_content: str, model_name: str = "gemini-2.5-pro") -> str:
    """Translates OWL ontology to Spanner Graph DDL using Gemini."""
    client = _get_client()
    
    prompt = f"""Please translate the following OWL Ontology in Turtle syntax to Google Cloud Spanner DDL:

```turtle
{ttl_content}
```

Ensure you follow the Spanner Graph DDL rules and output a single unified SQL code block.
"""
    
    response = client.models.generate_content(
        model=model_name,
        contents=prompt,
        config=types.GenerateContentConfig(
            system_instruction=load_system_instruction(),
            temperature=0.1,
        )
    )
    
    return clean_ddl_response(response.text)

def self_correct_ddl(ttl_content: str, invalid_ddl: str, error_message: str, model_name: str = "gemini-2.5-pro") -> str:
    """Uses Gemini to correct DDL that failed validation."""
    client = _get_client()
    
    prompt = f"""The generated Cloud Spanner DDL failed validation with the following error:
{error_message}

Here is the original OWL Ontology:
```turtle
{ttl_content}
```

Here is the invalid DDL that was generated:
```sql
{invalid_ddl}
```

Analyze the error, fix the root cause, and output the corrected DDL containing BOTH the table definitions and the CREATE PROPERTY GRAPH statement.
"""
    
    response = client.models.generate_content(
        model=model_name,
        contents=prompt,
        config=types.GenerateContentConfig(
            system_instruction=load_system_instruction(),
            temperature=0.1,
        )
    )
    
    return clean_ddl_response(response.text)

def clean_ddl_response(text: str) -> str:
    """Extracts SQL code blocks from the Gemini response."""
    match = re.search(r"```sql\s*(.*?)\s*```", text, re.DOTALL | re.IGNORECASE)
    if match:
        return match.group(1).strip()
    match_any = re.search(r"```\s*(.*?)\s*```", text, re.DOTALL)
    if match_any:
        return match_any.group(1).strip()
    return text.strip()
