# Export App Brain to JSON

Produces a structured JSON string suitable for pasting into an LLM
context or saving as a file for agent consumption.

## Usage

``` r
export_brain_json(brain, file = NULL, pretty = TRUE)
```

## Arguments

- brain:

  App Brain from build_brain()

- file:

  Optional file path to write JSON. NULL returns the string.

- pretty:

  Logical. Pretty-print the JSON (default TRUE).

## Value

Invisibly returns the JSON string.
