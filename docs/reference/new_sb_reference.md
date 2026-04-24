# Create an empty sb_reference tibble

`target_arg_count` is an implementation-detail column populated during
reference extraction. It is used by the resolver to distinguish state
reads (`rv()`, 0 args) from state writes (`rv(val)`, 1+ args). NA means
argument count is unknown or not applicable.

## Usage

``` r
new_sb_reference()
```

## Value

tibble with 0 rows and correct column types
