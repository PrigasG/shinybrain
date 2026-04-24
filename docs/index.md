# shinybrain

- [shinybrain](#shinybrain)
  - [What it gives you](#what-it-gives-you)
  - [Installation](#installation)
  - [Quick start](#quick-start)
  - [Included example apps](#included-example-apps)
  - [Main workflow](#main-workflow)
  - [Articles](#articles)
  - [Development status](#development-status)

[![R-CMD-check](https://github.com/PrigasG/shinybrain/actions/workflows/R-CMD-check.yaml/badge.svg?branch=master)](https://github.com/PrigasG/shinybrain/actions/workflows/R-CMD-check.yaml)

`shinybrain` statically analyzes Shiny applications without running
them. It parses app source code, identifies reactive contexts and helper
functions, resolves references across sourced files, and builds a
portable “App Brain” that can be exported as structured JSON, Markdown,
or an HTML dependency report.

## What it gives you

- A project-level parse of Shiny code without launching the app
- Reactive graph nodes and edges for inputs, reactives, outputs,
  observers, helpers, and state
- Detection of sourced files, missing
  [`source()`](https://rdrr.io/r/base/source.html) targets, and dynamic
  patterns that cannot be resolved statically
- Export formats you can hand to humans, CI jobs, or LLM workflows

## Installation

``` r

# install.packages("pak")
# pak::pak("PrigasG/shinybrain")
```

Or install from a local clone:

``` r

# install.packages("devtools")
devtools::install(".")
```

## Quick start

``` r

library(shinybrain)

app_dir <- system.file("examples", "basic_app", package = "shinybrain")
if (app_dir == "") app_dir <- file.path("..", "inst", "examples", "basic_app")
if (!dir.exists(app_dir)) app_dir <- file.path("inst", "examples", "basic_app")

result <- analyze_shiny_project(app_dir)
brain  <- build_brain(result)

brain$summary
#> $n_files
#> [1] 2
#> 
#> $n_contexts
#> [1] 13
#> 
#> $n_nodes
#> [1] 18
#> 
#> $n_edges
#> [1] 13
#> 
#> $n_symbols
#> [1] 18
#> 
#> $n_unresolved
#> [1] 0
#> 
#> $n_issues
#> [1] 4
#> 
#> $n_insights
#> [1] 1
#> 
#> $max_chain_depth
#> [1] 5
#> 
#> $complexity
#> $complexity$score
#> [1] 50
#> 
#> $complexity$label
#> [1] "Moderate"
#> 
#> 
#> $node_breakdown
#> $node_breakdown$helper_fn
#> [1] 2
#> 
#> $node_breakdown$input
#> [1] 5
#> 
#> $node_breakdown$observer
#> [1] 3
#> 
#> $node_breakdown$output
#> [1] 3
#> 
#> $node_breakdown$reactive
#> [1] 3
#> 
#> $node_breakdown$state
#> [1] 2
#> 
#> 
#> $edge_breakdown
#> $edge_breakdown$calls
#> [1] 2
#> 
#> $edge_breakdown$depends_on
#> [1] 4
#> 
#> $edge_breakdown$feeds_into
#> [1] 5
#> 
#> $edge_breakdown$reads_state
#> [1] 1
#> 
#> $edge_breakdown$writes_state
#> [1] 1
```

You can inspect the graph in the console:

``` r

print_brain_console(brain)
#> 
#> ============================================================ 
#>   ShinyBrain Report   basic_app 
#>   shinybrain  0.1.0    2026-04-24 00:43  UTC
#> ============================================================ 
#> 
#>   Complexity: Moderate ( 50 / 100 ) [██████████░░░░░░░░░░] 
#>   Chain depth: 5  ⚠  deep pipeline 
#> 
#>   At a Glance 
#>   ----------- 
#>   Files         : 2 
#>   Contexts      : 13 
#>   Nodes         : 18 
#>   Edges         : 13 
#>   Unresolved    : 0 
#>   Node types    : helper_fn × 2   input × 5   observer × 3   output × 3   reactive × 3   state × 2  
#> 
#>   Files 
#>   ----- 
#>   ✓ app.R ( entry , 88 lines )
#>   ✓ helpers.R ( sourced , 32 lines )
#> 
#>   Reactive Graph 
#>   -------------- 
#>   [ state ]
#>     • saved   → used by 1  
#>     • counters   
#>   [ reactive ]
#>     • dataset   → used by 1  
#>     • filtered   → used by 2  
#>     • summary_data   → used by 2  
#>   [ output ]
#>     • output$status   → used by 1  
#>     • output$preview   → used by 1  
#>     • output$chart   → used by 1  
#>   [ observer ]
#>     • observeEvent_46   → used by 2  
#>     • observeEvent_54   
#>     • observe_60   
#>   [ helper_fn ]
#>     • filter_by_threshold   → used by 1  
#>     • summarize_numeric   → used by 1  
#>   [ input ]
#>     • input$dataset   
#>     • input$cutoff   
#>     • input$go_btn   
#>     • input$save_btn   
#>     • input$reset_btn   
#> 
#>   Insights 
#>   -------- 
#>   ⚠️  [WARNING] 'write.csv()' inside 'observeEvent_46' is a side effect
#>      not wrapped in isolate(); it will re-run on every reactive
#>      invalidation cycle. 
#> 
#> ============================================================ 
#> 
#>   Run shinybrain_report(..., format = "html") for the interactive report.
```

And export it for downstream use:

``` r

export_brain_json(brain, "brain.json")
export_brain_markdown(brain, "brain.md")
export_brain_html(brain, "brain.html", open = FALSE)
```

## Included example apps

The package ships with concrete example apps under `inst/examples/`,
available after installation via
`system.file("examples", ..., package = "shinybrain")`:

- `basic_app/`: a runnable Shiny app covering the happy path
- `edge_case_app/`: an analyzer fixture with a missing
  [`source()`](https://rdrr.io/r/base/source.html) target, a dynamic
  [`source()`](https://rdrr.io/r/base/source.html) call, and a dynamic
  `input[[...]]` access

The test fixtures in `tests/fixtures/` also include compact examples for
single-file apps, observer/state behavior, and sourced-file projects.

## Main workflow

1.  Call
    [`analyze_shiny_file()`](https://prigasg.github.io/shinybrain/reference/analyze_shiny_file.md)
    or
    [`analyze_shiny_project()`](https://prigasg.github.io/shinybrain/reference/analyze_shiny_project.md)
2.  Build an App Brain with
    [`build_brain()`](https://prigasg.github.io/shinybrain/reference/build_brain.md)
3.  Export or report with:
    - [`print_brain_console()`](https://prigasg.github.io/shinybrain/reference/print_brain_console.md)
    - [`export_brain_json()`](https://prigasg.github.io/shinybrain/reference/export_brain_json.md)
    - [`export_brain_markdown()`](https://prigasg.github.io/shinybrain/reference/export_brain_markdown.md)
    - [`export_brain_html()`](https://prigasg.github.io/shinybrain/reference/export_brain_html.md)

## Articles

- [`vignette("shinybrain-getting-started")`](https://prigasg.github.io/shinybrain/articles/shinybrain-getting-started.md)
- [`vignette("shinybrain-workflows")`](https://prigasg.github.io/shinybrain/articles/shinybrain-workflows.md)

## Development status

The package is set up as an R package with tests, examples, vignettes,
and pkgdown configuration. It is intended for static analysis and
reporting workflows rather than runtime Shiny instrumentation.
