library(testthat)

# Source all R files manually when the package is not installed.
# If shinybrain is installed, testthat.R loads it via library() and this block
# becomes a no-op because the functions will already be on the search path.
.sb_source_all <- function() {
  r_dir <- testthat::test_path("..", "..", "R")
  if (!dir.exists(r_dir)) return(invisible())
  r_files <- list.files(r_dir, pattern = "\\.R$",
                        recursive = TRUE, full.names = TRUE)
  invisible(lapply(r_files, source))
}
if (!exists("analyze_shiny_file", mode = "function")) .sb_source_all()

fixture1 <- testthat::test_path("..", "fixtures", "basic_single_file", "app.R")
fixture2 <- testthat::test_path("..", "fixtures", "observer_and_state", "app.R")

# ===========================================================================
# IR Constructors
# ===========================================================================

test_that("IR constructors return tibbles with correct column names", {
  schemas <- list(
    project        = new_sb_project(),
    file           = new_sb_file(),
    context        = new_sb_context(),
    symbol         = new_sb_symbol(),
    reference      = new_sb_reference(),
    node_candidate = new_sb_node_candidate(),
    edge_candidate = new_sb_edge_candidate(),
    issue          = new_sb_issue()
  )

  # All should be tibbles with 0 rows
  for (nm in names(schemas)) {
    expect_true(tibble::is_tibble(schemas[[nm]]),
                info = paste("new_sb_", nm, " should return a tibble"))
    expect_equal(nrow(schemas[[nm]]), 0,
                 info = paste("new_sb_", nm, " should return 0 rows"))
  }

  # Spot-check key columns
  expect_true("project_id"   %in% names(new_sb_project()))
  expect_true("file_id"      %in% names(new_sb_file()))
  expect_true("context_type" %in% names(new_sb_context()))
  expect_true("symbol_type"  %in% names(new_sb_symbol()))
  expect_true("reference_type" %in% names(new_sb_reference()))
  expect_true("node_type"    %in% names(new_sb_node_candidate()))
  expect_true("edge_type"    %in% names(new_sb_edge_candidate()))
  expect_true("issue_type"   %in% names(new_sb_issue()))
})

test_that("validate_ir passes on correct structures", {
  expect_silent(validate_ir(new_sb_project(),        "project"))
  expect_silent(validate_ir(new_sb_file(),           "file"))
  expect_silent(validate_ir(new_sb_context(),        "context"))
  expect_silent(validate_ir(new_sb_symbol(),         "symbol"))
  expect_silent(validate_ir(new_sb_reference(),      "reference"))
  expect_silent(validate_ir(new_sb_node_candidate(), "node_candidate"))
  expect_silent(validate_ir(new_sb_edge_candidate(), "edge_candidate"))
  expect_silent(validate_ir(new_sb_issue(),          "issue"))
})

test_that("validate_ir catches missing columns", {
  bad <- new_sb_context()[, -1]  # remove context_id
  expect_error(validate_ir(bad, "context"), "missing required column")
})

# ===========================================================================
# IO Layer
# ===========================================================================

test_that("load_file succeeds on valid file", {
  result <- load_file(fixture1, "proj_test")
  expect_true(result$file$parse_success)
  expect_true(is.na(result$file$parse_error))
  expect_gt(result$file$line_count, 0)
  expect_equal(nrow(result$issues), 0)
})

test_that("load_file returns issue on missing file", {
  result <- load_file("/nonexistent/path/app.R", "proj_test")
  expect_false(result$file$parse_success)
  expect_equal(nrow(result$issues), 1)
  expect_equal(result$issues$issue_type, "missing_file")
  expect_equal(result$issues$severity, "error")
})

# ===========================================================================
# Fixture 1: basic_single_file
# ===========================================================================

test_that("analyze_shiny_file returns all 8 keys for fixture 1", {
  skip_if_not(file.exists(fixture1), "fixture 1 not found")
  result <- analyze_shiny_file(fixture1)
  expected_keys <- c("project", "files", "contexts", "symbols",
                     "references", "nodes", "edges", "issues")
  expect_true(all(expected_keys %in% names(result)))
})

test_that("fixture 1: exactly 1 file parsed", {
  skip_if_not(file.exists(fixture1), "fixture 1 not found")
  result <- analyze_shiny_file(fixture1)
  expect_equal(nrow(result$files), 1)
  expect_true(result$files$parse_success)
})

test_that("fixture 1: 6 contexts extracted with correct types", {
  skip_if_not(file.exists(fixture1), "fixture 1 not found")
  result   <- analyze_shiny_file(fixture1)
  contexts <- result$contexts

  expect_equal(nrow(contexts), 6,
               info = paste("Got context types:",
                            paste(contexts$context_type, collapse = ", ")))

  type_counts <- table(contexts$context_type)
  expect_equal(as.integer(type_counts["reactive"]),      2L)
  expect_equal(as.integer(type_counts["output_render"]), 3L)
  expect_equal(as.integer(type_counts["helper_fn"]),     1L)
})

test_that("fixture 1: output_render contexts have non-NA labels", {
  skip_if_not(file.exists(fixture1), "fixture 1 not found")
  result   <- analyze_shiny_file(fixture1)
  outputs  <- result$contexts[result$contexts$context_type == "output_render", ]
  expect_true(all(!is.na(outputs$label)))
  expect_true(all(grepl("output\\$", outputs$label)))
})

test_that("fixture 1: at least 8 symbols (6 defined + 2 synthetic inputs)", {
  skip_if_not(file.exists(fixture1), "fixture 1 not found")
  result  <- analyze_shiny_file(fixture1)
  expect_gte(nrow(result$symbols), 8L)
  # Synthetic input refs exist
  input_syms <- result$symbols[result$symbols$symbol_type == "input_ref", ]
  expect_gte(nrow(input_syms), 2L)
})

