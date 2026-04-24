# Build the App Brain from a ShinyBrain analysis result

Assembles analysis output into a portable, self-contained object ready
for export (JSON/Markdown for LLMs) or reporting (console/HTML for
developers).

## Usage

``` r
build_brain(result, options = brain_options())
```

## Arguments

- result:

  Named list from analyze_shiny_file() or analyze_shiny_project()

- options:

  brain_options() list

## Value

Named list: project, files, summary, nodes, edges, insights, issues,
options
