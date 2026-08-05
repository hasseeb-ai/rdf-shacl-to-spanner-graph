import os
import click
from rich.console import Console
from rich.panel import Panel
from rich.syntax import Syntax

from rdf_spanner_translator.parser import validate_rdf_file
from rdf_spanner_translator.translator import translate_ontology, self_correct_ddl
from rdf_spanner_translator.validator import validate_ddl

console = Console()

@click.group()
def main():
    """Gemini CLI Extension: RDF/SHACL to Cloud Spanner Graph DDL."""
    pass

@main.command()
@click.option("--input", "-i", type=click.Path(exists=True), required=True, help="Path to input OWL/Turtle file.")
@click.option("--output", "-o", type=click.Path(), default="schema.sql", help="Path to output SQL file.")
@click.option("--model", "-m", default="gemini-2.5-pro", help="Gemini model to use.")
def translate(input, output, model):
    """Translate OWL ontology (Turtle) to Spanner Graph DDL."""
    console.print(Panel.fit(f"[bold blue]Translating Ontology[/bold blue]\nInput: {input}\nOutput: {output}", title="Gemini Translator"))
    
    try:
        # Pre-validate with rdflib
        with console.status("[green]Parsing & pre-validating Turtle file locally..."):
            stats = validate_rdf_file(input)
            
        console.print(f"[green]✓ Local validation successful![/green] (Found {stats['triples']} triples, {stats['classes_count']} classes, {stats['properties_count']} properties)")
        
        # Read content
        with open(input, "r") as f:
            ttl_content = f.read()
            
        # Call Gemini translation
        with console.status(f"[yellow]Calling Gemini API ({model}) for translation..."):
            ddl = translate_ontology(ttl_content, model_name=model)
            
        # Write to file
        with open(output, "w") as f:
            f.write(ddl)
            
        console.print(f"[bold green]✓ DDL successfully generated and saved to {output}[/bold green]")
        
    except Exception as e:
        console.print(f"[bold red]Error:[/bold red] {e}")
        raise click.Abort()

@main.command()
@click.option("--ddl", "-d", type=click.Path(exists=True), required=True, help="Path to Spanner DDL SQL file.")
@click.option("--mcp-url", "-u", envvar="SPANNER_REMOTE_MCP_URL", help="SSE URL of Remote MCP Server.")
@click.option("--mcp-cmd", "-c", envvar="SPANNER_LOCAL_MCP_CMD", help="Stdio command to run Remote MCP Server.")
@click.option("--mcp-tool", "-t", envvar="SPANNER_MCP_TOOL_NAME", help="Name of tool on MCP server.")
def validate(ddl, mcp_url, mcp_cmd, mcp_tool):
    """Validate Spanner DDL syntax using Remote MCP."""
    if not mcp_url and not mcp_cmd:
        console.print("[bold red]Error:[/bold red] You must specify either --mcp-url or --mcp-cmd (or set SPANNER_REMOTE_MCP_URL/SPANNER_LOCAL_MCP_CMD environment variables)")
        raise click.Abort()
        
    console.print(Panel.fit(f"[bold purple]Validating DDL Schema[/bold purple]\nFile: {ddl}", title="MCP Validator"))
    
    try:
        with open(ddl, "r") as f:
            ddl_content = f.read()
            
        with console.status("[cyan]Connecting to MCP server and executing DDL..."):
            success, msg = validate_ddl(ddl_content, mcp_url, mcp_cmd, mcp_tool)
            
        if success:
            console.print(f"[bold green]✓ DDL validation successful![/bold green]\n[dim]{msg}[/dim]")
        else:
            console.print(f"[bold red]✗ DDL validation failed![/bold red]\n[red]{msg}[/red]")
            raise click.Abort()
            
    except Exception as e:
        console.print(f"[bold red]Error during validation:[/bold red] {e}")
        raise click.Abort()

