# Generate developer-facing insights from resolved IR

Generate developer-facing insights from resolved IR

## Usage

``` r
generate_insights(nodes, edges, references, contexts, issues)
```

## Arguments

- nodes:

  sb_node_candidate tibble

- edges:

  sb_edge_candidate tibble

- references:

  sb_reference tibble (resolved)

- contexts:

  sb_context tibble

- issues:

  sb_issue tibble

## Value

Tibble with columns: category, severity, label, message
