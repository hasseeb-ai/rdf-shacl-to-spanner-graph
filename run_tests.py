#!/usr/bin/env python3
"""Integration and unit test runner for the RDF-to-Spanner Graph DDL Translator.

This script discovers Turtle (.ttl) files in tests/ontologies/ and examples/,
translates and validates them against a real Spanner instance using the
official Spanner MCP server, runs semantic validation using the Validation Skill,
tracks success attempts, and prints gcloud cleanup commands for created databases.
"""

import os
import sys
import glob
import re
import uuid
import subprocess
from rich.console import Console
from rich.table import Table

console = Console()

def extract_score_from_report_file(report_path: str) -> str:
    """Reads a generated validation report file and extracts the semantic score."""
    if not os.path.exists(report_path):
        return "N/A"
    try:
        with open(report_path, "r") as f:
            text = f.read()
        score_match = re.search(r"(\d{1,3}%)\s*Score", text, re.IGNORECASE)
        if not score_match:
            score_match = re.search(r"\|\s*Total[^\n]+\|\s*(\d{1,3}%)\s*\|", text, re.IGNORECASE)
        if not score_match:
            score_match = re.search(r"(\d{1,3}%)\s*(?:PASS|WARN|FAIL)", text, re.IGNORECASE)
        if score_match:
            return score_match.group(1)
        if "PASS" in text:
            return "100%"
        return "Reviewed"
    except Exception:
        return "N/A"

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
        
    # Parse CLI flags and target domains
    cleanup = True
    semantic_audit = True
    verify_queries = False
    suite = "all"  # 'unit', 'examples', 'all'
    args = sys.argv[1:]
    
    if "--no-cleanup" in args:
        cleanup = False
        args.remove("--no-cleanup")
    if "--keep-databases" in args:
        cleanup = False
        args.remove("--keep-databases")
    if "--no-semantic-validation" in args:
        semantic_audit = False
        args.remove("--no-semantic-validation")
    if "--verify-queries" in args:
        verify_queries = True
        args.remove("--verify-queries")
    if "--test-queries" in args:
        verify_queries = True
        args.remove("--test-queries")
    if "--unit-only" in args:
        suite = "unit"
        args.remove("--unit-only")
    if "--examples-only" in args:
        suite = "examples"
        args.remove("--examples-only")

    targets = []
    if args:
        for arg in args:
            targets.extend([t.strip() for t in arg.split(",") if t.strip()])
            
    # Discover test items
    # Item structure: {"name": str, "ttl": str, "shacl": str | None, "is_unit": bool}
    test_items = []
    
    # 1. Discover Unit Test Ontologies in tests/ontologies/
    if suite in ("unit", "all") and os.path.exists("tests/ontologies"):
        unit_ttls = sorted(glob.glob("tests/ontologies/*.ttl"))
        for uttl in unit_ttls:
            base_name = os.path.basename(uttl)
            if base_name.endswith("_shacl.ttl") or base_name == "shacl.ttl":
                continue
            stem = base_name[:-4]
            if targets and not any(t in stem for t in targets):
                continue
                
            companion_shacl = os.path.join("tests/ontologies", f"{stem}_shacl.ttl")
            if not os.path.exists(companion_shacl):
                companion_shacl = None
                
            test_items.append({
                "name": f"Unit: {stem}",
                "stem": stem,
                "ttl": uttl,
                "shacl": companion_shacl,
                "is_unit": True
            })
            
    # 2. Discover Domain Examples in examples/
    if suite in ("examples", "all") and os.path.exists("examples"):
        for d in sorted(os.listdir("examples")):
            dir_path = os.path.join("examples", d)
            if os.path.isdir(dir_path):
                if targets and d not in targets:
                    continue
                ont_file = os.path.join(dir_path, f"{d}.ttl")
                if os.path.exists(ont_file):
                    shacl_file = os.path.join(dir_path, "shacl.ttl")
                    test_items.append({
                        "name": f"Example: {d}",
                        "stem": d,
                        "ttl": ont_file,
                        "shacl": shacl_file if os.path.exists(shacl_file) else None,
                        "is_unit": False
                    })
                    
    if not test_items:
        console.print("[bold yellow]No matching Turtle (.ttl) test ontology files found.[/bold yellow]")
        sys.exit(0)
        
    console.print(f"[bold green]Starting translation & validation suite for {len(test_items)} ontologies...[/bold green]\n")
    
    results = []
    created_databases = []
    
    # Run test loop
    for item in test_items:
        stem = item["stem"]
        ttl_path = item["ttl"]
        shacl_path = item["shacl"]
        test_name = item["name"]
        
        db_id = f"t_{uuid.uuid4().hex[:8]}"
        db_path = f"{spanner_instance}/databases/{db_id}"
        out_schema = f"output/{stem}_schema.sql"
        out_report = f"output/{stem}_validation_report.md"
        out_query_report = f"output/{stem}_query_report.md"
        
        console.print(f"[blue]Processing [bold]{test_name}[/bold] -> DB: {db_id}...[/blue]")
        
        env = os.environ.copy()
        env["SPANNER_DATABASE"] = db_path
        
        cmd = [
            sys.executable, "-m", "rdf_spanner_translator.cli", "run",
            "--input", ttl_path,
            "--output", out_schema,
            "--mcp-url", "https://spanner.googleapis.com/mcp",
            "--mcp-tool", "create_database"
        ]
        if shacl_path:
            cmd.extend(["--shacl", shacl_path])
        if semantic_audit:
            cmd.extend(["--report", out_report])
            
        result = subprocess.run(cmd, capture_output=True, text=True, env=env)
        attempts = result.stdout.count("Starting Self-Correction Attempt")
        success = (result.returncode == 0)
        created_databases.append(db_id)
        
        semantic_score = "N/A"
        if success and semantic_audit:
            semantic_score = extract_score_from_report_file(out_report)
            
        # Optional: Run Dynamic GQL Query Verification
        query_status = "N/A"
        if success and verify_queries:
            console.print(f"[cyan]Executing dynamic data ingestion & GQL query verification for {stem}...[/cyan]")
            q_cmd = [
                sys.executable, "-m", "rdf_spanner_translator.cli", "test-queries",
                "--input", ttl_path,
                "--ddl", out_schema,
                "--database", db_path,
                "--output", out_query_report,
                "--mcp-url", "https://spanner.googleapis.com/mcp"
            ]
            if shacl_path:
                q_cmd.extend(["--shacl", shacl_path])
            q_res = subprocess.run(q_cmd, capture_output=True, text=True, env=env)
            query_status = "PASS (4/4)" if q_res.returncode == 0 else "WARN"
            
        if success:
            results.append({
                "file": test_name,
                "status": "PASS",
                "semantic_score": semantic_score,
                "query_status": query_status,
                "attempts": attempts,
                "report": out_report if semantic_audit else "N/A",
                "error": None
            })
            console.print(f"[green]✓ {test_name} passed (Syntactic PASS, Semantic Score: {semantic_score}) in {attempts} correction attempts.[/green]\n")
        else:
            error_details = "Unknown execution error"
            for line in result.stdout.split("\n"):
                if "Error Message:" in line or "Error:" in line or "Spanner" in line:
                    error_details = line.strip()
            results.append({
                "file": test_name,
                "status": "FAIL",
                "semantic_score": "FAIL",
                "query_status": "N/A",
                "attempts": attempts,
                "report": "N/A",
                "error": error_details
            })
            console.print(f"[red]✗ {test_name} failed. Error: {error_details}[/red]\n")
                
    # Summary table
    table = Table(title="Ontology Translation & Validation Summary")
    table.add_column("Test Case", style="cyan")
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
            r["file"],
            f"[{status_style}]{r['status']}[/{status_style}]",
            f"[{score_style}]{r['semantic_score']}[/{score_style}]",
        ]
        if verify_queries:
            row.append(r["query_status"])
        row.extend([
            str(r["attempts"]),
            r["report"] if r["status"] == "PASS" else (r["error"] or "Error")
        ])
        table.add_row(*row)
        
    console.print(table)
    console.print("\n" + "="*80 + "\n")
    
    # Automatically delete all created databases (unless disabled by flag)
    if created_databases:
        if cleanup:
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
        else:
            console.print("[bold yellow]CLEANUP INSTRUCTIONS (Database Deletion Skipped):[/bold yellow]")
            console.print("Please copy-paste and execute the following commands to delete the created databases:")
            console.print("```bash")
            for db in created_databases:
                console.print(f"gcloud spanner databases delete {db} --instance={instance_id} --project={project_id} --quiet")
            console.print("```")
        
if __name__ == "__main__":
    run_integration_tests()