test_that("fixture 1: clean_data helper has usage_count >= 1", {
  skip_if_not(file.exists(fixture1), "fixture 1 not found")
  result  <- analyze_shiny_file(fixture1)
  helpers <- result$nodes[result$nodes$node_type == "helper_fn", ]
  expect_gte(nrow(helpers), 1L)
  clean_node <- helpers[grepl("clean_data", helpers$label), ]
  expect_gte(nrow(clean_node), 1L)
  expect_gte(clean_node$usage_count[1], 1L)
})

test_that("fixture 1: input references extracted for filtered_data", {
  skip_if_not(file.exists(fixture1), "fixture 1 not found")
  result <- analyze_shiny_file(fixture1)
  refs   <- result$references

  ctx_id <- result$contexts$context_id[result$contexts$label == "filtered_data"]
  if (length(ctx_id) == 0) skip("filtered_data context not found")

  ctx_refs <- refs[refs$from_context_id == ctx_id, ]
  input_reads <- ctx_refs[ctx_refs$reference_type == "input_read", ]
  expect_gte(nrow(input_reads), 1L)
  expect_true(any(grepl("input\\$year", input_reads$target_text)))
})

test_that("fixture 1: 0 issues at error/warning level", {
  skip_if_not(file.exists(fixture1), "fixture 1 not found")
  result <- analyze_shiny_file(fixture1)
  hard   <- result$issues[result$issues$severity %in% c("error", "warning"), ]
  expect_equal(nrow(hard), 0L)
})

test_that("fixture 1: no unresolved references", {
  skip_if_not(file.exists(fixture1), "fixture 1 not found")
  result     <- analyze_shiny_file(fixture1)
  unresolved <- sum(!is.na(result$references$unresolved_reason))
  expect_equal(unresolved, 0L)
})

# ===========================================================================
# Fixture 2: observer_and_state
# ===========================================================================

test_that("fixture 2: rv classified as state_val, not input_ref", {
  skip_if_not(file.exists(fixture2), "fixture 2 not found")
  result <- analyze_shiny_file(fixture2)
  state_ctxs <- result$contexts[result$contexts$context_type == "state_val", ]
  expect_gte(nrow(state_ctxs), 1L)
  expect_true(any(state_ctxs$label == "rv"))
  # Must NOT appear as input_ref
  input_syms <- result$symbols[result$symbols$symbol_type == "input_ref", ]
  expect_false("rv" %in% input_syms$name)
})

test_that("fixture 2: observe_event contexts detected", {
  skip_if_not(file.exists(fixture2), "fixture 2 not found")
  result <- analyze_shiny_file(fixture2)
  obs    <- result$contexts[result$contexts$context_type == "observe_event", ]
  expect_gte(nrow(obs), 2L)
})

test_that("fixture 2: possible_side_effect issue emitted for write.csv", {
  skip_if_not(file.exists(fixture2), "fixture 2 not found")
  result <- analyze_shiny_file(fixture2)
  se_issues <- result$issues[result$issues$issue_type == "possible_side_effect", ]
  expect_gte(nrow(se_issues), 1L)
})

test_that("fixture 2: updateNumericInput captured as ui_update_call", {
  skip_if_not(file.exists(fixture2), "fixture 2 not found")
  result <- analyze_shiny_file(fixture2)
  ui_upd <- result$references[
    result$references$reference_type == "ui_update_call" |
    grepl("updateNumericInput", result$references$target_text), ]
  expect_gte(nrow(ui_upd), 1L)
})

test_that("fixture 2: analysis completes without crash", {
  skip_if_not(file.exists(fixture2), "fixture 2 not found")
  expect_no_error(analyze_shiny_file(fixture2))
})

# ===========================================================================
# Failure modes
# ===========================================================================

test_that("missing file: returns result with error issue, no crash", {
  result <- analyze_shiny_file("/nonexistent/nowhere/app.R")
  expect_true("issues" %in% names(result))
  error_issues <- result$issues[result$issues$severity == "error", ]
  expect_gte(nrow(error_issues), 1L)
})

test_that("empty file: returns 0 contexts and an info issue", {
  tmp <- tempfile(fileext = ".R")
  writeLines("", tmp)
  on.exit(unlink(tmp))
  result <- analyze_shiny_file(tmp)
  expect_equal(nrow(result$contexts), 0L)
  empty_iss <- result$issues[result$issues$issue_type == "empty_file", ]
  expect_gte(nrow(empty_iss), 1L)
})

test_that("library-only file: returns 0 contexts, no crash", {
  tmp <- tempfile(fileext = ".R")
  writeLines(c("library(shiny)", "library(dplyr)"), tmp)
  on.exit(unlink(tmp))
  result <- analyze_shiny_file(tmp)
  expect_equal(nrow(result$contexts), 0L)
  expect_no_error(analyze_shiny_file(tmp))
})

test_that("dynamic input id: unresolved_reason = dynamic_input_id", {
  tmp <- tempfile(fileext = ".R")
  writeLines(c(
    "library(shiny)",
    "server <- function(input, output, session) {",
    "  x <- reactive({ input[[paste0('slider_', 1)]] })",
    "}"
  ), tmp)
  on.exit(unlink(tmp))
  result <- analyze_shiny_file(tmp)
  dyn <- result$references[
    !is.na(result$references$unresolved_reason) &
    result$references$unresolved_reason == "dynamic_input_id", ]
  expect_gte(nrow(dyn), 1L)
})
