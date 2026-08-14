"""Command-Line Interface (CLI) for the RDF-to-Spanner Graph DDL Translator.

This module uses the Click framework to expose command-line utilities for:
1. Translating OWL Ontologies (in Turtle format) into Spanner SQL schemas (Relational + Graph DDL).
2. Validating Spanner Graph DDL syntax against a database or emulator via a Remote MCP server.
3. Running the end-to-end self-correcting translation pipeline.
"""

import os
import click
from rich.console import Console
from rich.panel import Panel
from rich.syntax import Syntax

from rdf_spanner_translator.parser import validate_rdf_file
from rdf_spanner_translator.translator import (
    translate_ontology, 
    self_correct_ddl, 
    audit_spanner_schema, 
    extract_validation_score
)
from rdf_spanner_translator.validator import validate_ddl, check_database_existence
import json
from datetime import datetime, timezone

# Initialize Rich console for stylized and formatted terminal outputs
console = Console()


def save_telemetry(input_path: str, telemetry: dict):
    """Saves a JSON trace of a failed validation and its self-correction history in a single runlogs.json file."""
    try:
        os.makedirs("failures", exist_ok=True)
        runlogs_path = os.path.join("failures", "runlogs.json")
        
        runlogs = []
        if os.path.exists(runlogs_path):
            try:
                with open(runlogs_path, "r") as f:
                    runlogs = json.load(f)
            except Exception as e:
                console.print(f"[yellow]Warning: Could not parse existing runlogs.json ({e}). Starting fresh.[/yellow]")
        else:
            # Migrate legacy individual repair files
            for entry in os.listdir("failures"):
                if entry.endswith("_repair.json") and entry != "runlogs.json":
                    old_path = os.path.join("failures", entry)
                    try:
                        with open(old_path, "r") as f:
                            old_telemetry = json.load(f)
                            old_telemetry["captured_in_skill"] = False
                            runlogs.append(old_telemetry)
                        os.remove(old_path)
                    except Exception as e:
                        console.print(f"[yellow]Warning: Could not migrate {entry} ({e})[/yellow]")

        new_run = telemetry.copy()
        new_run["timestamp"] = datetime.now(timezone.utc).isoformat()
        if "captured_in_skill" not in new_run:
            new_run["captured_in_skill"] = False


        # Match entry by ontology_file and initial_ddl
        updated = False
        for idx, existing_run in enumerate(runlogs):
            if (existing_run.get("ontology_file") == new_run.get("ontology_file") and
                existing_run.get("initial_ddl") == new_run.get("initial_ddl")):
                # Update run details but preserve captured_in_skill flag if it was True
                new_run["captured_in_skill"] = existing_run.get("captured_in_skill", False)
                runlogs[idx] = new_run
                updated = True
                break
        
        if not updated:
            runlogs.append(new_run)
            
        with open(runlogs_path, "w") as f:
            json.dump(runlogs, f, indent=2)
    except Exception as e:
        console.print(f"[yellow]Warning: Could not save repair telemetry to failures folder ({e})[/yellow]")


@click.group()
def main():
    """Antigravity CLI Plugin and Standalone CLI: RDF/SHACL to Cloud Spanner Graph DDL."""
    pass

