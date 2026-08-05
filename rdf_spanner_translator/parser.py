import os
from rdflib import Graph, RDF, OWL

def validate_rdf_file(file_path: str) -> dict:
    """Parses and validates a Turtle RDF/OWL file.
    
    Returns a dict with metadata (classes, properties, triples) or raises an exception.
    """
    if not os.path.exists(file_path):
        raise FileNotFoundError(f"Input file not found: {file_path}")
        
    g = Graph()
    try:
        # Determine format
        if file_path.endswith((".ttl", ".turtle")):
            fmt = "turtle"
        elif file_path.endswith((".xml", ".rdf")):
            fmt = "xml"
        else:
            fmt = "guess"
            
        if fmt == "guess":
            g.parse(file_path)
        else:
            g.parse(file_path, format=fmt)
    except Exception as e:
        raise ValueError(f"Failed to parse RDF file syntax: {e}")

    # Gather simple stats
    num_triples = len(g)
    
    classes = set()
    for s in g.subjects(RDF.type, OWL.Class):
        classes.add(str(s))
        
    properties = set()
    for p_type in [OWL.ObjectProperty, OWL.DatatypeProperty]:
        for s in g.subjects(RDF.type, p_type):
            properties.add(str(s))

    return {
        "triples": num_triples,
        "classes_count": len(classes),
        "properties_count": len(properties),
        "classes": sorted(list(classes)),
        "properties": sorted(list(properties)),
    }
