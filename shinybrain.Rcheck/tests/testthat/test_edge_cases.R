library(testthat)

# Source all R files when the package is not installed; otherwise let library()
# (via testthat.R) provide the functions.
.sb_source_all <- function() {
  r_dir <- testthat::test_path("..", "..", "R")
  if (!dir.exists(r_dir)) return(invisible())
  r_files <- list.files(r_dir, pattern = "\\.R$",
                        recursive = TRUE, full.names = TRUE)
  invisible(lapply(r_files, source))
}
if (!exists("analyze_shiny_file", mode = "function")) .sb_source_all()

# ===========================================================================
# Parse failure handling
# ===========================================================================

test_that("unparseable R code returns parse_failure issue, no crash", {
  tmp <- tempfile(fileext = ".R")
  writeLines(c("library(shiny)", "x <- reactive({ <<<broken"), tmp)
  on.exit(unlink(tmp))
  result <- analyze_shiny_file(tmp)
  expect_true("issues" %in% names(result))
  pf <- result$issues[result$issues$issue_type == "parse_failure", ]
  expect_gte(nrow(pf), 1L)
  expect_equal(pf$severity[1], "error")
  expect_equal(nrow(result$contexts), 0L)
})

# ===========================================================================
# Empty reactive body
# ===========================================================================

test_that("empty reactive body produces a reactive context, no crash", {
  tmp <- tempfile(fileext = ".R")
  writeLines(c(
    "library(shiny)",
    "server <- function(input, output, session) {",
    "  x <- reactive({})",
    "}"
  ), tmp)
  on.exit(unlink(tmp))
  result <- analyze_shiny_file(tmp)
  expect_no_error(analyze_shiny_file(tmp))
  reactives <- result$contexts[result$contexts$context_type == "reactive", ]
  expect_gte(nrow(reactives), 1L)
})

# ===========================================================================
# observe() with no body reference
# ===========================================================================

test_that("observe() with empty body produces observer context, no crash", {
  tmp <- tempfile(fileext = ".R")
  writeLines(c(
    "library(shiny)",
    "server <- function(input, output, session) {",
    "  observe({})",
    "}"
  ), tmp)
  on.exit(unlink(tmp))
  result <- analyze_shiny_file(tmp)
  expect_no_error(analyze_shiny_file(tmp))
  obs <- result$contexts[result$contexts$context_type == "observer", ]
  expect_gte(nrow(obs), 1L)
})

# ===========================================================================
# Multiple reactives in one server
# ===========================================================================

test_that("multiple reactive() assignments all yield separate contexts", {
  tmp <- tempfile(fileext = ".R")
  writeLines(c(
    "library(shiny)",
    "server <- function(input, output, session) {",
    "  a <- reactive({ input$x })",
    "  b <- reactive({ input$y })",
    "  c <- reactive({ a() + b() })",
    "}"
  ), tmp)
  on.exit(unlink(tmp))
  result <- analyze_shiny_file(tmp)
  reactives <- result$contexts[result$contexts$context_type == "reactive", ]
  expect_equal(nrow(reactives), 3L)
  expect_true(all(c("a", "b", "c") %in% reactives$label))
})

# ===========================================================================
# eventReactive detection
# ===========================================================================

test_that("eventReactive() is classified as event_reactive context", {
  tmp <- tempfile(fileext = ".R")
  writeLines(c(
    "library(shiny)",
    "server <- function(input, output, session) {",
    "  result <- eventReactive(input$go, { mean(rnorm(input$n)) })",
    "}"
  ), tmp)
  on.exit(unlink(tmp))
  result <- analyze_shiny_file(tmp)
  ev <- result$contexts[result$contexts$context_type == "event_reactive", ]
  expect_gte(nrow(ev), 1L)
  expect_true(any(ev$label == "result"))
})

# ===========================================================================
# reactiveValues detection
# ===========================================================================

test_that("reactiveValues() is classified as state_values context", {
  tmp <- tempfile(fileext = ".R")
  writeLines(c(
    "library(shiny)",
    "server <- function(input, output, session) {",
    "  vals <- reactiveValues(count = 0, data = NULL)",
    "}"
  ), tmp)
  on.exit(unlink(tmp))
  result <- analyze_shiny_file(tmp)
  sv <- result$contexts[result$contexts$context_type == "state_values", ]
  expect_gte(nrow(sv), 1L)
  expect_true(any(sv$label == "vals"))
})

# ===========================================================================
# Missing source() target
# ===========================================================================

test_that("source() pointing to non-existent file produces missing_file issue", {
  tmp <- tempfile(fileext = ".R")
  writeLines(c(
    'library(shiny)',
    'source("nonexistent_helper.R")',
    'server <- function(input, output, session) {}'
  ), tmp)
  on.exit(unlink(tmp))
  result <- analyze_shiny_file(tmp)
  mf <- result$issues[result$issues$issue_type == "missing_file", ]
  expect_gte(nrow(mf), 1L)
})

# ===========================================================================
# input$ references deduplicated in symbols
# ===========================================================================

test_that("repeated input$x reads produce a single synthetic input_ref symbol", {
  tmp <- tempfile(fileext = ".R")
  writeLines(c(
    "library(shiny)",
    "server <- function(input, output, session) {",
    "  a <- reactive({ input$n + 1 })",
    "  b <- reactive({ input$n * 2 })",
    "}"
  ), tmp)
  on.exit(unlink(tmp))
  result  <- analyze_shiny_file(tmp)
  inp_sym <- result$symbols[result$symbols$symbol_type == "input_ref" &
                              result$symbols$name == "input$n", ]
  expect_equal(nrow(inp_sym), 1L)
})

# ===========================================================================
# Taxonomy constants are coherent
# ===========================================================================

test_that("CONTEXT_TYPES does not contain unimplemented module types", {
  expect_false("module_def"      %in% CONTEXT_TYPES)
  expect_false("module_instance" %in% CONTEXT_TYPES)
})

test_that("SYMBOL_TYPES does not contain unimplemented module types", {
  expect_false("module_def"      %in% SYMBOL_TYPES)
  expect_false("module_instance" %in% SYMBOL_TYPES)
})
