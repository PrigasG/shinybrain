# Getting Started with shinybrain

`shinybrain` statically analyzes Shiny application source code and turns
it into a portable “App Brain” object. This vignette walks through the
smallest useful workflow.

## Analyze a project

``` r

library(shinybrain)

app_dir <- system.file("examples", "basic_app", package = "shinybrain")
if (app_dir == "") app_dir <- file.path("..", "inst", "examples", "basic_app")
if (!dir.exists(app_dir)) app_dir <- file.path("inst", "examples", "basic_app")

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
#>   shinybrain  0.1.0    2026-04-24 00:45  UTC
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
#> [1] 11
```

## Next steps

See
[`vignette("shinybrain-workflows")`](https://prigasg.github.io/shinybrain/articles/shinybrain-workflows.md)
for a tour of the included example apps and typical analysis workflows.
