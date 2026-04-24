# Export App Brain to Markdown

Produces a human- and LLM-readable Markdown document summarising the app
structure, reactive graph, and insights.

## Usage

``` r
export_brain_markdown(brain, file = NULL)
```

## Arguments

- brain:

  App Brain from build_brain()

- file:

  Optional file path to write Markdown. NULL returns the string.

## Value

Invisibly returns the Markdown string.
