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
        
    # Parse target domains if passed as command line arguments
    targets = []
    if len(sys.argv) > 1:
        for arg in sys.argv[1:]:
            targets.extend([t.strip() for t in arg.split(",") if t.strip()])
            
    # Discover example ontologies (specifically examples/<domain>/<domain>.ttl)
    ttl_files = []
    if os.path.exists("examples"):
        for d in sorted(os.listdir("examples")):
            dir_path = os.path.join("examples", d)
            if os.path.isdir(dir_path):
                # Filter by targets if specified
                if targets and d not in targets:
                    continue
                ont_file = os.path.join(dir_path, f"{d}.ttl")
                if os.path.exists(ont_file):
                    ttl_files.append(ont_file)
                    
    if not ttl_files:
        console.print("[bold yellow]No matching Turtle (.ttl) ontology files found in examples/ subdirectories.[/bold yellow]")
        sys.exit(0)
        
    console.print(f"[bold green]Starting integration tests for {len(ttl_files)} domains...[/bold green]\n")
    
    results = []
    created_databases = []
    
    # Run test loop
    for ttl_path in sorted(ttl_files):
        domain = os.path.basename(os.path.dirname(ttl_path))
        
        # 1. Test Case: Without SHACL
        db_id_nsh = f"t_nsh_{uuid.uuid4().hex[:8]}"
        db_path_nsh = f"{spanner_instance}/databases/{db_id_nsh}"
        out_path_nsh = f"output/{domain}_schema.sql"
        
        console.print(f"[blue]Processing [bold]{domain} (No SHACL)[/bold] -> DB: {db_id_nsh}...[/blue]")
        
        env = os.environ.copy()
        env["SPANNER_DATABASE"] = db_path_nsh
        
        cmd_nsh = [
            ".venv/bin/rdf-spanner-translator", "run",
            "--input", ttl_path,
            "--output", out_path_nsh,
            "--mcp-url", "https://spanner.googleapis.com/mcp",
            "--mcp-tool", "create_database"
        ]
        
        result_nsh = subprocess.run(cmd_nsh, capture_output=True, text=True, env=env)
        attempts_nsh = result_nsh.stdout.count("Starting Self-Correction Attempt")
        success_nsh = (result_nsh.returncode == 0)
        created_databases.append(db_id_nsh)
        
        if success_nsh:
            results.append({
                "file": f"{domain} (No SHACL)",
                "status": "PASS",
                "attempts": attempts_nsh,
                "error": None
            })
            console.print(f"[green]✓ {domain} (No SHACL) passed in {attempts_nsh} correction attempts.[/green]\n")
        else:
            error_details = "Unknown execution error"
            for line in result_nsh.stdout.split("\n"):
                if "Error Message:" in line or "Error:" in line or "Spanner" in line:
                    error_details = line.strip()
            results.append({
                "file": f"{domain} (No SHACL)",
                "status": "FAIL",
                "attempts": attempts_nsh,
                "error": error_details
            })
            console.print(f"[red]✗ {domain} (No SHACL) failed. Error: {error_details}[/red]\n")
            
        # 2. Test Case: With SHACL (if shacl.ttl exists)
        shacl_path = os.path.join(os.path.dirname(ttl_path), "shacl.ttl")
        if os.path.exists(shacl_path):
            db_id_sh = f"t_sh_{uuid.uuid4().hex[:8]}"
            db_path_sh = f"{spanner_instance}/databases/{db_id_sh}"
            out_path_sh = f"output/{domain}_with_shacl_schema.sql"
            
            console.print(f"[blue]Processing [bold]{domain} (With SHACL)[/bold] -> DB: {db_id_sh}...[/blue]")
            
            env = os.environ.copy()
            env["SPANNER_DATABASE"] = db_path_sh
            
            cmd_sh = [
                ".venv/bin/rdf-spanner-translator", "run",
                "--input", ttl_path,
                "--shacl", shacl_path,
                "--output", out_path_sh,
                "--mcp-url", "https://spanner.googleapis.com/mcp",
                "--mcp-tool", "create_database"
            ]
            
            result_sh = subprocess.run(cmd_sh, capture_output=True, text=True, env=env)
            attempts_sh = result_sh.stdout.count("Starting Self-Correction Attempt")
            success_sh = (result_sh.returncode == 0)
            created_databases.append(db_id_sh)
            
            if success_sh:
                results.append({
                    "file": f"{domain} (With SHACL)",
                    "status": "PASS",
                    "attempts": attempts_sh,
                    "error": None
                })
                console.print(f"[green]✓ {domain} (With SHACL) passed in {attempts_sh} correction attempts.[/green]\n")
            else:
                error_details = "Unknown execution error"
                for line in result_sh.stdout.split("\n"):
                    if "Error Message:" in line or "Error:" in line or "Spanner" in line:
                        error_details = line.strip()
                results.append({
                    "file": f"{domain} (With SHACL)",
                    "status": "FAIL",
                    "attempts": attempts_sh,
                    "error": error_details
                })
                console.print(f"[red]✗ {domain} (With SHACL) failed. Error: {error_details}[/red]\n")
                
    # Summary table
    table = Table(title="Ontology Translation & Validation Summary")
    table.add_column("Test Case", style="cyan")
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
    
    # Automatically delete all created databases
    if created_databases:
        console.print("[bold yellow]Cleaning up created test databases...[/bold yellow]")
        for db in created_databases:
            console.print(f"Deleting database [cyan]{db}[/cyan]...")
            cmd = [
                "gcloud", "spanner", "databases", "delete", db,
                "--instance", instance_id,
                "--project", project_id,
                "--quiet"
            ]
            subprocess.run(cmd, capture_output=True)
        console.print("[bold green]✓ Database cleanup complete![/bold green]")
        
if __name__ == "__main__":
    run_integration_tests()
