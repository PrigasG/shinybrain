# Workflows and Included Examples

This package ships with concrete example apps and fixtures that exercise
the analysis pipeline.

## Example apps

### `examples/basic_app`

This is the happy-path example. It includes:

- [`reactive()`](https://rdrr.io/pkg/shiny/man/reactive.html)
- [`eventReactive()`](https://rdrr.io/pkg/shiny/man/observeEvent.html)
- [`observeEvent()`](https://rdrr.io/pkg/shiny/man/observeEvent.html)
- [`observe()`](https://rdrr.io/pkg/shiny/man/observe.html)
- [`reactiveVal()`](https://rdrr.io/pkg/shiny/man/reactiveVal.html)
- [`reactiveValues()`](https://rdrr.io/pkg/shiny/man/reactiveValues.html)
- [`renderText()`](https://rdrr.io/pkg/shiny/man/renderPrint.html)
- [`renderTable()`](https://rdrr.io/pkg/shiny/man/renderTable.html)
- [`renderPlot()`](https://rdrr.io/pkg/shiny/man/renderPlot.html)
- sourced helper functions
- side-effect calls such as
  [`write.csv()`](https://rdrr.io/r/utils/write.table.html) and
  [`message()`](https://rdrr.io/r/base/message.html)

``` r

library(shinybrain)

basic_app <- system.file("examples", "basic_app", package = "shinybrain")
if (basic_app == "") basic_app <- file.path("inst", "examples", "basic_app")
if (!dir.exists(basic_app)) basic_app <- file.path("examples", "basic_app")

basic_result <- analyze_shiny_project(basic_app)
table(basic_result$contexts$context_type)
#> < table of extent 0 >
```

### `examples/edge_case_app`

This app is designed for analyzer edge cases rather than runtime
execution. It includes:

- a resolved `source("helpers.R")`
- a missing source target
- a dynamic [`source()`](https://rdrr.io/r/base/source.html) call
- a dynamic `input[[...]]` lookup

``` r

edge_app <- system.file("examples", "edge_case_app", package = "shinybrain")
if (edge_app == "") edge_app <- file.path("inst", "examples", "edge_case_app")
if (!dir.exists(edge_app)) edge_app <- file.path("examples", "edge_case_app")

edge_result <- analyze_shiny_project(edge_app)
edge_result$issues[, c("severity", "issue_type")]
#> # A tibble: 1 × 2
#>   severity issue_type  
#>   <chr>    <chr>       
#> 1 error    missing_file
```

## Fixture-level workflows

The `tests/fixtures/` directory contains small focused projects for
regression testing:

- `basic_single_file`
- `observer_and_state`
- `source_chain`

These are useful when you want compact reproducible inputs while working
on the parser or graph builder.

## Export workflow

Once you have a `brain` object, the usual downstream workflow is:

``` r

brain <- build_brain(basic_result)

export_brain_json(brain, "brain.json")
export_brain_markdown(brain, "brain.md")
export_brain_html(brain, "brain.html", open = FALSE)
```

## Smoke-test runner

The repository includes a convenience runner:

``` r

source("examples/run_example.R")
```

It analyzes the bundled example apps, prints summaries, and writes
export artifacts to a temporary directory.
