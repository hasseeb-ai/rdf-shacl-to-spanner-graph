"""Command-Line Interface (CLI) for the RDF-to-Spanner Graph DDL Translator.

This module uses the Click framework to expose command-line utilities for:
1. Translating OWL Ontologies (in Turtle format) into Spanner SQL schemas (Relational + Graph DDL).
2. Validating Spanner Graph DDL syntax against a database or emulator via a Remote MCP server.
3. Running the end-to-end self-correcting translation pipeline.
"""

import os
import sys
import glob
import json
import uuid
import shutil
import subprocess
from datetime import datetime, timezone
import click
from rich.console import Console
from rich.panel import Panel
from rich.table import Table
from rich.syntax import Syntax

from rdf_spanner_translator.config import DEFAULT_GEMINI_MODEL, DEFAULT_MCP_URL
from rdf_spanner_translator.parser import validate_rdf_file
from rdf_spanner_translator.translator import (
    translate_ontology, 
    self_correct_ddl, 
    audit_spanner_schema, 
    extract_validation_score
)
from rdf_spanner_translator.validator import validate_ddl, check_database_existence
from rdf_spanner_translator.query_verifier import run_query_verification

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
@click.option("--model", "-m", default=DEFAULT_GEMINI_MODEL, envvar="GEMINI_MODEL", help=f"Gemini model to use (default: {DEFAULT_GEMINI_MODEL}).")
def translate(input, shacl, output, model):
    """Translate OWL ontology (Turtle) to Spanner Graph DDL offline."""
    console.print(Panel.fit(f"[bold blue]Translating Ontology (Offline)[/bold blue]\nInput: {input}\nSHACL: {shacl}\nOutput: {output}", title="Gemini Translator"))
    
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
@click.option("--input", "-i", type=click.Path(exists=True), default=None, help="Path to input OWL/Turtle file (required for semantic and query validation).")
@click.option("--ddl", "-d", type=click.Path(exists=True), required=True, help="Path to generated Spanner SQL DDL file.")
@click.option("--shacl", "-s", type=click.Path(exists=True), default=None, help="Path to optional SHACL shapes Turtle file.")
@click.option("--database", "--db", envvar="SPANNER_DATABASE", default=None, help="Full Cloud Spanner database resource path.")
@click.option("--output", "-o", type=click.Path(), default=None, help="Path to output markdown report file.")
@click.option("--mode", type=click.Choice(["all", "syntax", "semantic", "queries"], case_sensitive=False), default="all", help="Validation mode/tier to run.")
@click.option("--syntax-only", is_flag=True, help="Shortcut for --mode syntax.")
@click.option("--semantic-only", is_flag=True, help="Shortcut for --mode semantic.")
@click.option("--queries-only", is_flag=True, help="Shortcut for --mode queries.")
@click.option("--mcp-url", "-u", default=DEFAULT_MCP_URL, envvar="SPANNER_REMOTE_MCP_URL", help="URL of Remote Spanner MCP Server.")
@click.option("--mcp-tool", "-t", envvar="SPANNER_MCP_TOOL_NAME", help="Name of tool on MCP server.")
@click.option("--model", "-m", default=DEFAULT_GEMINI_MODEL, envvar="GEMINI_MODEL", help=f"Gemini model to use for audits (default: {DEFAULT_GEMINI_MODEL}).")
def validate(input, ddl, shacl, database, output, mode, syntax_only, semantic_only, queries_only, mcp_url, mcp_tool, model):
    """Validate Spanner Graph DDL across Syntax, Semantic Scorecard, and Dynamic Queries."""
    # Resolve active validation mode
    if syntax_only:
        active_mode = "syntax"
    elif semantic_only:
        active_mode = "semantic"
    elif queries_only:
        active_mode = "queries"
    else:
        active_mode = mode.lower()
        
    console.print(Panel.fit(
        f"[bold purple]Spanner Graph Schema Validator[/bold purple]\n"
        f"Mode: [bold]{active_mode.upper()}[/bold]\n"
        f"DDL File: {ddl}\n"
        f"Source Ontology: {input or 'N/A'}\n"
        f"Database: {database or 'N/A'}",
        title="Spanner Validator"
    ))
    
    # ----------------------------------------------------
    # Tier 1: Syntactic DDL Validation on Spanner MCP
    # ----------------------------------------------------
    if active_mode in ("all", "syntax"):
        console.print("\n[bold cyan]─── Tier 1: Dialect & Syntactic Validation ───[/bold cyan]")
        if not database:
            if active_mode == "syntax":
                console.print("[bold red]Error:[/bold red] --database is required for syntax validation.")
                raise click.Abort()
            else:
                console.print("[yellow]Skipping Tier 1: No --database provided.[/yellow]")
        else:
            with open(ddl, "r") as f:
                ddl_content = f.read()
            with console.status("[cyan]Validating DDL syntax on Cloud Spanner..."):
                success, msg = validate_ddl(ddl_content, mcp_url, mcp_tool, database)
            if success:
                console.print(f"[bold green]✓ Tier 1 Passed:[/bold green] DDL syntax compiles cleanly on Spanner.\n[dim]{msg}[/dim]")
            else:
                console.print(f"[bold red]✗ Tier 1 Failed:[/bold red]\n[red]{msg}[/red]")
                if active_mode == "syntax":
                    raise click.Abort()

    # ----------------------------------------------------
    # Tier 2: Static Semantic Validation Scorecard
    # ----------------------------------------------------
    if active_mode in ("all", "semantic"):
        console.print("\n[bold cyan]─── Tier 2: Semantic Validation & Scorecard ───[/bold cyan]")
        if not input:
            console.print("[bold red]Error:[/bold red] --input (source ontology .ttl) is required for semantic validation.")
            raise click.Abort()
            
        with open(input, "r") as f:
            ttl_content = f.read()
        with open(ddl, "r") as f:
            ddl_content = f.read()
            
        shacl_content = None
        if shacl:
            with open(shacl, "r") as f:
                shacl_content = f.read()
                
        with console.status("[yellow]Auditing schema against 7 semantic validation dimensions..."):
            report = audit_spanner_schema(
                ttl_content=ttl_content,
                ddl_content=ddl_content,
                shacl_content=shacl_content,
                model_name=model
            )
            
        report_file = output or f"output/{os.path.basename(input)[:-4] if input.endswith('.ttl') else 'schema'}_validation_report.md"
        rep_dir = os.path.dirname(os.path.abspath(report_file))
        if rep_dir:
            os.makedirs(rep_dir, exist_ok=True)
        with open(report_file, "w") as f:
            f.write(report)
            
        status, score = extract_validation_score(report)
        status_color = "green" if status == "PASS" else ("yellow" if status == "WARN" else "red")
        console.print(f"[{status_color}]✓ Tier 2 Passed: Semantic Audit {status} ({score})[/{status_color}]")
        console.print(f"Executive scorecard saved to [bold cyan]{report_file}[/bold cyan]")

    # ----------------------------------------------------
    # Tier 3: Dynamic Mock Data & Live GQL Query Execution
    # ----------------------------------------------------
    if active_mode in ("all", "queries"):
        console.print("\n[bold cyan]─── Tier 3: Dynamic Data & GQL Query Verification ───[/bold cyan]")
        if not input or not database:
            if active_mode == "queries":
                console.print("[bold red]Error:[/bold red] Both --input and --database are required for query verification.")
                raise click.Abort()
            else:
                console.print("[yellow]Skipping Tier 3: --input or --database not provided.[/yellow]")
        else:
            stem = os.path.basename(input)[:-4] if (input and input.endswith('.ttl')) else 'schema'
            out_dir = os.path.dirname(ddl) if ddl else "output"
            if not out_dir:
                out_dir = "output"
            query_report_file = output if active_mode == "queries" else os.path.join(out_dir, f"{stem}_query_report.md")
            with console.status("[yellow]Synthesizing mock data, executing DML, and running 4 GQL queries..."):
                all_passed, report_md = run_query_verification(
                    ttl_path=input,
                    ddl_path=ddl,
                    database=database,
                    shacl_path=shacl,
                    mcp_url=mcp_url,
                    model_name=model,
                    output_report=query_report_file
                )
            status_str = "SUCCESS (4/4 Queries Passed)" if all_passed else "WARNING (Some queries encountered issues)"
            status_color = "green" if all_passed else "yellow"
            console.print(f"[{status_color}]✓ Verification Complete: {status_str}[/{status_color}]")
            console.print(f"Executive query report saved to [bold cyan]{query_report_file}[/bold cyan]")