@main.command()
@click.option("--input", "-i", type=click.Path(exists=True), required=True, help="Path to input OWL/Turtle file.")
@click.option("--shacl", "-s", type=click.Path(exists=True), default=None, help="Path to optional SHACL shapes Turtle file.")
@click.option("--output", "-o", type=click.Path(), default="schema.sql", help="Path to output SQL file.")
@click.option("--model", "-m", default="gemini-3.5-flash", help="Gemini model to use.")
def translate(input, shacl, output, model):
    """Translate OWL ontology (Turtle) to Spanner Graph DDL, optionally guided by SHACL shapes."""
    console.print(Panel.fit(f"[bold blue]Translating Ontology[/bold blue]\nInput: {input}\nSHACL: {shacl}\nOutput: {output}", title="Gemini Translator"))
    
    try:
        # Step 1: Pre-validate Turtle file locally using rdflib
        with console.status("[green]Parsing & pre-validating Turtle file locally..."):
            stats = validate_rdf_file(input)
            
        console.print(f"[green]✓ Local validation successful![/green] (Found {stats['triples']} triples, {stats['classes_count']} classes, {stats['properties_count']} properties)")
        
        shacl_content = None
        if shacl:
            with console.status("[green]Parsing & pre-validating SHACL file locally..."):
                shacl_stats = validate_rdf_file(shacl)
            console.print(f"[green]✓ SHACL validation successful![/green] (Found {shacl_stats['triples']} triples)")
            
            with open(shacl, "r") as f:
                shacl_content = f.read()
        
        # Read the file contents
        with open(input, "r") as f:
            ttl_content = f.read()
            
        # Step 2: Request translation from the Gemini model
        with console.status(f"[yellow]Calling Gemini API ({model}) for translation..."):
            ddl = translate_ontology(ttl_content, shacl_content=shacl_content, model_name=model)
            
        # Step 3: Write the generated DDL output to the SQL target file
        output_dir = os.path.dirname(os.path.abspath(output))
        if output_dir:
            os.makedirs(output_dir, exist_ok=True)
        with open(output, "w") as f:
            f.write(ddl)
            
        console.print(f"[bold green]✓ DDL successfully generated and saved to {output}[/bold green]")
        
    except Exception as e:
        console.print(f"[bold red]Error:[/bold red] {e}")
        raise click.Abort()

@main.command()
@click.option("--ddl", "-d", type=click.Path(exists=True), required=True, help="Path to Spanner DDL SQL file.")
@click.option("--mcp-url", "-u", default="https://spanner.googleapis.com/mcp", envvar="SPANNER_REMOTE_MCP_URL", help="URL of Remote Spanner MCP Server.")
@click.option("--mcp-tool", "-t", envvar="SPANNER_MCP_TOOL_NAME", help="Name of tool on MCP server.")
@click.option("--database", "--db", envvar="SPANNER_DATABASE", help="Full Cloud Spanner database resource path (e.g., projects/<project>/instances/<instance>/databases/<database>).")
def validate(ddl, mcp_url, mcp_tool, database):
    """Validate Spanner DDL syntax using Remote MCP."""
    console.print(Panel.fit(f"[bold purple]Validating DDL Schema[/bold purple]\nFile: {ddl}\nDatabase: {database}", title="MCP Validator"))
    
    # Run database pre-validation check (existence vs expected tool state)
    if database and mcp_url:
        with console.status("[cyan]Verifying target database state..."):
            exists, err = check_database_existence(mcp_url, mcp_tool, database)
            if err:
                console.print(f"[yellow]Pre-validation warning: Could not verify database state ({err}). Proceeding...[/yellow]")
            elif exists is not None:
                if mcp_tool == "create_database" and exists:
                    console.print(f"[bold red]Error:[/bold red] Database already exists: {database}.\nChoose a new database ID or use the 'update_database_schema' tool.")
                    raise click.Abort()
                elif mcp_tool == "update_database_schema" and not exists:
                    console.print(f"[bold red]Error:[/bold red] Database does not exist: {database}.\nCreate the database first or use the 'create_database' tool.")
                    raise click.Abort()

    try:
        # Read SQL DDL file
        with open(ddl, "r") as f:
            ddl_content = f.read()
            
        # Connect to MCP server and invoke the DDL execution tool
        with console.status("[cyan]Connecting to MCP server and executing DDL..."):
            success, msg = validate_ddl(ddl_content, mcp_url, mcp_tool, database)
            
        # Report results
        if success:
            console.print(f"[bold green]✓ DDL validation successful![/bold green]\n[dim]{msg}[/dim]")
        else:
            console.print(f"[bold red]✗ DDL validation failed![/bold red]\n[red]{msg}[/red]")
            raise click.Abort()
            
    except Exception as e:
        console.print(f"[bold red]Error during validation:[/bold red] {e}")
        raise click.Abort()

