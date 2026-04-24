# Detect the entry point of a Shiny project directory

Detect the entry point of a Shiny project directory

## Usage

``` r
detect_entry_point(path)
```

## Arguments

- path:

  Path to project directory

## Value

Named list: list(type, files) where type is one of "app_r",
"ui_server_pair", or throws with guidance
