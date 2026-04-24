# Build sb_symbol tibble from parsed contexts and references

Creates:

- One symbol per context that defines a graphable entity

- Synthetic input_ref symbols for each distinct input\$x encountered

- Synthetic state symbols for reactiveVal/reactiveValues

## Usage

``` r
build_symbols(contexts, references, file_id, project_id)
```

## Arguments

- contexts:

  sb_context tibble

- references:

  sb_reference tibble

- file_id:

  File ID

- project_id:

  Project ID

## Value

sb_symbol tibble
