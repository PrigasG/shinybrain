# shinybrain example runner

The canonical packaged example apps live in `inst/examples/`.

This directory only keeps a convenience runner script for local development.

## Runner

```sh
Rscript examples/run_example.R
```

Prints nodes, edges, and issues for the packaged example apps and then writes
JSON, Markdown, and HTML brain exports for the basic app into `tempdir()`.
