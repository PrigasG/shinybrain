# Extract context objects from parse data

Identifies all reactive, observer, output, helper function, and state
contexts in the file.

## Usage

``` r
extract_contexts(parse_data, code, file_id, project_id)
```

## Arguments

- parse_data:

  Data frame from getParseData()

- code:

  Raw code string

- file_id:

  File ID

- project_id:

  Project ID

## Value

sb_context tibble
