# Load a single R source file into an sb_file row

Does not parse the code. Only reads the file and validates it exists. On
failure, returns a row with parse_success = FALSE and an issue row.

## Usage

``` r
load_file(path, project_id, role = "entry", source_line = NA_integer_)
```

## Arguments

- path:

  Absolute or relative path to the file

- project_id:

  Project ID string

- role:

  One of "entry", "sourced", "module"

- source_line:

  Line in the calling file where source() was found, or NA_integer\_ for
  entry files

## Value

Named list: list(file = one-row sb_file tibble, issues = sb_issue
tibble)
