# ShinyBrain - v0.1 Build Package

> Concrete implementation guide: IR schemas, function signatures, fixture apps, Sprint 1 checklist.

---

## 1. Internal Representation (IR) - Tibble Schemas

These are the contracts the entire package builds toward. Every layer - parser, resolver, graph builder, exporter - reads and writes these structures. Lock them before writing functional code.

---

### 1.1 `sb_project`

One row. Top-level project container.

```r
sb_project <- tibble::tibble(
  project_id       = character(),   # uuid, e.g. "proj_a1b2c3"
  root_path        = character(),   # absolute path to project root
  entry_point_type = character(),   # "app_r" | "ui_server_pair" | "single_file"
  entry_files      = list(),        # character vector of entry file paths
  parse_order      = list(),        # character vector: order files were parsed
  shinybrain_version = character(), # package version that produced this
  created_at       = character()    # ISO timestamp
)
```

---

### 1.2 `sb_file`

One row per source file parsed.

```r
sb_file <- tibble::tibble(
  file_id       = character(),  # "file_001"
  project_id    = character(),  # foreign key to sb_project
  path          = character(),  # absolute path
  relative_path = character(),  # relative to project root
  role          = character(),  # "entry" | "sourced" | "module"
  source_line   = integer(),    # line in parent file where source() was called, NA if entry
  code          = character(),  # full raw code as single string
  line_count    = integer(),
  parse_success = logical()
)
```

---

### 1.3 `sb_context`

One row per meaningful execution block. This is the central IR object -
everything that can become a graph node starts here.

```r
sb_context <- tibble::tibble(
  context_id        = character(),  # "ctx_001"
  project_id        = character(),
  file_id           = character(),
  context_type      = character(),  # see type enum below
  label             = character(),  # e.g. "filtered_data", "output$plot", "observe_001"
  qualified_name    = character(),  # "app.R::filtered_data"
  line_start        = integer(),
  line_end          = integer(),
  parent_context_id = character(),  # NA if top-level; used for nested/module contexts
  module_id         = character(),  # NA if not inside a module
  snippet           = character(),  # extracted code body, trimmed to N lines
  contains_isolate  = logical(),
  confidence        = character(),  # "high" | "medium" | "low"
  flags             = list()        # character vector of flags e.g. "possible_side_effect"
)
```

**`context_type` enum:**

```
"reactive"
"output_render"
"observer"
"observe_event"
"event_reactive"
"helper_fn"
"state_val"        # reactiveVal()
"state_values"     # reactiveValues()
"ui_block"
"global_block"
"unknown"
```

> **Reserved for future use:** `"module_def"`, `"module_instance"` - the parser
> does not yet detect Shiny modules. The `module_id` field in schemas is a
> placeholder.

---

### 1.4 `sb_symbol`

One row per named entity defined in the project.

```r
sb_symbol <- tibble::tibble(
  symbol_id          = character(),  # "sym_001"
  project_id         = character(),
  file_id            = character(),
  context_id         = character(),  # context where this symbol is defined
  name               = character(),  # e.g. "filtered_data", "clean_data", "rv"
  qualified_name     = character(),  # "app.R::filtered_data"
  symbol_type        = character(),  # see type enum below
  line_start         = integer(),
  line_end           = integer(),
  module_id          = character(),  # NA if not module-scoped
  usage_count        = integer(),    # how many contexts reference this symbol
  confidence         = character()
)
```

**`symbol_type` enum:**

```
"input_ref"        # input$x - always read-only, never defined
"output"           # output$x <- render*
"reactive"
"event_reactive"
"observer"
"observe_event"
"helper_fn"
"state_val"
"state_values"
"unresolved"
```

> **Reserved for future use:** `"module_def"`, `"module_instance"`

---

### 1.5 `sb_reference`

One row per reference from one context to a symbol or input.
This is the raw material for graph edges.

