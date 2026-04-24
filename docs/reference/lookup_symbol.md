# Look up a symbol by name in the symbols table

Look up a symbol by name in the symbols table

## Usage

``` r
lookup_symbol(name, symbols, from_context_id = NA_character_)
```

## Arguments

- name:

  Symbol name string

- symbols:

  sb_symbol tibble

- from_context_id:

  Context ID for disambiguation (unused in Sprint 1)

## Value

List: list(symbol_id, unresolved_reason)
