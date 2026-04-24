# Validate graph integrity

Checks for: orphan edges, duplicate node IDs, unrecognized node types

## Usage

``` r
validate_graph(nodes, edges, project_id)
```

## Arguments

- nodes:

  sb_node_candidate tibble

- edges:

  sb_edge_candidate tibble

- project_id:

  Project ID

## Value

sb_issue tibble (empty if no problems)
