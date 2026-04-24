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

fixture3_dir <- testthat::test_path("..", "fixtures", "source_chain")
fixture3     <- testthat::test_path("..", "fixtures", "source_chain", "app.R")

# ===========================================================================
# source() call extraction
# ===========================================================================

test_that("extract_source_calls finds helpers.R and data_utils.R", {
  skip_if_not(file.exists(fixture3), "fixture 3 not found")
  code  <- paste(readLines(fixture3), collapse = "\n")
  exprs <- parse(text = code, keep.source = TRUE)
  pd    <- utils::getParseData(exprs, includeText = TRUE)
  r <- extract_source_calls(pd, fixture3, "proj_test",
                             make_id("proj_test", fixture3, prefix = "file"))
  expect_equal(length(r$paths), 2)
  expect_true(all(file.exists(r$paths)))
  expect_true(any(grepl("helpers",    r$paths)))
  expect_true(any(grepl("data_utils", r$paths)))
})

test_that("dynamic source() produces unsupported_pattern issue", {
  tmp <- tempfile(fileext = ".R")
  writeLines(c('library(shiny)', 'source(paste0("R/", "helpers.R"))'), tmp)
  on.exit(unlink(tmp))
  code  <- paste(readLines(tmp), collapse = "\n")
  exprs <- parse(text = code, keep.source = TRUE)
  pd    <- utils::getParseData(exprs, includeText = TRUE)
  r <- extract_source_calls(pd, tmp, "proj_test", "file_test")
  expect_gte(nrow(r$issues), 1L)
  expect_true(any(r$issues$issue_type == "unsupported_pattern"))
})

# ===========================================================================
# Source chain resolution
# ===========================================================================

test_that("resolve_source_chain returns 3 files in correct order", {
  skip_if_not(file.exists(fixture3), "fixture 3 not found")
  chain <- resolve_source_chain(fixture3, "proj_test")
  expect_equal(length(chain$ordered_paths), 3)
  expect_true(grepl("app\\.R",        chain$ordered_paths[1]))
  expect_true(grepl("helpers\\.R",    chain$ordered_paths[2]))
  expect_true(grepl("data_utils\\.R", chain$ordered_paths[3]))
})

test_that("file roles assigned correctly", {
  skip_if_not(file.exists(fixture3), "fixture 3 not found")
  chain <- resolve_source_chain(fixture3, "proj_test")
  expect_equal(unname(chain$file_roles[chain$ordered_paths[1]]), "entry")
  expect_equal(unname(chain$file_roles[chain$ordered_paths[2]]), "sourced")
  expect_equal(unname(chain$file_roles[chain$ordered_paths[3]]), "sourced")
})

test_that("cycle detection produces source_cycle issue", {
  dir_tmp <- tempdir()
  a <- file.path(dir_tmp, "cycle_a.R")
  b <- file.path(dir_tmp, "cycle_b.R")
  a_src <- gsub("\\\\", "/", a)
  b_src <- gsub("\\\\", "/", b)
  writeLines(c('library(shiny)', sprintf('source("%s")', b_src)), a)
  writeLines(c(sprintf('source("%s")', a_src)), b)
  on.exit({ unlink(a); unlink(b) })
  chain <- resolve_source_chain(a, "proj_cycle")
  expect_true(any(chain$issues$issue_type == "source_cycle"))
})

# ===========================================================================
# analyze_shiny_project: source_chain fixture
# ===========================================================================

test_that("analyze_shiny_project returns all 8 keys", {
  skip_if_not(dir.exists(fixture3_dir), "fixture 3 dir not found")
  r3 <- analyze_shiny_project(fixture3_dir)
  keys <- c("project", "files", "contexts", "symbols",
            "references", "nodes", "edges", "issues")
  expect_true(all(keys %in% names(r3)))
})

test_that("3 files parsed successfully", {
  skip_if_not(dir.exists(fixture3_dir), "fixture 3 dir not found")
  r3 <- analyze_shiny_project(fixture3_dir)
  expect_equal(nrow(r3$files), 3)
  expect_true(all(r3$files$parse_success))
})

test_that("file roles: 1 entry, 2 sourced", {
  skip_if_not(dir.exists(fixture3_dir), "fixture 3 dir not found")
  r3 <- analyze_shiny_project(fixture3_dir)
  expect_equal(sum(r3$files$role == "entry"),   1L)
  expect_equal(sum(r3$files$role == "sourced"), 2L)
})

