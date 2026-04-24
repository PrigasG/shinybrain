# Resolve references to symbol IDs where possible

Links function_call and reactive_read references to known project
symbols. Re-types state_val reads/writes by checking if the target is a
state symbol. Sets unresolved_reason for cases where resolution was
expected but failed.

## Usage

``` r
resolve_references(references, symbols, project_id)
```

## Arguments

- references:

  sb_reference tibble

- symbols:

  sb_symbol tibble

- project_id:

  Project ID

## Value

Updated sb_reference tibble
