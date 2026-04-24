# Analyze a single Shiny R file

Runs the full static analysis pipeline on one file and returns all
internal representation objects as a named list.

## Usage

``` r
analyze_shiny_file(path)
```

## Arguments

- path:

  Path to the Shiny R file (app.R or equivalent)

## Value

Named list with keys: project, files, contexts, symbols, references,
nodes, edges, issues
