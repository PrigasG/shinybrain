# Extract static source() call paths from parse data

Only resolves string-literal paths. Dynamic paths produce issues.

## Usage

``` r
extract_source_calls(parse_data, calling_file_path, project_id, file_id)
```

## Arguments

- parse_data:

  Data frame from getParseData()

- calling_file_path:

  Absolute path of the file containing the call

- project_id:

  Project ID

- file_id:

  File ID

## Value

Named list: list(paths = character vector, issues = sb_issue tibble)