```r
sb_reference <- tibble::tibble(
  reference_id       = character(),  # "ref_001"
  project_id         = character(),
  from_context_id    = character(),  # context containing the reference
  reference_type     = character(),  # see type enum below
  target_text        = character(),  # raw text as written, e.g. "input$year", "clean_data"
  resolved_symbol_id = character(),  # NA if unresolved
  line_start         = integer(),
  line_end           = integer(),
  is_isolated        = logical(),    # TRUE if inside isolate()
  is_dynamic         = logical(),    # TRUE if target cannot be statically determined
  confidence         = character(),
  unresolved_reason  = character()   # NA or unresolved type string (see section 3)
)
```

**`reference_type` enum:**

```
"input_read"
"reactive_read"
"output_write"
"state_read"
"state_write"
"function_call"
"event_trigger"
"namespace_use"
"source_call"
"module_instantiation"
"ui_update_call"
```

---

### 1.6 `sb_node_candidate`

Promoted from `sb_context` after resolution. One row per graph node.
Renderer consumes this, not raw contexts.

```r
sb_node_candidate <- tibble::tibble(
  node_id           = character(),  # "node_001" - stable across renders
  project_id        = character(),
  context_id        = character(),  # FK to sb_context
  node_type         = character(),  # final graph type (maps from context_type)
  label             = character(),
  qualified_name    = character(),
  file_id           = character(),
  line_start        = integer(),
  module_id         = character(),
  confidence        = character(),
  contains_isolate  = logical(),
  usage_count       = integer(),    # for helper_fn nodes only
  flags             = list(),
  snippet           = character()
)
```

---

### 1.7 `sb_edge_candidate`

One row per directed relationship in the graph.

```r
sb_edge_candidate <- tibble::tibble(
  edge_id      = character(),  # "edge_001"
  project_id   = character(),
  from_node_id = character(),
  to_node_id   = character(),
  edge_type    = character(),  # see type enum below
  reference_id = character(),  # FK to sb_reference if applicable
  is_isolated  = logical(),
  confidence   = character(),
  file_id      = character(),
  line_start   = integer(),
  flags        = list()
)
```

**`edge_type` enum:**

```
"depends_on"
"feeds_into"
"triggers"
"calls"
"reads_state"
"writes_state"
"contains"
"cross_module"
"defines"
"unresolved_link"
```

---

### 1.8 `sb_issue`

One row per warning, error, or flagged pattern.

```r
sb_issue <- tibble::tibble(
  issue_id     = character(),  # "issue_001"
  project_id   = character(),
  file_id      = character(),  # NA if project-level
  context_id   = character(),  # NA if not context-specific
  severity     = character(),  # "info" | "warning" | "error"
  issue_type   = character(),  # see unresolved taxonomy (section 3)
  message      = character(),
  line_start   = integer(),
  line_end     = integer()
)
```

---

## 2. Function Signatures

Split into internal pipeline functions and user-facing functions.
Build internal first. User-facing functions are thin wrappers.

---

### 2.1 IO Layer (`R/io/`)

```r
# Detect project entry point from a directory path
# Returns list(type, files) or throws with guidance
detect_entry_point(path)

# Load a single file - reads code, validates it exists
# Returns sb_file row (unpopulated parse fields)
load_file(path, project_id, role = "entry", source_line = NA_integer_)

# Resolve all source() calls recursively from an entry file
# Returns character vector of file paths in parse order
# Detects and stops on cycles, returns issue rows for cycles found
resolve_source_chain(entry_path, project_root)
```

---

### 2.2 Parse Layer (`R/parse/`)

```r
# Parse a single file - runs all 5 passes
# Returns list(file = sb_file, contexts = sb_context, symbols = sb_symbol, references = sb_reference, issues = sb_issue)
parse_file(sb_file_row)

# Pass 1: run parse() + getParseData(), attach to file object
parse_raw(sb_file_row)

# Pass 2: scan top-level expressions
# Returns list of typed expression records
scan_top_level(parse_data, file_id)

# Pass 3: extract context objects from recognized call patterns
# Returns sb_context tibble rows
extract_contexts(top_level_exprs, file_id, project_id)

# Pass 4: extract intra-context references
# Returns sb_reference tibble rows
extract_references(contexts, parse_data, file_id, project_id)

# Pass 5: extract snippet for each context (trimmed to max_lines)
extract_snippet(context_row, code, max_lines = 20)
```