@main.command("validate-semantic")
@click.option("--input", "-i", type=click.Path(exists=True), required=True, help="Path to input OWL/Turtle file.")
@click.option("--shacl", "-s", type=click.Path(exists=True), default=None, help="Path to optional SHACL shapes Turtle file.")
@click.option("--ddl", "-d", type=click.Path(exists=True), required=True, help="Path to generated Spanner SQL DDL file.")
@click.option("--output", "-o", type=click.Path(), default="validation_report.md", help="Path to output markdown report.")
@click.option("--model", "-m", default="gemini-2.5-pro", help="Gemini model to use for semantic audit.")
def validate_semantic_command(input, shacl, ddl, output, model):
    """Perform rigorous semantic validation of generated Spanner DDL against source OWL/SHACL using the Validation Skill."""
    console.print(Panel.fit(
        f"[bold cyan]Running Semantic Validation Audit[/bold cyan]\n"
        f"Source Ontology: {input}\n"
        f"SHACL Shapes: {shacl or 'None'}\n"
        f"Target DDL: {ddl}\n"
        f"Report Output: {output}\n"
        f"Model: {model}",
        title="Spanner Graph Semantic Auditor"
    ))
    
    try:
        with open(input, "r") as f:
            ttl_content = f.read()
            
        shacl_content = None
        if shacl:
            with open(shacl, "r") as f:
                shacl_content = f.read()
                
        with open(ddl, "r") as f:
            ddl_content = f.read()
            
        with console.status("[yellow]Auditing schema against 7 semantic validation dimensions..."):
            report = audit_spanner_schema(
                ttl_content=ttl_content,
                ddl_content=ddl_content,
                shacl_content=shacl_content,
                model_name=model
            )
            
        # Ensure output dir exists
        output_dir = os.path.dirname(os.path.abspath(output))
        if output_dir:
            os.makedirs(output_dir, exist_ok=True)
            
        with open(output, "w") as f:
            f.write(report)
            
        status, score = extract_validation_score(report)
        status_color = "green" if status == "PASS" else ("yellow" if status == "WARN" else "red")
        
        console.print(f"[{status_color}]✓ Semantic Validation Audit Complete: {status} ({score})[/{status_color}]")
        console.print(f"Executive one-pager report saved to [bold cyan]{output}[/bold cyan]")
        
    except Exception as e:
        console.print(f"[bold red]Error during semantic validation:[/bold red] {e}")
        raise click.Abort()

