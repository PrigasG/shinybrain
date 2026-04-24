# shinybrain

[![R-CMD-check](https://github.com/PrigasG/shinybrain/actions/workflows/R-CMD-check.yaml/badge.svg?branch=master)](https://github.com/PrigasG/shinybrain/actions/workflows/R-CMD-check.yaml)

`shinybrain` statically analyzes Shiny applications without running them. It parses app source code, identifies reactive contexts and helper functions, resolves references across sourced files, and builds a portable "App Brain" that can be exported as structured JSON, Markdown, or an HTML dependency report.

## What it gives you

- A project-level parse of Shiny code without launching the app
- Reactive graph nodes and edges for inputs, reactives, outputs, observers, helpers, and state
- Detection of sourced files, missing `source()` targets, and dynamic patterns that cannot be resolved statically
- Export formats you can hand to humans, CI jobs, or LLM workflows

## Installation

```r
# install.packages("pak")
# pak::pak("PrigasG/shinybrain")
```

Or install from a local clone:

```r
# install.packages("devtools")
devtools::install(".")
```

## Quick start

```r
library(shinybrain)

app_dir <- system.file("examples", "basic_app", package = "shinybrain")
if (app_dir == "") app_dir <- file.path("inst", "examples", "basic_app")
if (!dir.exists(app_dir)) app_dir <- file.path("examples", "basic_app")

result <- analyze_shiny_project(app_dir)
brain  <- build_brain(result)

brain$summary
```

You can inspect the graph in the console:

```r
print_brain_console(brain)
```

And export it for downstream use:

```r
export_brain_json(brain, "brain.json")
export_brain_markdown(brain, "brain.md")
export_brain_html(brain, "brain.html", open = FALSE)
```

## Included example apps

The repository ships with concrete example apps in `examples/`:

- `examples/basic_app/`: a runnable Shiny app covering the happy path
- `examples/edge_case_app/`: an analyzer fixture with a missing `source()` target, a dynamic `source()` call, and a dynamic `input[[...]]` access

Installed copies are also available under `system.file("examples", ..., package = "shinybrain")`.

The test fixtures in `tests/fixtures/` also include compact examples for single-file apps, observer/state behavior, and sourced-file projects.

## Main workflow

1. Call `analyze_shiny_file()` or `analyze_shiny_project()`
2. Build an App Brain with `build_brain()`
3. Export or report with:
   - `print_brain_console()`
   - `export_brain_json()`
   - `export_brain_markdown()`
   - `export_brain_html()`

## Articles

- `vignette("shinybrain-getting-started")`
- `vignette("shinybrain-workflows")`

## Development status

The package is set up as an R package with tests, examples, vignettes, and pkgdown configuration. It is intended for static analysis and reporting workflows rather than runtime Shiny instrumentation.
