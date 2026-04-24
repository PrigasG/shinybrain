# Brain export options

Brain export options

## Usage

``` r
brain_options(
  include_snippets = TRUE,
  snippet_max_lines = 15L,
  include_file_paths = "relative",
  include_unresolved = TRUE,
  strict_missing_sources = FALSE,
  verbose = FALSE
)
```

## Arguments

- include_snippets:

  Logical. Include code snippets in node data.

- snippet_max_lines:

  Integer. Max lines per snippet.

- include_file_paths:

  One of "relative", "basename", or "none".

- include_unresolved:

  Logical. Include unresolved references in export.

- strict_missing_sources:

  Logical. When TRUE, elevates missing-file warnings (from unresolved
  [`source()`](https://rdrr.io/r/base/source.html) targets) to errors.
  The ghost node is still emitted either way.

- verbose:

  Logical. When TRUE,
  [`build_brain()`](https://prigasg.github.io/shinybrain/reference/build_brain.md)
  prints a diagnostic report of every state-related reference
  (state_read, state_write, ambiguous state calls) with its
  `target_arg_count`. Useful when a state edge is expected but missing
  from the graph.

## Value

Named list of options
