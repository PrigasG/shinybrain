# Generate a short deterministic ID from one or more strings

Uses a digest-style hash (base conversion of sum of char codes +
length), keeping it short and readable. Deterministic for same inputs.

## Usage

``` r
make_id(..., prefix = "")
```

## Arguments

- ...:

  Values to combine. Non-character inputs are coerced via
  as.character(); NULL entries are dropped; NA becomes "NA".

- prefix:

  Optional prefix string e.g. "ctx", "sym"

## Value

Single character ID string of the form "\_\<6-hex-digits\>".

## Details

NA and NULL inputs are coerced to the literal string "NA" so that two
callers with the same NA pattern produce the same ID; callers that pass
genuinely distinct values should ensure their inputs are not NA.
