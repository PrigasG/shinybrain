# Build a single sb_issue row as a one-row tibble

Build a single sb_issue row as a one-row tibble

## Usage

``` r
make_issue(
  project_id,
  severity,
  issue_type,
  message,
  file_id = NA_character_,
  context_id = NA_character_,
  line_start = NA_integer_,
  line_end = NA_integer_
)
```

## Arguments

- project_id:

  Project ID string

- severity:

  One of "info", "warning", "error"

- issue_type:

  One of ISSUE_TYPES

- message:

  Human-readable message

- file_id:

  Optional file ID

- context_id:

  Optional context ID

- line_start:

  Optional line number

- line_end:

  Optional line number

## Value

One-row sb_issue tibble