---

### 2.3 Resolve Layer (`R/resolve/`)

```r
# Link sb_reference rows to sb_symbol rows where possible
# Mutates resolved_symbol_id and updates confidence
# Returns updated sb_reference tibble
resolve_references(references, symbols, project_id)

# Check a symbol name against defined symbols
# Returns symbol_id or NA with unresolved_reason
lookup_symbol(name, symbols, from_context_id)
```

> **Not yet implemented:** `resolve_modules()` - module namespace resolution
> is planned but requires a dedicated parser pass. The `module_id` field is
> reserved in the IR schemas for this purpose.

---

### 2.4 Graph Layer (`R/graph/`)

```r
# Promote resolved contexts to node candidates
# Returns sb_node_candidate tibble
build_nodes(contexts, symbols, project_id)

# Build edge candidates from resolved references
# Returns sb_edge_candidate tibble
build_edges(references, nodes, symbols, project_id)

# Calculate usage count for helper_fn nodes
# Mutates usage_count on sb_node_candidate
compute_usage_weights(nodes, edges)

# Validate graph: check for orphan edges, duplicate IDs, etc.
# Returns sb_issue rows for any graph-level problems
validate_graph(nodes, edges, project_id)
```

---

### 2.5 Brain Layer (`R/brain/`) - Planned, not yet implemented

> The brain export layer (JSON/Markdown serialization, natural language
> summaries) is planned for a future sprint. The IR layers are designed to
> feed into it without changes.

---

### 2.6 User-Facing Functions (`R/`)

```r
# Main entry: analyze a project path, return full internal model
analyze_shiny_project(path)

# Convenience: analyze a single file
analyze_shiny_file(path)

# Print a human-readable summary of analysis results
summarize_analysis(result)
```

> **Planned (not yet implemented):** `shinybrain_export()`, `shinybrain_static()`,
> `shinybrain()`, `shinybrain_addin()`

---

## 3. Unresolved Taxonomy

Every `unresolved_reason` value must be one of these strings.
Used in `sb_reference`, `sb_issue`, and App Brain exports.

```r
UNRESOLVED_TYPES <- c(
  "dynamic_input_id",        # input[[paste0(...)]]
  "dynamic_output_id",       # output[[name]] <- ...
  "dynamic_source_path",     # source(file.path(...))
  "runtime_generated_ui",    # renderUI internals
  "conditional_definition",  # reactive inside if() block
  "ambiguous_symbol",        # name matches multiple definitions
  "unknown_callee",          # function call target not found in project
  "nonstandard_evaluation",  # NSE patterns obscuring symbols
  "unsupported_pattern",     # known limitation, not yet supported
  "parse_failure",           # file could not be parsed at all
  "module_link_incomplete",  # module wiring partially resolved
  "source_cycle"             # circular source() chain detected
)
```

---

## 4. Fixture Apps

Three reference apps for Sprint 1. Each is a complete, runnable Shiny app.
Store at `tests/fixtures/` in the package.

---

### Fixture 1: `basic_single_file`

`tests/fixtures/basic_single_file/app.R`

```r
library(shiny)

# Simple helper function
clean_data <- function(df) {
  df[complete.cases(df), ]
}

ui <- fluidPage(
  titlePanel("Basic App"),
  sidebarLayout(
    sidebarPanel(
      sliderInput("year", "Year", min = 2000, max = 2023, value = 2010),
      selectInput("region", "Region",
                  choices = c("North", "South", "East", "West"))
    ),
    mainPanel(
      plotOutput("trend_plot"),
      tableOutput("summary_table"),
      textOutput("record_count")
    )
  )
)

server <- function(input, output, session) {

  filtered_data <- reactive({
    df <- mtcars
    df <- clean_data(df)
    df[df$cyl >= input$year %% 4 + 4, ]
  })

  summary_stats <- reactive({
    data.frame(
      region = input$region,
      mean_mpg = mean(filtered_data()$mpg)
    )
  })

  output$trend_plot <- renderPlot({
    plot(filtered_data()$mpg, main = input$region)
  })

  output$summary_table <- renderTable({
    summary_stats()
  })

  output$record_count <- renderText({
    paste("Records:", nrow(filtered_data()))
  })

}

shinyApp(ui, server)
```

