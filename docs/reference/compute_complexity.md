# Compute a composite complexity score for the app

Returns a list with `score` (0-100) and `label`
(Low/Moderate/High/Complex).

## Usage

``` r
compute_complexity(nodes, edges, insights)
```

## Arguments

- nodes:

  sb_node_candidate tibble

- edges:

  sb_edge_candidate tibble

- insights:

  Insights tibble from generate_insights()
