# shinybrain example runner

The canonical packaged example apps live in `inst/examples/`.

This directory only keeps a convenience runner script for local development.

## Available examples

- `basic_app`: baseline multi-file app with helpers, state, observers, and exports
- `edge_case_app`: missing and dynamic `source()` handling
- `v2_hotspot_app`: concentrated reactive dependencies for hotspot detection
- `v2_dead_reactive_app`: intentionally unused reactive for dead-reactive detection
- `v2_side_effect_app`: side effects inside a reactive for architecture warnings
- `v2_legacy_app`: multi-file legacy-style app with modules, dynamic UI, side effects, and incomplete module wiring

## Runner

```sh
Rscript examples/run_example.R
```

Prints nodes, edges, and issues for the packaged example apps and then writes
JSON, Markdown, and HTML brain exports for the basic app into `tempdir()`.
