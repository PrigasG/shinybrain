# Analyze a full Shiny project directory

Detects entry point, resolves source() chains, parses all files, and
merges the IR into a single project model.

## Usage

``` r
analyze_shiny_project(path)
```

## Arguments

- path:

  Path to project directory (or path to app.R / server.R)

## Value

Named list with keys: project, files, contexts, symbols, references,
nodes, edges, issues