def discover_ontologies(dir_path: str) -> list[dict]:
    """Discovers all Turtle ontologies and companion SHACL shapes in a directory or directory tree."""
    items = []
    
    # Check if direct flat directory (like tests/ontologies/)
    flat_ttls = sorted(glob.glob(os.path.join(dir_path, "*.ttl")))
    if flat_ttls:
        for uttl in flat_ttls:
            base_name = os.path.basename(uttl)
            if base_name.endswith("_shacl.ttl") or base_name == "shacl.ttl":
                continue
            stem = base_name[:-4]
            companion_shacl = os.path.join(dir_path, f"{stem}_shacl.ttl")
            if not os.path.exists(companion_shacl):
                companion_shacl = None
            items.append({
                "name": stem,
                "stem": stem,
                "ttl": uttl,
                "shacl": companion_shacl,
                "is_unit": "test" in dir_path.lower()
            })
        return items

    # Check for domain subdirectories (like examples/<domain>/)
    for entry in sorted(os.listdir(dir_path)):
        sub_dir = os.path.join(dir_path, entry)
        if os.path.isdir(sub_dir):
            ont_file = os.path.join(sub_dir, f"{entry}.ttl")
            if os.path.exists(ont_file):
                shacl_file = os.path.join(sub_dir, "shacl.ttl")
                items.append({
                    "name": f"Example: {entry}",
                    "stem": entry,
                    "ttl": ont_file,
                    "shacl": shacl_file if os.path.exists(shacl_file) else None,
                    "is_unit": False
                })
    return items