@main.command()
@click.option("--input", "-i", type=click.Path(exists=True), required=True, help="Path to input OWL/Turtle file.")
@click.option("--output", "-o", type=click.Path(), default="schema.sql", help="Path to output SQL file.")
@click.option("--mcp-url", "-u", envvar="SPANNER_REMOTE_MCP_URL", help="SSE URL of Remote MCP Server.")
@click.option("--mcp-cmd", "-c", envvar="SPANNER_LOCAL_MCP_CMD", help="Stdio command to run Remote MCP Server.")
@click.option("--mcp-tool", "-t", envvar="SPANNER_MCP_TOOL_NAME", help="Name of tool on MCP server.")
@click.option("--self-correct/--no-self-correct", "-s", default=True, help="Enable self-correction loop.")
@click.option("--model", "-m", default="gemini-2.5-pro", help="Gemini model to use.")
def run(input, output, mcp_url, mcp_cmd, mcp_tool, self_correct, model):
    """End-to-End: Translate OWL ontology, validate syntax via MCP, and self-correct if needed."""
    console.print(Panel.fit(f"[bold green]Running End-to-End Pipeline[/bold green]\nInput: {input}\nOutput: {output}\nSelf-correct: {self_correct}", title="RDF to Spanner Graph DDL Pipeline"))
    
    # 1. Parsing
    try:
        with console.status("[green]Parsing & pre-validating Turtle file locally..."):
            stats = validate_rdf_file(input)
        console.print(f"[green]✓ Local validation successful![/green] (Found {stats['triples']} triples, {stats['classes_count']} classes, {stats['properties_count']} properties)")
    except Exception as e:
        console.print(f"[bold red]Error during parsing:[/bold red] {e}")
        raise click.Abort()
        
    # Read Turtle file
    with open(input, "r") as f:
        ttl_content = f.read()
        
    # 2. Translation
    try:
        with console.status(f"[yellow]Calling Gemini API ({model}) for translation..."):
            ddl = translate_ontology(ttl_content, model_name=model)
    except Exception as e:
        console.print(f"[bold red]Error during translation:[/bold red] {e}")
        raise click.Abort()
        
    # 3. Validation and correction
    if not mcp_url and not mcp_cmd:
        with open(output, "w") as f:
            f.write(ddl)
        console.print(f"[yellow]! Validation skipped (no MCP configuration provided). Saved DDL to {output}[/yellow]")
        return
        
    try:
        with console.status("[cyan]Connecting to MCP server and executing DDL..."):
            success, msg = validate_ddl(ddl, mcp_url, mcp_cmd, mcp_tool)
            
        if success:
            with open(output, "w") as f:
                f.write(ddl)
            console.print(f"[bold green]✓ DDL validation successful![/bold green] Saved verified DDL to {output}")
            return
            
        console.print(f"[bold red]✗ Initial DDL validation failed![/bold red]")
        console.print(f"[red]Error Message:[/red]\n{msg}")
        
        if not self_correct:
            with open(output, "w") as f:
                f.write(ddl)
            console.print(f"[yellow]Self-correction disabled. Saved invalid DDL to {output}[/yellow]")
            raise click.Abort()
            
        # 4. Self-correction loop
        max_attempts = 3
        attempt = 1
        current_ddl = ddl
        current_error = msg
        
        while attempt <= max_attempts:
            console.print(f"\n[bold yellow]Starting Self-Correction Attempt {attempt}/{max_attempts}...[/bold yellow]")
            
            with console.status(f"[yellow]Requesting correction from Gemini..."):
                current_ddl = self_correct_ddl(ttl_content, current_ddl, current_error, model_name=model)
                
            console.print(f"[yellow]Executing corrected DDL...[/yellow]")
            with console.status("[cyan]Re-validating corrected DDL..."):
                success, msg = validate_ddl(current_ddl, mcp_url, mcp_cmd, mcp_tool)
                
            if success:
                with open(output, "w") as f:
                    f.write(current_ddl)
                console.print(f"[bold green]✓ Self-correction successful! DDL is now valid.[/bold green] Saved verified DDL to {output}")
                return
                
            console.print(f"[bold red]✗ Corrected DDL validation failed![/bold red]")
            console.print(f"[red]Error Message:[/red]\n{msg}")
            current_error = msg
            attempt += 1
            
        # If all attempts failed
        with open(output, "w") as f:
            f.write(current_ddl)
        console.print(f"[bold red]✗ Failed to generate a valid schema after {max_attempts} correction attempts.[/bold red] Saved last attempt to {output}")
        raise click.Abort()
        
    except Exception as e:
        console.print(f"[bold red]Error during pipeline execution:[/bold red] {e}")
        raise click.Abort()

if __name__ == "__main__":
    main()
