# Recursively resolve all source() chains from an entry file

Returns files in parse order (entry first, then sourced files DFS).
Detects and breaks cycles.

## Usage

``` r
resolve_source_chain(entry_path, project_id)
```

## Arguments

- entry_path:

  Absolute path to entry file

- project_id:

  Project ID

## Value

Named list: list(ordered_paths = char vector, file_roles = named char
vector, source_lines = named int vector, issues = sb_issue tibble)
