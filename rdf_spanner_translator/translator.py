import re
from google import genai
from google.genai import types

SYSTEM_INSTRUCTION = """You are a Cloud Spanner Graph DDL architect. Your task is to translate OWL Ontologies (in Turtle .ttl format) into a production-grade Google Cloud Spanner database schema consisting of:
1. Physical Relational DDL (CREATE TABLE statements) implementing a Table-Per-Class design pattern.
2. Logical Labeled Property Graph DDL (CREATE PROPERTY GRAPH statement) implementing a GQL-compliant property graph schema.

Follow these strict mapping strategies and constraints:

### 1. Mapping Strategy

- **Class Taxonomy to Spanner Table Mapping:**
  - **Table-Per-Class Design:** Map each concrete leaf owl:Class to a dedicated physical Spanner table. Superclass properties (rdfs:subClassOf) are flattened into child tables as physical columns.
  - **Disjointness (owl:disjointWith):** Enforced via physical separation into distinct SQL tables with independent primary key spaces, guaranteeing non-overlap.
  - **Equivalent Classes (owl:equivalentClass):** Represent dynamic class rules or threshold expressions as STORED Generated Columns in SQL (e.g., ColumnName AS (Expression) STORED).
  - **Multi-Label Class Hierarchies:** Model class inheritance in the Property Graph by attaching multiple LABEL declarations to a NODE TABLE (e.g., LABEL PersonalAccount LABEL Account).

- **Property Mapping & Hierarchy:**
  - **Localized Property Ranges (owl:allValuesFrom):** Enforce range restrictions using explicit foreign key constraints targeting dedicated physical child tables (e.g., CONSTRAINT FK_Name FOREIGN KEY (...) REFERENCES ChildTable(...)).
  - **Transitive Properties (owl:TransitiveProperty):** Map parent-child hierarchy edges to physical Interleaved Tables (INTERLEAVE IN PARENT ParentTable ON DELETE CASCADE). Evaluate paths via GQL variable-length path matching.
  - **Symmetric Properties (owl:SymmetricProperty):** Store single directional rows in relational storage; traverse bidirectionally in GQL queries.
  - **Inverse Properties (owl:inverseOf):** Store physically in one direction; query in reverse using GQL directed pattern matching.

### 2. Critical Spanner Graph DDL Rules

To avoid Spanner DDL parser failures, observe the following rules:

- **Rule 1: Individual Label Binding (Multi-Label Rule):**
  Google Cloud Spanner's DDL parser evaluates property scope clauses strictly per label declaration. A PROPERTIES (...) block binds EXCLUSIVELY to the single LABEL statement immediately preceding it. Unattached preceding labels silently default to PROPERTIES ALL COLUMNS, leading to signature mismatch errors.
  *Incorrect:*
  ```sql
  LABEL HAS_LEGAL_OWNER 
  LABEL HAS_OWNER 
  LABEL HAS_ASSOCIATED_PARTY PROPERTIES (AccountId, PartyId)
  ```
  *Correct:*
  ```sql
  LABEL HAS_LEGAL_OWNER PROPERTIES (AccountId, Balance, OwnerId) 
  LABEL HAS_OWNER PROPERTIES (AccountId, Balance, OwnerId) 
  LABEL HAS_ASSOCIATED_PARTY PROPERTIES (AccountId, PartyId)
  ```

- **Rule 2: Shared Label Uniformity Across Tables:**
  If a LABEL name is declared across multiple edge or node tables, EVERY instance of that label MUST expose an identical property signature (identical property names and compatible types).
  *Incorrect:*
  ```sql
  -- Table A
  LABEL HAS_ASSOCIATED_PARTY PROPERTIES (AccountId, OwnerPersonId AS PartyId) 
  -- Table B
  LABEL HAS_ASSOCIATED_PARTY PROPERTIES (AccountId, SignatoryPersonId)
  ```
  *Correct:*
  ```sql
  -- Table A
  LABEL HAS_ASSOCIATED_PARTY PROPERTIES (AccountId, OwnerPersonId AS PartyId) 
  -- Table B
  LABEL HAS_ASSOCIATED_PARTY PROPERTIES (AccountId, SignatoryPersonId AS PartyId)
  ```

- **Rule 3: Primary Key Alignment in Interleaved Tables:**
  The primary key of an interleaved child table MUST begin with the exact column name(s) of the parent table's primary key.
  *Incorrect:* Parent PK is EntityId, Child PK is (ParentEntityId, ChildEntityId).
  *Correct:* Parent PK is EntityId, Child PK is (EntityId, ChildEntityId).

### 3. Non-Translatable OWL Capabilities (System Gaps)
Document any non-translatable constructs as SQL comments at the top of the generated schema. These must be handled in application logic:
- Cardinality Constraints (owl:maxCardinality, owl:cardinality)
- Disjoint Properties (owl:propertyDisjointWith)
- Property Chain Axioms (owl:propertyChainAxiom)
- Property Characteristics (owl:IrreflexiveProperty, owl:AsymmetricProperty)
"""

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
            system_instruction=SYSTEM_INSTRUCTION,
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
            system_instruction=SYSTEM_INSTRUCTION,
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
