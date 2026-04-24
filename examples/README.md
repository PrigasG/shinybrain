# shinybrain examples

Fixtures and a runner script used to exercise every public entry point of
the package.

## Apps

`basic_app/` is runnable under Shiny and exercises the happy path:

| construct          | where it appears                               |
|--------------------|------------------------------------------------|
| `reactive()`       | `dataset`, `filtered`                          |
| `eventReactive()`  | `summary_data`                                 |
| `observeEvent()`   | save and reset buttons                         |
| `observe()`        | the log-when-runs-high observer                |
| `reactiveVal()`    | `saved`                                        |
| `reactiveValues()` | `counters`                                     |
| `renderText`       | `output$status`                                |
| `renderTable`      | `output$preview`                               |
| `renderPlot`       | `output$chart`                                 |
| `source()`         | `source("helpers.R")`                          |
| helper functions   | `filter_by_threshold`, `summarize_numeric`     |
| side-effect calls  | `write.csv`, `message` inside save observer    |

`edge_case_app/` is not runnable. It is fed to the analyzer to produce:

- a resolved `source()` to `helpers.R`
- a `missing_file` issue from `source("does_not_exist.R")`
- an `unsupported_pattern` issue from `source(paste0("dyna", "mic.R"))`
- a dynamic input read (`input[[key]]`) that should be flagged `is_dynamic`

## Runner

```sh
Rscript examples/run_example.R
```

Prints nodes, edges, and issues for each app and then writes JSON, Markdown,
and HTML brain exports for the basic app into `tempdir()`.
