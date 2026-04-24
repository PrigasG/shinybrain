# Valid context types Note: "module_def" and "module_instance" are reserved for future module support but are not produced by the current parser. "ui_block" and "global_block" were removed in 0.1.0; the parser classifies top-level UI and global.R content as "unknown" or "helper_fn" instead.

Valid context types Note: "module_def" and "module_instance" are
reserved for future module support but are not produced by the current
parser. "ui_block" and "global_block" were removed in 0.1.0; the parser
classifies top-level UI and global.R content as "unknown" or "helper_fn"
instead.

## Usage

``` r
CONTEXT_TYPES
```

## Format

An object of class `character` of length 9.