test_that("helper functions from sourced files detected (>= 3 helpers)", {
  skip_if_not(dir.exists(fixture3_dir), "fixture 3 dir not found")
  r3      <- analyze_shiny_project(fixture3_dir)
  helpers <- r3$contexts[r3$contexts$context_type == "helper_fn", ]
  expect_gte(nrow(helpers), 3L)
  expect_true(any(helpers$label == "plot_metric"))
  expect_true(any(helpers$label == "format_table"))
  expect_true(any(helpers$label == "prepare_data"))
})

test_that("helper symbols carry non-NA file_id", {
  skip_if_not(dir.exists(fixture3_dir), "fixture 3 dir not found")
  r3      <- analyze_shiny_project(fixture3_dir)
  helpers <- r3$symbols[r3$symbols$symbol_type == "helper_fn", ]
  expect_true("plot_metric"  %in% helpers$name)
  expect_true("prepare_data" %in% helpers$name)
  pm <- helpers[helpers$name == "plot_metric", ]
  expect_false(is.na(pm$file_id[1]))
})

test_that("reactive context 'processed' detected from app.R", {
  skip_if_not(dir.exists(fixture3_dir), "fixture 3 dir not found")
  r3        <- analyze_shiny_project(fixture3_dir)
  reactives <- r3$contexts[r3$contexts$context_type == "reactive", ]
  expect_gte(nrow(reactives), 1L)
  expect_true(any(reactives$label == "processed"))
})

test_that("cross-file function calls resolved to sourced file symbols", {
  skip_if_not(dir.exists(fixture3_dir), "fixture 3 dir not found")
  r3       <- analyze_shiny_project(fixture3_dir)
  fn_calls <- r3$references[r3$references$reference_type == "function_call", ]
  resolved <- fn_calls[!is.na(fn_calls$resolved_symbol_id), ]
  expect_true(any(resolved$target_text %in%
                    c("prepare_data", "plot_metric", "format_table")))
})

test_that("prepare_data node has usage_count >= 1", {
  skip_if_not(dir.exists(fixture3_dir), "fixture 3 dir not found")
  r3   <- analyze_shiny_project(fixture3_dir)
  prep <- r3$nodes[r3$nodes$node_type == "helper_fn" &
                     grepl("prepare_data", r3$nodes$label), ]
  expect_gte(nrow(prep), 1L)
  expect_gte(prep$usage_count[1], 1L)
})

test_that("0 error-severity issues in source_chain fixture", {
  skip_if_not(dir.exists(fixture3_dir), "fixture 3 dir not found")
  r3     <- analyze_shiny_project(fixture3_dir)
  errors <- r3$issues[r3$issues$severity == "error", ]
  expect_equal(nrow(errors), 0L)
})

# ===========================================================================
# detect_entry_point
# ===========================================================================

test_that("detect_entry_point identifies app.R", {
  skip_if_not(dir.exists(fixture3_dir), "fixture 3 dir not found")
  ep <- detect_entry_point(fixture3_dir)
  expect_equal(ep$type, "app_r")
  expect_equal(length(ep$files), 1L)
  expect_true(grepl("app\\.R", ep$files[1]))
})

test_that("detect_entry_point identifies ui.R + server.R pair", {
  dir_tmp <- tempdir()
  ui_f <- file.path(dir_tmp, "ui.R")
  sv_f <- file.path(dir_tmp, "server.R")
  writeLines("fluidPage()", ui_f)
  writeLines("function(i,o,s){}", sv_f)
  on.exit({ unlink(ui_f); unlink(sv_f) })
  ep <- detect_entry_point(dir_tmp)
  expect_equal(ep$type, "ui_server_pair")
  expect_equal(length(ep$files), 2L)
})

test_that("analyze_shiny_project with direct file path delegates to analyze_shiny_file", {
  skip_if_not(file.exists(fixture3), "fixture 3 not found")
  r <- analyze_shiny_project(fixture3)
  expect_true("contexts" %in% names(r))
})

# ===========================================================================
# Sprint 1 regression
# ===========================================================================

test_that("Sprint 1 regression: fixture 1 yields 6 contexts", {
  fixture1 <- testthat::test_path("..", "fixtures", "basic_single_file", "app.R")
  skip_if_not(file.exists(fixture1), "fixture 1 not found")
  r1 <- analyze_shiny_file(fixture1)
  expect_equal(nrow(r1$contexts), 6L)
})

test_that("Sprint 1 regression: fixture 1 has 0 hard issues", {
  fixture1 <- testthat::test_path("..", "fixtures", "basic_single_file", "app.R")
  skip_if_not(file.exists(fixture1), "fixture 1 not found")
  r1 <- analyze_shiny_file(fixture1)
  hard <- r1$issues[r1$issues$severity %in% c("error", "warning"), ]
  expect_equal(nrow(hard), 0L)
})
