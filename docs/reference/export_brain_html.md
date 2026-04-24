# Export a self-contained HTML report from an App Brain

Produces a polished HTML file with a reactive graph visualization
(powered by vis.js via CDN), insight cards, and full node/edge tables.

## Usage

``` r
export_brain_html(brain, file = NULL, open = TRUE)
```

## Arguments

- brain:

  App Brain from build_brain()

- file:

  Path to write the HTML file. NULL auto-generates in the working
  directory.

- open:

  Logical. Open the file in the default browser after writing.

## Value

Invisibly returns the file path.
