# Validate an IR object against its expected schema

Validate an IR object against its expected schema

## Usage

``` r
validate_ir(x, schema_name)
```

## Arguments

- x:

  The tibble to validate

- schema_name:

  One of: "project", "file", "context", "symbol", "reference",
  "node_candidate", "edge_candidate", "issue"

## Value

Invisibly returns x; throws error on schema mismatch
