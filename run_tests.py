#!/usr/bin/env python3
"""Integration test runner for the RDF-to-Spanner Graph DDL Translator.

This script discovers all Turtle (.ttl) files in the examples directory,
translates and validates them against a real Spanner instance using the
official Spanner MCP server, tracks success attempts, and prints gcloud
cleanup commands for created databases.
"""

import os
import sys
import glob
import uuid
import subprocess
from rich.console import Console
from rich.table import Table

console = Console()

def run_integration_tests():
    # Validate environment prerequisites
    gemini_key = os.environ.get("GEMINI_API_KEY")
    if not gemini_key:
        console.print("[bold red]Error:[/bold red] GEMINI_API_KEY environment variable is not set.")
        sys.exit(1)
        
    spanner_instance = os.environ.get("SPANNER_INSTANCE")
    if not spanner_instance:
        console.print("[bold red]Error:[/bold red] SPANNER_INSTANCE environment variable is not set.")
        console.print("Please set it, e.g.:")
        console.print("  export SPANNER_INSTANCE=\"projects/my-project/instances/my-instance\"")
        sys.exit(1)
        
    # instance path format
    spanner_instance = spanner_instance.strip().rstrip("/")
    if not spanner_instance.startswith("projects/") or "/instances/" not in spanner_instance:
        console.print("[bold red]Error:[/bold red] SPANNER_INSTANCE must be in format 'projects/<project>/instances/<instance>'")
        sys.exit(1)
        
    # Get project and instance IDs for gcloud output
    parts = spanner_instance.split("/")
    project_id = parts[1]
    instance_id = parts[3]
        
    # Discover example ontologies
    ttl_files = glob.glob("examples/*.ttl")
    if not ttl_files:
        console.print("[bold yellow]No Turtle (.ttl) files found in examples/ directory.[/bold yellow]")
        sys.exit(0)
        
    console.print(f"[bold green]Starting integration tests for {len(ttl_files)} ontologies...[/bold green]\n")
    
    results = []
    created_databases = []
    
    # Run test loop
    for ttl_path in sorted(ttl_files):
        file_name = os.path.basename(ttl_path)
        file_stem = os.path.splitext(file_name)[0]
        
        # Generate a unique database name
        db_id = f"t_{uuid.uuid4().hex[:10]}"
        db_path = f"{spanner_instance}/databases/{db_id}"
        out_path = f"output/{file_stem}_schema.sql"
        
        console.print(f"[blue]Processing [bold]{file_name}[/bold] -> DB: {db_id}...[/blue]")
        
        env = os.environ.copy()
        env["SPANNER_DATABASE"] = db_path
        
        # commands to run all tests
        cmd = [
            ".venv/bin/rdf-spanner-translator", "run",
            "--input", ttl_path,
            "--output", out_path,
            "--mcp-url", "https://spanner.googleapis.com/mcp",
            "--mcp-tool", "create_database"
        ]
        
        result = subprocess.run(cmd, capture_output=True, text=True, env=env)
        
        # Parse attempts and results
        attempts = result.stdout.count("Starting Self-Correction Attempt")
        success = (result.returncode == 0)
        
        # Track the database ID
        created_databases.append(db_id)
        
        if success:
            results.append({
                "file": file_name,
                "status": "PASS",
                "attempts": attempts,
                "error": None
            })
            console.print(f"[green]✓ {file_name} passed in {attempts} correction attempts.[/green]\n")
        else:
            error_details = "Unknown execution error"
            for line in result.stdout.split("\n"):
                if "Error Message:" in line or "Error:" in line or "Spanner" in line:
                    error_details = line.strip()
            results.append({
                "file": file_name,
                "status": "FAIL",
                "attempts": attempts,
                "error": error_details
            })
            console.print(f"[red]✗ {file_name} failed. Error: {error_details}[/red]\n")
            
    # Summary table
    table = Table(title="Ontology Translation & Validation Summary")
    table.add_column("Ontology File", style="cyan")
    table.add_column("Status", style="bold")
    table.add_column("Correction Attempts", justify="right", style="magenta")
    table.add_column("Details / Failures", style="red")
    
    for r in results:
        status_style = "green" if r["status"] == "PASS" else "red"
        table.add_row(
            r["file"],
            f"[{status_style}]{r['status']}[/{status_style}]",
            str(r["attempts"]),
            r["error"] or "N/A"
        )
        
    console.print(table)
    console.print("\n" + "="*80 + "\n")
    
    # Output gcloud cleanup instructions
    if created_databases:
        console.print("[bold yellow]CLEANUP INSTRUCTIONS:[/bold yellow]")
        console.print("Please copy-paste and execute the following commands to delete the created databases:")
        console.print("```bash")
        for db in created_databases:
            console.print(f"gcloud spanner databases delete {db} --instance={instance_id} --project={project_id} --quiet")
        console.print("```")
        
if __name__ == "__main__":
    run_integration_tests()