**Expected parse results:**

```r
# Contexts: 5
#   filtered_data  -> reactive
#   summary_stats  -> reactive
#   trend_plot     -> output_render
#   summary_table  -> output_render
#   record_count   -> output_render
#   clean_data     -> helper_fn

# Symbols: 6 (above + input refs)

# References from filtered_data:
#   input$year        -> input_read,  confidence = high
#   clean_data()      -> function_call, confidence = high

# References from summary_stats:
#   input$region      -> input_read,  confidence = high
#   filtered_data()   -> reactive_read, confidence = high

# References from trend_plot:
#   filtered_data()   -> reactive_read, confidence = high
#   input$region      -> input_read, confidence = high

# References from summary_table:
#   summary_stats()   -> reactive_read, confidence = high

# References from record_count:
#   filtered_data()   -> reactive_read, confidence = high

# Issues: 0
# Unresolved: 0
# clean_data usage_count: 1
```

---

### Fixture 2: `observer_and_state`

`tests/fixtures/observer_and_state/app.R`

```r
library(shiny)

ui <- fluidPage(
  numericInput("threshold", "Threshold", value = 5),
  actionButton("reset_btn", "Reset"),
  actionButton("save_btn", "Save"),
  textOutput("status"),
  tableOutput("filtered_table")
)

server <- function(input, output, session) {

  # State node - should NOT be classified as input
  rv <- reactiveVal(NULL)

  filtered <- reactive({
    req(input$threshold)
    mtcars[mtcars$cyl >= input$threshold, ]
  })

  # observeEvent - triggered by button
  observeEvent(input$reset_btn, {
    rv(NULL)
    updateNumericInput(session, "threshold", value = 5)
  })

  # observeEvent - save action with side effect
  observeEvent(input$save_btn, {
    data <- filtered()
    rv(data)
    write.csv(data, "output.csv")  # side effect - should be flagged
  })

  output$status <- renderText({
    if (is.null(rv())) "No data saved." else paste("Saved", nrow(rv()), "rows.")
  })

  output$filtered_table <- renderTable({
    filtered()
  })

}

shinyApp(ui, server)
```

**Expected parse results:**

```r
# Contexts: 6
#   rv              -> state_val
#   filtered        -> reactive
#   observe_reset   -> observe_event
#   observe_save    -> observe_event  (flags: possible_side_effect)
#   status          -> output_render
#   filtered_table  -> output_render

# State nodes: rv - symbol_type = "state_val" (NOT "input_ref")

# References in observe_save:
#   filtered()    -> reactive_read
#   rv(data)      -> state_write
#   write.csv()   -> function_call, flag: possible_side_effect

# References in observe_reset:
#   rv(NULL)             -> state_write
#   updateNumericInput() -> ui_update_call

# References in status:
#   rv()          -> state_read

# Issues: 1
#   severity: "info"
#   issue_type: "unsupported_pattern"  (write.csv side effect flagged)
```

---

### Fixture 3: `source_chain`

`tests/fixtures/source_chain/app.R`

```r
library(shiny)

source("helpers.R")
source("data_utils.R")

ui <- fluidPage(
  selectInput("metric", "Metric", choices = c("mpg", "hp", "wt")),
  plotOutput("metric_plot"),
  tableOutput("metric_table")
)

server <- function(input, output, session) {

  processed <- reactive({
    prepare_data(mtcars, input$metric)
  })

  output$metric_plot <- renderPlot({
    plot_metric(processed(), input$metric)
  })

  output$metric_table <- renderTable({
    format_table(processed())
  })

}

shinyApp(ui, server)
```

`tests/fixtures/source_chain/helpers.R`

