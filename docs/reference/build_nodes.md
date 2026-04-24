# Promote contexts to graph node candidates

Also creates synthetic input nodes from symbols of type "input_ref" and
ghost nodes for files marked as missing (role == "missing") so the graph
visibly shows broken source() links rather than silently dropping them.

## Usage

``` r
build_nodes(contexts, symbols, project_id, files = NULL)
```

## Arguments

- contexts:

  sb_context tibble

- symbols:

  sb_symbol tibble

- project_id:

  Project ID

- files:

  Optional sb_file tibble used to emit ghost nodes for missing files.
  Pass NULL to skip ghost-node emission.

## Value

sb_node_candidate tibble
