# Extract intra-context references from parse data

Extract intra-context references from parse data

## Usage

``` r
extract_references(contexts, parse_data, code, file_id, project_id)
```

## Arguments

- contexts:

  sb_context tibble

- parse_data:

  Data frame from getParseData()

- code:

  Raw code string

- file_id:

  File ID

- project_id:

  Project ID

## Value

sb_reference tibble