```r
# Plot utility - used in 1 reactive context
plot_metric <- function(df, metric) {
  barplot(df[[metric]], main = paste("Distribution of", metric))
}

# Table utility - used in 1 reactive context
format_table <- function(df) {
  head(df, 10)
}
```

`tests/fixtures/source_chain/data_utils.R`

```r
# Core data prep - used in 1 reactive context
# Higher usage would increase visual weight
prepare_data <- function(df, metric) {
  df <- df[!is.na(df[[metric]]), ]
  df[order(df[[metric]]), ]
}
```

**Expected parse results:**

```r
# Files parsed: 3 (app.R, helpers.R, data_utils.R)
# source() chain resolved: app.R -> helpers.R, app.R -> data_utils.R

# Symbols from sourced files carry source_file metadata:
#   plot_metric   -> helper_fn, file_id = "file_002" (helpers.R)
#   format_table  -> helper_fn, file_id = "file_002" (helpers.R)
#   prepare_data  -> helper_fn, file_id = "file_003" (data_utils.R)

# Contexts: 3 (processed, metric_plot, metric_table) + 3 helper fns

# References:
#   processed -> prepare_data()  -> function_call, resolved = TRUE
#   processed -> input$metric    -> input_read
#   metric_plot -> plot_metric() -> function_call, resolved = TRUE
#   metric_plot -> processed()   -> reactive_read
#   metric_plot -> input$metric  -> input_read
#   metric_table -> format_table() -> function_call, resolved = TRUE
#   metric_table -> processed()  -> reactive_read

# usage_count:
#   prepare_data: 1
#   plot_metric:  1
#   format_table: 1

# Issues: 0
# Unresolved: 0
```

---

## 5. Sprint 1 Task Checklist

Goal: `analyze_shiny_file("app.R")` returns a trusted internal model.
No viewer. No modules. No `source()`. No D3.

---

### Package Setup

- [ ] `usethis::create_package("shinybrain")`
- [ ] Create directory structure: `R/io/`, `R/parse/`, `R/ir/`, `R/resolve/`, `R/graph/`, `R/brain/`, `R/utils/`
- [ ] Create `tests/fixtures/` with the 3 fixture apps above
- [ ] Add dependencies to `DESCRIPTION`: `tibble`, `rlang`, `utils`, `stringr`
- [ ] Set up `testthat` with `usethis::use_testthat()`

---

### IR Constructors

- [ ] Write `new_sb_project()` - returns empty validated tibble
- [ ] Write `new_sb_file()` - returns empty validated tibble
- [ ] Write `new_sb_context()` - returns empty validated tibble
- [ ] Write `new_sb_symbol()` - returns empty validated tibble
- [ ] Write `new_sb_reference()` - returns empty validated tibble
- [ ] Write `new_sb_node_candidate()` - returns empty validated tibble
- [ ] Write `new_sb_edge_candidate()` - returns empty validated tibble
- [ ] Write `new_sb_issue()` - returns empty validated tibble
- [ ] Write `validate_ir()` - checks required columns and types exist
- [ ] Test: each constructor produces expected column names and types

---

### IO Layer

- [ ] Write `load_file(path, project_id, role, source_line)`
- [ ] Test: loads file, populates `sb_file` row, handles missing file gracefully with `sb_issue`

---

### Parse Layer - Pass 1 & 2

- [ ] Write `parse_raw()` - wraps `parse()` + `getParseData()`; handles parse errors, returns issue on failure
- [ ] Write `scan_top_level()` - identifies assignments, function defs, function calls, `source()` calls
- [ ] Test with fixture 1: correct number of top-level expressions found

---

### Parse Layer - Pass 3: Context Extraction

