# Null coalescing operator

Null coalescing operator

## Usage

``` r
x %||% y
```

## Arguments

- x:

  Primary value to return when it is not NULL and not length 0.

- y:

  Fallback value returned when `x` is NULL or empty.

## Value

`x` when present, otherwise `y`.
