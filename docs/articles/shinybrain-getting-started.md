# Getting Started with shinybrain

`shinybrain` statically analyzes Shiny application source code and turns
it into a portable “App Brain” object. This vignette walks through the
smallest useful workflow.

## Analyze a project

``` r

library(shinybrain)

app_dir <- system.file("examples", "basic_app", package = "shinybrain")
if (app_dir == "") app_dir <- file.path("inst", "examples", "basic_app")
if (!dir.exists(app_dir)) app_dir <- file.path("examples", "basic_app")

result <- analyze_shiny_project(app_dir)
names(result)
#> [1] "project"    "files"      "contexts"   "symbols"    "references"
#> [6] "nodes"      "edges"      "issues"
```

The analysis result contains project metadata plus the internal tibbles
used by the parser and graph builder:

- `project`
- `files`
- `contexts`
- `symbols`
- `references`
- `nodes`
- `edges`
- `issues`

## Build an App Brain

``` r

brain <- build_brain(result)
brain$summary
#> $n_files
#> [1] 0
#> 
#> $n_contexts
#> [1] 0
#> 
#> $n_nodes
#> [1] 0
#> 
#> $n_edges
#> [1] 0
#> 
#> $n_symbols
#> [1] 0
#> 
#> $n_unresolved
#> [1] 0
#> 
#> $n_issues
#> [1] 1
#> 
#> $n_insights
#> [1] 1
#> 
#> $max_chain_depth
#> [1] 0
#> 
#> $complexity
#> $complexity$score
#> [1] 0
#> 
#> $complexity$label
#> [1] "Low"
#> 
#> 
#> $node_breakdown
#> list()
#> 
#> $edge_breakdown
#> list()
```

The App Brain is the package’s portable reporting object. It includes:

- project metadata
- file inventory
- graph nodes and edges
- generated insights
- issue records
- export options

## Print a console summary

``` r

print_brain_console(brain)
#> 
#> ============================================================ 
#>   ShinyBrain Report   basic_app 
#>   shinybrain  0.1.0    2026-04-24 00:34  UTC
#> ============================================================ 
#> 
#>   Complexity: Low ( 0 / 100 ) [░░░░░░░░░░░░░░░░░░░░] 
#>   Chain depth: 0  
#> 
#>   At a Glance 
#>   ----------- 
#>   Files         : 0 
#>   Contexts      : 0 
#>   Nodes         : 0 
#>   Edges         : 0 
#>   Unresolved    : 0 
#> 
#>   Insights 
#>   -------- 
#>   ❌ [ERROR] Directory not found:
#>      C:\Users\priga\Documents\shinybrain\vignettes\examples\basic_app 
#> 
#> 
#>   Pipeline Issues 
#>   --------------- 
#>   ⚠️  [ ERROR ]  Directory not found: C:\Users\priga\Documents\shinybrain\vignettes\examples\basic_app 
#> ============================================================ 
#> 
#>   Run shinybrain_report(..., format = "html") for the interactive report.
```

## Export for downstream use

``` r

export_brain_json(brain, "brain.json")
export_brain_markdown(brain, "brain.md")
export_brain_html(brain, "brain.html", open = FALSE)
```

## Single-file apps

If you already know the app entry file, use
[`analyze_shiny_file()`](https://prigasg.github.io/shinybrain/reference/analyze_shiny_file.md):

``` r

single_file <- file.path(app_dir, "app.R")

single_result <- analyze_shiny_file(single_file)
nrow(single_result$contexts)
#> [1] 0
```

## Next steps

See
[`vignette("shinybrain-workflows")`](https://prigasg.github.io/shinybrain/articles/shinybrain-workflows.md)
for a tour of the included example apps and typical analysis workflows.
