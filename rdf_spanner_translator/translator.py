import os
import re
import time
import random
from google import genai
from google.genai import types

from .config import DEFAULT_GEMINI_MODEL, FALLBACK_GEMINI_MODEL

def load_skill_instructions(skill_name: str, fallback_prompt: str = "") -> str:
    """Dynamically loads and cleans any skill instruction from skills/<skill_name>/SKILL.md.
    
    Strips YAML frontmatter block (starts and ends with ---) to extract clean Markdown instructions.
    """
    project_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    skill_path = os.path.join(project_root, "skills", skill_name, "SKILL.md")
    
    if os.path.exists(skill_path):
        try:
            with open(skill_path, "r") as f:
                content = f.read()
            # Strip YAML frontmatter block
            content_clean = re.sub(r"^---.*?---", "", content, flags=re.DOTALL)
            return content_clean.strip()
        except Exception:
            pass
            
    return fallback_prompt.strip()


def load_system_instruction() -> str:
    """Loads translation system instructions dynamically from SKILL.md."""
    fallback = (
        "You are a Cloud Spanner Graph DDL architect. Your task is to translate OWL Ontologies "
        "(in Turtle .ttl format) into a production-grade Google Cloud Spanner database schema consisting of "
        "Physical Relational DDL (CREATE TABLE statements) and Logical Labeled Property Graph DDL (CREATE PROPERTY GRAPH)."
    )
    return load_skill_instructions("owl-to-spanner-property-graph-translator", fallback)

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

def _generate_with_retry(client: genai.Client, model: str, contents, config: types.GenerateContentConfig, max_retries: int = 3):
    """Executes client.models.generate_content with exponential backoff on transient 503/429 errors, falling back to FALLBACK_GEMINI_MODEL if needed."""
    models_to_try = [model]
    if FALLBACK_GEMINI_MODEL and FALLBACK_GEMINI_MODEL != model:
        models_to_try.append(FALLBACK_GEMINI_MODEL)
        
    last_exception = None
    for current_model in models_to_try:
        delay = 1.5
        for attempt in range(1, max_retries + 1):
            try:
                return client.models.generate_content(
                    model=current_model,
                    contents=contents,
                    config=config,
                )
            except Exception as e:
                last_exception = e
                err_str = str(e)
                is_transient = "503" in err_str or "429" in err_str or "UNAVAILABLE" in err_str or "RESOURCE_EXHAUSTED" in err_str
                if is_transient and attempt < max_retries:
                    sleep_time = delay + random.uniform(0.5, 1.5)
                    time.sleep(sleep_time)
                    delay *= 2
                    continue
                # Break to try fallback model if available
                break
                
    if last_exception:
        raise last_exception


def translate_ontology(ttl_content: str, shacl_content: str = None, model_name: str = DEFAULT_GEMINI_MODEL) -> str:
    """Translates OWL ontology to Spanner Graph DDL using Gemini, optionally guided by SHACL shapes."""
    client = _get_client()
    
    prompt = f"""Please translate the following OWL Ontology in Turtle syntax to Google Cloud Spanner DDL:

```turtle
{ttl_content}
```
"""
    if shacl_content:
        prompt += f"""
Additionally, apply constraints from the following SHACL Shapes (in Turtle syntax) to define physical column types (e.g. datatypes, nullability, cardinalities) and property graph elements:

```turtle
{shacl_content}
```
"""
    prompt += """
Ensure you follow the Spanner Graph DDL rules and output a single unified SQL code block.
"""
    
    response = _generate_with_retry(
        client=client,
        model=model_name,
        contents=prompt,
        config=types.GenerateContentConfig(
            system_instruction=load_system_instruction(),
            temperature=0.0,
        )
    )
    
    return clean_ddl_response(response.text)