@main.command()
@click.option("--input", "-i", type=click.Path(exists=True), required=True, help="Path to input OWL/Turtle file.")
@click.option("--shacl", "-s", type=click.Path(exists=True), default=None, help="Path to optional SHACL shapes Turtle file.")
@click.option("--output", "-o", type=click.Path(), default="schema.sql", help="Path to output SQL file.")
@click.option("--report", "-r", type=click.Path(), default=None, help="Optional path to output executive semantic validation report markdown file.")
@click.option("--mcp-url", "-u", default="https://spanner.googleapis.com/mcp", envvar="SPANNER_REMOTE_MCP_URL", help="URL of Remote Spanner MCP Server.")
@click.option("--mcp-tool", "-t", envvar="SPANNER_MCP_TOOL_NAME", help="Name of tool on MCP server.")
@click.option("--self-correct/--no-self-correct", "-s", default=True, help="Enable self-correction loop.")
@click.option("--model", "-m", default="gemini-3.5-flash", help="Gemini model to use.")
@click.option("--database", "--db", envvar="SPANNER_DATABASE", help="Full Cloud Spanner database resource path (e.g., projects/<project>/instances/<instance>/databases/<database>).")
def run(input, shacl, output, report, mcp_url, mcp_tool, self_correct, model, database):
    """End-to-End: Translate OWL ontology, validate syntax via MCP, and self-correct if needed."""
    console.print(Panel.fit(f"[bold green]Running End-to-End Pipeline[/bold green]\nInput: {input}\nSHACL: {shacl}\nOutput: {output}\nSelf-correct: {self_correct}", title="RDF to Spanner Graph DDL Pipeline"))
    
    # Ensure output parent directory exists
    output_dir = os.path.dirname(os.path.abspath(output))
    if output_dir:
        os.makedirs(output_dir, exist_ok=True)

    # 1. Parsing and local RDF Turtle pre-validation
    try:
        with console.status("[green]Parsing & pre-validating Turtle file locally..."):
            stats = validate_rdf_file(input)
        console.print(f"[green]✓ Local validation successful![/green] (Found {stats['triples']} triples, {stats['classes_count']} classes, {stats['properties_count']} properties)")
    except Exception as e:
        console.print(f"[bold red]Error during parsing:[/bold red] {e}")
        raise click.Abort()
        
    shacl_content = None
    if shacl:
        try:
            with console.status("[green]Parsing & pre-validating SHACL file locally..."):
                shacl_stats = validate_rdf_file(shacl)
            console.print(f"[green]✓ SHACL validation successful![/green] (Found {shacl_stats['triples']} triples)")
            
            with open(shacl, "r") as f:
                shacl_content = f.read()
        except Exception as e:
            console.print(f"[bold red]Error during SHACL parsing:[/bold red] {e}")
            raise click.Abort()

    with open(input, "r") as f:
        ttl_content = f.read()
        
    # Pre-validation: Verify database state via MCP before translating to avoid unnecessary API cost
    if database and mcp_url:
        with console.status("[cyan]Verifying target database state..."):
            exists, err = check_database_existence(mcp_url, mcp_tool, database)
            if err:
                console.print(f"[yellow]Pre-validation warning: Could not verify database state ({err}). Proceeding...[/yellow]")
            elif exists is not None:
                if mcp_tool == "create_database" and exists:
                    console.print(f"[bold red]Error:[/bold red] Database already exists: {database}.\nChoose a new database ID or use the 'update_database_schema' tool.")
                    raise click.Abort()
                elif mcp_tool == "update_database_schema" and not exists:
                    console.print(f"[bold red]Error:[/bold red] Database does not exist: {database}.\nCreate the database first or use the 'create_database' tool.")
                    raise click.Abort()
        
    # 2. Translate Turtle Ontology into Cloud Spanner DDL using Gemini
    try:
        with console.status(f"[yellow]Calling Gemini API ({model}) for translation..."):
            ddl = translate_ontology(ttl_content, shacl_content=shacl_content, model_name=model)
    except Exception as e:
        console.print(f"[bold red]Error during translation:[/bold red] {e}")
        raise click.Abort()
        
    # 3. Validation execution via the MCP Server
    if not mcp_url:
        # If no validation harness environment is defined, write translation and return
        with open(output, "w") as f:
            f.write(ddl)
        console.print(f"[yellow]! Validation skipped (no MCP configuration provided). Saved DDL to {output}[/yellow]")
        return
        
    def _generate_report_if_requested(target_ddl):
        if report:
            try:
                with console.status("[yellow]Auditing schema & generating executive semantic validation report..."):
                    rep = audit_spanner_schema(ttl_content, target_ddl, shacl_content)
                rep_dir = os.path.dirname(os.path.abspath(report))
                if rep_dir:
                    os.makedirs(rep_dir, exist_ok=True)
                with open(report, "w") as f:
                    f.write(rep)
                status, score = extract_validation_score(rep)
                status_color = "green" if status == "PASS" else ("yellow" if status == "WARN" else "red")
                console.print(f"[{status_color}]✓ Executive Semantic Validation Report generated: {status} ({score}) -> {report}[/{status_color}]")
            except Exception as ex:
                console.print(f"[yellow]Warning: Could not generate semantic report: {ex}[/yellow]")

    try:
        # Run first validation pass
        with console.status("[cyan]Connecting to MCP server and executing DDL..."):
            success, msg = validate_ddl(ddl, mcp_url, mcp_tool, database)
            
        if success:
            with open(output, "w") as f:
                f.write(ddl)
            console.print(f"[bold green]✓ DDL validation successful![/bold green] Saved verified DDL to {output}")
            _generate_report_if_requested(ddl)
            return
            
        # If validation fails, proceed to error logging and self-correction
        console.print(f"[bold red]✗ Initial DDL validation failed![/bold red]")
        console.print(f"[red]Error Message:[/red]\n{msg}")
        
        telemetry = {
            "ontology_file": input,
            "ontology_content": ttl_content,
            "initial_ddl": ddl,
            "initial_error": msg,
            "correction_attempts": [],
            "final_status": "FAILURE",
            "final_ddl": ddl
        }
        if shacl:
            telemetry["shacl_file"] = shacl
            telemetry["shacl_content"] = shacl_content
        
        if not self_correct:
            with open(output, "w") as f:
                f.write(ddl)
            console.print(f"[yellow]Self-correction disabled. Saved invalid DDL to {output}[/yellow]")
            raise click.Abort()
            
        # 4. Self-correction loop: prompt Gemini with compiler/parser errors to rewrite DDL
        max_attempts = 3
        attempt = 1
        current_ddl = ddl
        current_error = msg
        
        while attempt <= max_attempts:
            console.print(f"\n[bold yellow]Starting Self-Correction Attempt {attempt}/{max_attempts}...[/bold yellow]")
            
            # Send invalid DDL + compiler error + original Turtle file to Gemini to repair
            with console.status(f"[yellow]Requesting correction from Gemini..."):
                current_ddl = self_correct_ddl(ttl_content, current_ddl, current_error, shacl_content=shacl_content, model_name=model)
                
            # Re-execute the corrected schema against Spanner via MCP
            console.print(f"[yellow]Executing corrected DDL...[/yellow]")
            with console.status("[cyan]Re-validating corrected DDL..."):
                # Dynamically choose between create_database and update_database_schema
                if mcp_tool == "create_database" and database and mcp_url:
                    exists, _ = check_database_existence(mcp_url, mcp_tool, database)
                    active_tool = "update_database_schema" if exists else "create_database"
                else:
                    active_tool = mcp_tool
                success, msg = validate_ddl(current_ddl, mcp_url, active_tool, database)
                
            attempt_info = {
                "attempt": attempt,
                "corrected_ddl": current_ddl,
                "error": msg if not success else None
            }
            telemetry["correction_attempts"].append(attempt_info)
                
            if success:
                # If correction was successful, save the new DDL and exit
                with open(output, "w") as f:
                    f.write(current_ddl)
                console.print(f"[bold green]✓ Self-correction successful! DDL is now valid.[/bold green] Saved verified DDL to {output}")
                
                telemetry["final_status"] = "SUCCESS"
                telemetry["final_ddl"] = current_ddl
                save_telemetry(input, telemetry)
                _generate_report_if_requested(current_ddl)
                return
                
            # Log failure and loop again if attempts remain
            console.print(f"[bold red]✗ Corrected DDL validation failed![/bold red]")
            console.print(f"[red]Error Message:[/red]\n{msg}")
            current_error = msg
            attempt += 1
            
        # If the self-correction loop exhausted all attempts without finding a valid DDL schema
        with open(output, "w") as f:
            f.write(current_ddl)
        console.print(f"[bold red]✗ Failed to generate a valid schema after {max_attempts} correction attempts.[/bold red] Saved last attempt to {output}")
        
        telemetry["final_status"] = "FAILURE"
        telemetry["final_ddl"] = current_ddl
        save_telemetry(input, telemetry)
        raise click.Abort()
        
    except Exception as e:
        console.print(f"[bold red]Error during pipeline execution:[/bold red] {e}")
        raise click.Abort()

if __name__ == "__main__":
    main()