- [ ] Detect `reactive({ })` assignments → `context_type = "reactive"`
- [ ] Detect `output$x <- render*({ })` → `context_type = "output_render"`, label = output ID
- [ ] Detect `observe({ })` → `context_type = "observer"`
- [ ] Detect `observeEvent(trigger, { })` → `context_type = "observe_event"`
- [ ] Detect `eventReactive(trigger, { })` → `context_type = "event_reactive"`
- [ ] Detect named function definitions → `context_type = "helper_fn"`
- [ ] Detect `reactiveVal()` → `context_type = "state_val"`
- [ ] Detect `reactiveValues()` → `context_type = "state_values"`
- [ ] Populate `line_start`, `line_end`, `label`, `qualified_name` for each
- [ ] Test with fixture 1: 6 contexts extracted with correct types
- [ ] Test with fixture 2: `rv` classified as `state_val`, not as input

---

### Parse Layer - Pass 4: Reference Extraction

- [ ] Extract `input$x` references → `reference_type = "input_read"`
- [ ] Extract `output$x <-` references → `reference_type = "output_write"`
- [ ] Extract named function calls present in project → `reference_type = "function_call"`
- [ ] Extract reactive invocations `name()` → `reference_type = "reactive_read"`
- [ ] Extract `rv()` reads → `reference_type = "state_read"`
- [ ] Extract `rv(val)` writes → `reference_type = "state_write"`
- [ ] Detect `isolate({ })` blocks → mark enclosed references `is_isolated = TRUE`
- [ ] Detect `write.*`, `save*`, `db*`, `POST`, `httr` calls → set flag `possible_side_effect`
- [ ] Detect `update*Input()` calls → `reference_type = "ui_update_call"`
- [ ] Test with fixture 1: all references extracted with correct types and targets
- [ ] Test with fixture 2: `write.csv` flagged, `rv(data)` classified as `state_write`

---

### Pass 5: Snippets

- [ ] Write `extract_snippet()` - extracts lines `line_start:line_end` from code, trims to `max_lines`
- [ ] Test: snippet matches expected lines for each fixture context

---

### Resolve Layer

- [ ] Write `resolve_references()` - links `target_text` to `symbol_id` where match found in `sb_symbol`
- [ ] Unmatched references get `unresolved_reason` from taxonomy
- [ ] Test with fixture 1: all helper function calls resolve to correct symbol IDs
- [ ] Test with fixture 2: `rv` reads/writes resolve correctly

---

### Graph Layer

- [ ] Write `build_nodes()` - promotes `sb_context` rows to `sb_node_candidate`
- [ ] Write `build_edges()` - derives `sb_edge_candidate` from resolved `sb_reference`
- [ ] Write `compute_usage_weights()` - calculates `usage_count` for helper_fn nodes
- [ ] Write `validate_graph()` - checks no orphan edges, no duplicate node IDs
- [ ] Test with fixture 1: correct node count (6), edge count, usage_count for `clean_data`
- [ ] Test with fixture 2: state node present, write/read edges present

---

### `analyze_shiny_file()` Integration

- [ ] Wire all passes end to end
- [ ] Return named list: `list(project, files, contexts, symbols, references, nodes, edges, issues)`
- [ ] Test with all 3 fixtures: summary counts match expected values
- [ ] Test: unsupported construct produces `sb_issue` row, does not crash

---

### Failure Mode Tests

- [ ] File not found → informative error, not crash
- [ ] Unparseable R code → `parse_success = FALSE` + `sb_issue`, rest of pipeline continues
- [ ] Empty file → 0 contexts, 0 symbols, no crash
- [ ] File with only `library()` calls → 0 contexts, 0 symbols, no crash
- [ ] `input[[paste0("x", i)]]` → `unresolved_reason = "dynamic_input_id"`, not crash

---

### Sprint 1 Acceptance Criteria

Given `analyze_shiny_file("tests/fixtures/basic_single_file/app.R")`:

- [ ] Returns a list with all 8 named tibbles
- [ ] `nrow(contexts) == 6`
- [ ] `nrow(symbols) >= 6`
- [ ] All `output_render` contexts have non-NA `label`
- [ ] `reactive` contexts have `input$year` and `input$region` as extracted references
- [ ] `clean_data` helper has `usage_count == 1`
- [ ] `nrow(issues) == 0`
- [ ] No unresolved references
- [ ] Test suite passes with 0 failures

---

*End of ShinyBrain v0.1 Build Package*