def self_correct_ddl(ttl_content: str, invalid_ddl: str, error_message: str, shacl_content: str = None, model_name: str = DEFAULT_GEMINI_MODEL) -> str:
    """Uses Gemini to correct DDL that failed validation, optionally guided by SHACL shapes."""
    client = _get_client()
    
    prompt = f"""The generated Cloud Spanner DDL failed validation with the following error:
{error_message}

Here is the original OWL Ontology:
```turtle
{ttl_content}
```
"""
    if shacl_content:
        prompt += f"""
Here are the SHACL Shapes:
```turtle
{shacl_content}
```
"""
    prompt += f"""
Here is the invalid DDL that was generated:
```sql
{invalid_ddl}
```

Analyze the error, fix the root cause, and output the corrected DDL containing BOTH the table definitions and the CREATE PROPERTY GRAPH statement.
"""
    
    response = _generate_with_retry(
        client=client,
        model=model_name,
        contents=prompt,
        config=types.GenerateContentConfig(
            system_instruction=load_system_instruction(),
            temperature=0.0,
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


def clean_html_response(text: str) -> str:
    """Extracts HTML code blocks if wrapped in markdown fences, otherwise returns text."""
    match = re.search(r"```(?:html)?\s*(<!DOCTYPE\s+html.*?)```", text, re.DOTALL | re.IGNORECASE)
    if match:
        return match.group(1).strip()
    match_html_tag = re.search(r"(<!DOCTYPE\s+html.*)", text, re.DOTALL | re.IGNORECASE)
    if match_html_tag:
        return match_html_tag.group(1).strip()
    return text.strip()


def load_validation_system_instruction() -> str:
    """Loads semantic validation system instructions dynamically from SKILL.md."""
    fallback = (
        "You are a Cloud Spanner Graph Semantic Auditor. Evaluate the generated Spanner DDL "
        "against the source OWL ontology and SHACL shapes, producing an executive one-pager validation report in HTML."
    )
    return load_skill_instructions("spanner-graph-semantic-validator", fallback)


def audit_spanner_schema(
    ttl_content: str, 
    ddl_content: str, 
    shacl_content: str = None, 
    model_name: str = DEFAULT_GEMINI_MODEL
) -> str:
    """Evaluates generated Spanner DDL against source OWL/SHACL using the validation skill."""
    client = _get_client()
    
    prompt = f"""Please perform a rigorous semantic validation of the following generated Cloud Spanner DDL against the source OWL Ontology and SHACL shapes.

### Source OWL Ontology (Turtle .ttl):
```turtle
{ttl_content}
```
"""
    if shacl_content:
        prompt += f"""
### Companion SHACL Shapes:
```turtle
{shacl_content}
```
"""
    prompt += f"""
### Generated Cloud Spanner DDL:
```sql
{ddl_content}
```

Evaluate the translation across all 7 dimensions specified in your instructions. Format your evaluation strictly as the Executive One-Pager Validation Report in standalone HTML.
"""
    
    response = _generate_with_retry(
        client=client,
        model=model_name,
        contents=prompt,
        config=types.GenerateContentConfig(
            system_instruction=load_validation_system_instruction(),
            temperature=0.0,
        )
    )
    
    return clean_html_response(response.text)


def extract_validation_score(report_text: str) -> tuple[str, str]:
    """Extracts the validation status and score from the generated report (HTML or Markdown).
    
    Returns:
        (status, score_str) e.g. ("PASS", "100%") or ("WARN", "92%") or ("FAIL", "75%")
    """
    status = "UNKNOWN"
    score = "N/A"
    
    # Check overall status
    if "PASS" in report_text:
        status = "PASS"
    if "WARN" in report_text:
        status = "WARN"
    if "FAIL" in report_text and "0 Failed" not in report_text and "failed: 0" not in report_text.lower():
        status = "FAIL"
    
    # Extract percentage score
    score_match = re.search(r"(\d{1,3}%)\s*Score", report_text, re.IGNORECASE)
    if not score_match:
        score_match = re.search(r"\|\s*Total[^\n]+\|\s*(\d{1,3}%)\s*\|", report_text, re.IGNORECASE)
    if not score_match:
        score_match = re.search(r"(\d{1,3}%)\s*(?:PASS|WARN|FAIL)", report_text, re.IGNORECASE)
    if not score_match:
        score_match = re.search(r"(?:<td>|Score\s*:?\s*)(\d{1,3}%)", report_text, re.IGNORECASE)
    if not score_match:
        score_match = re.search(r"(\d{1,3}%)", report_text)
        
    if score_match:
        score = score_match.group(1)
        
    return status, score