def cleanup_spanner_databases(databases: list[str], instance_path: str, auto_delete: bool = True):
    """Deletes temporary Spanner databases created during testing, or prints cleanup commands."""
    if not databases or not instance_path:
        return
        
    parts = instance_path.split("/")
    if len(parts) >= 4 and parts[0] == "projects" and parts[2] == "instances":
        project_id = parts[1]
        instance_id = parts[3]
    else:
        return
        
    if auto_delete:
        console.print("\n[bold yellow]Cleaning up created test databases...[/bold yellow]")
        for db in databases:
            console.print(f"Deleting database [cyan]{db}[/cyan]...")
            cmd = [
                "gcloud", "spanner", "databases", "delete", db,
                "--instance", instance_id,
                "--project", project_id,
                "--quiet"
            ]
            subprocess.run(cmd, capture_output=True)
        console.print("[bold green]✓ Database cleanup complete![/bold green]")
    else:
        console.print("\n[bold yellow]CLEANUP INSTRUCTIONS (Database Deletion Skipped):[/bold yellow]")
        console.print("Execute the following to delete created test databases:")
        console.print("```bash")
        for db in databases:
            console.print(f"gcloud spanner databases delete {db} --instance={instance_id} --project={project_id} --quiet")
        console.print("```")


@main.command()
@click.option("--input", "-i", type=click.Path(exists=True), required=True, help="Path to input OWL/Turtle file or directory of ontologies.")
@click.option("--shacl", "-s", type=click.Path(exists=True), default=None, help="Path to optional SHACL shapes Turtle file.")
@click.option("--output", "-o", type=click.Path(), default=None, help="Path to output SQL file (or output directory in batch mode).")
@click.option("--report", "-r", type=click.Path(), default=None, help="Optional path to output executive semantic validation report.")
@click.option("--verify-queries/--no-verify-queries", default=False, help="Enable live data ingestion and GQL query verification.")
@click.option("--query-report", type=click.Path(), default=None, help="Optional path to output dynamic query execution report.")
@click.option("--instance", envvar="SPANNER_INSTANCE", help="Cloud Spanner instance path (projects/<project>/instances/<instance>).")
@click.option("--database", "--db", envvar="SPANNER_DATABASE", help="Full Cloud Spanner database resource path.")
@click.option("--cleanup/--no-cleanup", default=True, help="Automatically delete temporary test databases created during batch execution.")
@click.option("--bundle-examples/--no-bundle-examples", default=False, help="Bundle verified schemas & reports into examples/<domain>/.")
@click.option("--mcp-url", "-u", default=DEFAULT_MCP_URL, envvar="SPANNER_REMOTE_MCP_URL", help="URL of Remote Spanner MCP Server.")
@click.option("--mcp-tool", "-t", envvar="SPANNER_MCP_TOOL_NAME", default="create_database", help="Name of tool on MCP server.")
@click.option("--self-correct/--no-self-correct", default=True, help="Enable self-correction loop.")
@click.option("--model", "-m", default=DEFAULT_GEMINI_MODEL, envvar="GEMINI_MODEL", help=f"Gemini model to use (default: {DEFAULT_GEMINI_MODEL}).")
def pipeline(input, shacl, output, report, verify_queries, query_report, instance, database, cleanup, bundle_examples, mcp_url, mcp_tool, self_correct, model):
    """End-to-End: Translate OWL ontology, validate syntax via MCP, self-correct if needed, and generate reports."""
    
    # ---------------------------------------------------------
    # Batch Execution Mode (When --input is a directory)
    # ---------------------------------------------------------
    if os.path.isdir(input):
        discovered = discover_ontologies(input)
        if not discovered:
            console.print(f"[yellow]No Turtle (.ttl) ontologies found in directory: {input}[/yellow]")
            return
            
        target_instance = instance
        if not target_instance and database:
            parts = database.split("/")
            if len(parts) >= 4:
                target_instance = "/".join(parts[:4])
                
        console.print(Panel.fit(
            f"[bold green]Running Batch Spanner Graph Pipeline[/bold green]\n"
            f"Directory: {input}\n"
            f"Ontologies Discovered: {len(discovered)}\n"
            f"Spanner Instance: {target_instance or 'N/A'}\n"
            f"Verify Queries: {verify_queries}\n"
            f"Cleanup Databases: {cleanup}",
            title="Batch Spanner Pipeline"
        ))
        
        results = []
        created_databases = []
        
        for item in discovered:
            stem = item["stem"]
            ttl_path = item["ttl"]
            shacl_path = item["shacl"]
            is_unit = item["is_unit"]
            name = item["name"]
            
            category_dir = "unit_tests" if is_unit else "examples"
            os.makedirs(f"output/{category_dir}", exist_ok=True)
            
            out_schema = f"output/{category_dir}/{stem}_schema.sql"
            out_report = f"output/{category_dir}/{stem}_validation_report.md"
            out_query_report = f"output/{category_dir}/{stem}_query_report.md"
            
            db_id = f"t_{uuid.uuid4().hex[:8]}"
            db_path = f"{target_instance}/databases/{db_id}" if target_instance else database
            if target_instance:
                created_databases.append(db_id)
                
            console.print(f"[blue]Processing [bold]{name}[/bold] -> DB: {db_id}...[/blue]")
            
            # Read TTL & SHACL
            with open(ttl_path, "r") as f:
                ttl_content = f.read()
            shacl_content = None
            if shacl_path and os.path.exists(shacl_path):
                with open(shacl_path, "r") as f:
                    shacl_content = f.read()
                    
            # 1. Translate
            with console.status(f"[yellow]Translating {stem}..."):
                current_ddl = translate_ontology(ttl_content, shacl_content=shacl_content, model_name=model)
                
            # 2. Validate & Self-Correct
            success = False
            attempts = 0
            err_msg = ""
            
            if db_path and mcp_url:
                success, msg = validate_ddl(current_ddl, mcp_url, "create_database", db_path)
                if not success and self_correct:
                    max_attempts = 3
                    attempt = 1
                    current_error = msg
                    while attempt <= max_attempts and not success:
                        attempts = attempt
                        with console.status(f"[yellow]Self-correction attempt {attempt}/{max_attempts} for {stem}..."):
                            current_ddl = self_correct_ddl(ttl_content, current_ddl, current_error, shacl_content=shacl_content, model_name=model)
                            exists, _ = check_database_existence(mcp_url, "create_database", db_path)
                            active_tool = "update_database_schema" if exists else "create_database"
                            success, msg = validate_ddl(current_ddl, mcp_url, active_tool, db_path)
                        if not success:
                            current_error = msg
                            attempt += 1
                if not success:
                    err_msg = msg
            else:
                success = True
                
            # Save DDL
            with open(out_schema, "w") as f:
                f.write(current_ddl)
                
            # 3. Semantic Audit
            sem_score = "N/A"
            if success:
                try:
                    with console.status(f"[yellow]Auditing semantics for {stem}..."):
                        rep = audit_spanner_schema(ttl_content, current_ddl, shacl_content, model_name=model)
                    with open(out_report, "w") as f:
                        f.write(rep)
                    status, score = extract_validation_score(rep)
                    sem_score = score
                except Exception:
                    sem_score = "Reviewed"
                    
            # 4. Dynamic Query Verification
            query_status = "N/A"
            if success and verify_queries and db_path:
                try:
                    with console.status(f"[cyan]Executing dynamic GQL queries for {stem}..."):
                        q_pass, _ = run_query_verification(
                            ttl_path=ttl_path,
                            ddl_path=out_schema,
                            database=db_path,
                            shacl_path=shacl_path,
                            mcp_url=mcp_url,
                            model_name=model,
                            output_report=out_query_report
                        )
                    query_status = "PASS (4/4)" if q_pass else "WARN"
                except Exception:
                    query_status = "ERROR"
                    
            # Bundle into examples/<domain>/ if requested
            if success and bundle_examples and not is_unit:
                domain_dir = os.path.dirname(ttl_path)
                shutil.copyfile(out_schema, os.path.join(domain_dir, "schema.sql"))
                if os.path.exists(out_report):
                    shutil.copyfile(out_report, os.path.join(domain_dir, "validation_report.md"))
                if os.path.exists(out_query_report):
                    shutil.copyfile(out_query_report, os.path.join(domain_dir, "query_report.md"))
                    
            status_str = "PASS" if success else "FAIL"
            results.append({
                "name": name,
                "status": status_str,
                "semantic_score": sem_score,
                "query_status": query_status,
                "attempts": attempts,
                "report": out_report if success else err_msg
            })
            
            if success:
                console.print(f"[green]✓ {name} passed (Syntax: PASS, Semantics: {sem_score})[/green]\n")
            else:
                console.print(f"[red]✗ {name} failed: {err_msg}[/red]\n")
                
        # Print Summary Table
        table = Table(title="Batch Spanner Graph Pipeline Summary")
        table.add_column("Ontology Target", style="cyan")
        table.add_column("DDL Syntax", style="bold")
        table.add_column("Semantic Score", justify="center", style="green")
        if verify_queries:
            table.add_column("GQL Queries", justify="center", style="magenta")
        table.add_column("Correction Attempts", justify="right", style="magenta")
        table.add_column("Report / Details", style="dim")
        
        for r in results:
            status_style = "green" if r["status"] == "PASS" else "red"
            score_style = "bold green" if "%" in r["semantic_score"] and not r["semantic_score"].startswith("0") else "yellow"
            row = [
                r["name"],
                f"[{status_style}]{r['status']}[/{status_style}]",
                f"[{score_style}]{r['semantic_score']}[/{score_style}]",
            ]
            if verify_queries:
                row.append(r["query_status"])
            row.extend([
                str(r["attempts"]),
                r["report"]
            ])
            table.add_row(*row)
            
        console.print(table)
        
        # Cleanup databases
        if target_instance and created_databases:
            cleanup_spanner_databases(created_databases, target_instance, auto_delete=cleanup)
        return

    # ---------------------------------------------------------
    # Single File Pipeline Execution Mode
    # ---------------------------------------------------------
    stem = os.path.splitext(os.path.basename(input))[0] if input.endswith('.ttl') else 'schema'
    if "test" in input.lower():
        default_dir = "output/unit_tests"
    elif "example" in input.lower():
        default_dir = "output/examples"
    else:
        default_dir = "output"
        
    target_output = output or os.path.join(default_dir, f"{stem}_schema.sql")
    target_report = report or os.path.join(default_dir, f"{stem}_validation_report.md")
    target_query_report = query_report or os.path.join(default_dir, f"{stem}_query_report.md")

    temp_db_created = False
    temp_db_id = None
    target_database = database
    if not target_database and instance:
        temp_db_id = f"t_{uuid.uuid4().hex[:8]}"
        target_database = f"{instance.rstrip('/')}/databases/{temp_db_id}"
        temp_db_created = True

    console.print(Panel.fit(
        f"[bold green]Running End-to-End Spanner Graph Pipeline[/bold green]\n"
        f"Input: {input}\n"
        f"SHACL: {shacl or 'None'}\n"
        f"Output: {target_output}\n"
        f"Report: {target_report}\n"
        f"Database: {target_database or 'N/A'}\n"
        f"Self-Correct: {self_correct}\n"
        f"Verify Queries: {verify_queries}",
        title="Spanner Graph Pipeline"
    ))
    
    # Ensure output parent directory exists
    output_dir = os.path.dirname(os.path.abspath(target_output))
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
        
    # Pre-validation: Verify database state via MCP before translating
    if target_database and mcp_url and not temp_db_created:
        with console.status("[cyan]Verifying target database state..."):
            exists, err = check_database_existence(mcp_url, mcp_tool, target_database)
            if err:
                console.print(f"[yellow]Pre-validation warning: Could not verify database state ({err}). Proceeding...[/yellow]")
            elif exists is not None:
                if mcp_tool == "create_database" and exists:
                    console.print(f"[bold red]Error:[/bold red] Database already exists: {target_database}.\nChoose a new database ID or use the 'update_database_schema' tool.")
                    raise click.Abort()
                elif mcp_tool == "update_database_schema" and not exists:
                    console.print(f"[bold red]Error:[/bold red] Database does not exist: {target_database}.\nCreate the database first or use the 'create_database' tool.")
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
        with open(target_output, "w") as f:
            f.write(ddl)
        console.print(f"[yellow]! Validation skipped (no MCP configuration provided). Saved DDL to {target_output}[/yellow]")
        return
        
    def _generate_reports(target_ddl):
        if target_report:
            try:
                with console.status("[yellow]Auditing schema & generating semantic validation report..."):
                    rep = audit_spanner_schema(ttl_content, target_ddl, shacl_content, model_name=model)
                rep_dir = os.path.dirname(os.path.abspath(target_report))
                if rep_dir:
                    os.makedirs(rep_dir, exist_ok=True)
                with open(target_report, "w") as f:
                    f.write(rep)
                status, score = extract_validation_score(rep)
                status_color = "green" if status == "PASS" else ("yellow" if status == "WARN" else "red")
                console.print(f"[{status_color}]✓ Semantic Validation Report generated: {status} ({score}) -> {target_report}[/{status_color}]")
            except Exception as ex:
                console.print(f"[yellow]Warning: Could not generate semantic report: {ex}[/yellow]")
                
        if verify_queries and target_database:
            try:
                rep_dir = os.path.dirname(os.path.abspath(target_query_report))
                if rep_dir:
                    os.makedirs(rep_dir, exist_ok=True)
                with console.status("[yellow]Executing dynamic mock data ingestion & GQL queries..."):
                    all_passed, _ = run_query_verification(
                        ttl_path=input,
                        ddl_path=target_output,
                        database=target_database,
                        shacl_path=shacl,
                        mcp_url=mcp_url,
                        model_name=model,
                        output_report=target_query_report
                    )
                status_str = "SUCCESS" if all_passed else "WARNING (Some queries failed)"
                status_color = "green" if all_passed else "yellow"
                console.print(f"[{status_color}]✓ Dynamic GQL Query Verification Complete: {status_str} -> {target_query_report}[/{status_color}]")
            except Exception as ex:
                console.print(f"[yellow]Warning: Could not execute query verification: {ex}[/yellow]")

    try:
        # Run first validation pass
        with console.status("[cyan]Connecting to MCP server and executing DDL..."):
            success, msg = validate_ddl(ddl, mcp_url, mcp_tool, target_database)
            
        if success:
            with open(target_output, "w") as f:
                f.write(ddl)
            console.print(f"[bold green]✓ DDL validation successful![/bold green] Saved verified DDL to {target_output}")
            _generate_reports(ddl)
            if temp_db_created and instance:
                cleanup_spanner_databases([temp_db_id], instance, auto_delete=cleanup)
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
            with open(target_output, "w") as f:
                f.write(ddl)
            console.print(f"[yellow]Self-correction disabled. Saved invalid DDL to {target_output}[/yellow]")
            if temp_db_created and instance:
                cleanup_spanner_databases([temp_db_id], instance, auto_delete=cleanup)
            raise click.Abort()
            
        # 4. Self-correction loop
        max_attempts = 3
        attempt = 1
        current_ddl = ddl
        current_error = msg
        
        while attempt <= max_attempts:
            console.print(f"\n[bold yellow]Starting Self-Correction Attempt {attempt}/{max_attempts}...[/bold yellow]")
            
            with console.status(f"[yellow]Requesting correction from Gemini..."):
                current_ddl = self_correct_ddl(ttl_content, current_ddl, current_error, shacl_content=shacl_content, model_name=model)
                
            console.print(f"[yellow]Executing corrected DDL...[/yellow]")
            with console.status("[cyan]Re-validating corrected DDL..."):
                if mcp_tool == "create_database" and target_database and mcp_url:
                    exists, _ = check_database_existence(mcp_url, mcp_tool, target_database)
                    active_tool = "update_database_schema" if exists else "create_database"
                else:
                    active_tool = mcp_tool
                success, msg = validate_ddl(current_ddl, mcp_url, active_tool, target_database)
                
            attempt_info = {
                "attempt": attempt,
                "corrected_ddl": current_ddl,
                "error": msg if not success else None
            }
            telemetry["correction_attempts"].append(attempt_info)
                
            if success:
                with open(target_output, "w") as f:
                    f.write(current_ddl)
                console.print(f"[bold green]✓ Self-correction successful! DDL is now valid.[/bold green] Saved verified DDL to {target_output}")
                
                telemetry["final_status"] = "SUCCESS"
                telemetry["final_ddl"] = current_ddl
                save_telemetry(input, telemetry)
                _generate_reports(current_ddl)
                if temp_db_created and instance:
                    cleanup_spanner_databases([temp_db_id], instance, auto_delete=cleanup)
                return
                
            console.print(f"[bold red]✗ Corrected DDL validation failed![/bold red]")
            console.print(f"[red]Error Message:[/red]\n{msg}")
            current_error = msg
            attempt += 1
            
        with open(target_output, "w") as f:
            f.write(current_ddl)
        console.print(f"[bold red]✗ Failed to generate a valid schema after {max_attempts} correction attempts.[/bold red] Saved last attempt to {target_output}")
        
        telemetry["final_status"] = "FAILURE"
        telemetry["final_ddl"] = current_ddl
        save_telemetry(input, telemetry)
        if temp_db_created and instance:
            cleanup_spanner_databases([temp_db_id], instance, auto_delete=cleanup)
        raise click.Abort()
        
    except Exception as e:
        console.print(f"[bold red]Error during pipeline execution:[/bold red] {e}")
        if temp_db_created and instance:
            cleanup_spanner_databases([temp_db_id], instance, auto_delete=cleanup)
        raise click.Abort()


if __name__ == "__main__":
    main()
