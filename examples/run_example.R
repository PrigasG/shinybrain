# Smoke test: runs shinybrain on the two example apps and prints a summary.
# Run from the package root:
#   Rscript examples/run_example.R
# Or, from within an R session with the package loaded:
#   source("examples/run_example.R")

suppressPackageStartupMessages({
  if (!requireNamespace("shinybrain", quietly = TRUE)) {
    # If the package is not installed, source the R files in place so the
    # script still works from a fresh clone.
    pkg_root <- tryCatch(rprojroot::find_package_root_file(),
                         error = function(e) getwd())
    r_files  <- list.files(file.path(pkg_root, "R"),
                           pattern = "\\.R$", full.names = TRUE)
    invisible(lapply(r_files, source))
  } else {
    library(shinybrain)
  }
})

# ---- Locate the examples directory regardless of invocation mode -------
.resolve_examples_dir <- function() {
  # 1) Rscript: commandArgs carries --file=<path>
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", args, value = TRUE)
  if (length(file_arg) > 0) {
    p <- sub("^--file=", "", file_arg[1])
    if (nzchar(p)) return(normalizePath(dirname(p), mustWork = FALSE))
  }
  # 2) source(): sys.frame(1)$ofile
  ofile <- tryCatch(sys.frame(1)$ofile, error = function(e) NULL)
  if (!is.null(ofile) && nzchar(ofile)) {
    return(normalizePath(dirname(ofile), mustWork = FALSE))
  }
  # 3) Fallback: look for examples/ relative to cwd
  cwd <- getwd()
  if (dir.exists(file.path(cwd, "examples"))) {
    return(normalizePath(file.path(cwd, "examples"), mustWork = FALSE))
  }
  cwd
}

run_one <- function(app_dir, label, verbose = FALSE) {
  cat("\n================================================================\n")
  cat("  ", label, "\n")
  cat("  path: ", app_dir, "\n")
  cat("================================================================\n")

  result <- analyze_shiny_project(app_dir)
  brain  <- build_brain(result, options = brain_options(verbose = verbose))

  cat("\n-- project --\n")
  print(result$project[, c("entry_point_type", "shinybrain_version")])

  cat("\n-- files --\n")
  if (nrow(result$files) > 0) {
    print(result$files[, c("role", "relative_path",
                           "parse_success", "line_count")])
  } else {
    cat("(none)\n")
  }

  cat("\n-- nodes --\n")
  if (nrow(result$nodes) > 0) {
    print(result$nodes[, c("label", "node_type", "usage_count")])
  } else {
    cat("(none)\n")
  }

  cat("\n-- edges --\n")
  if (nrow(result$edges) > 0) {
    print(result$edges[, c("from_node_id", "to_node_id", "edge_type")])
  } else {
    cat("(none)\n")
  }

  cat("\n-- issues --\n")
  if (nrow(result$issues) > 0) {
    print(result$issues[, c("severity", "issue_type", "message")])
  } else {
    cat("(none)\n")
  }

  cat("\n-- brain summary --\n")
  print_brain_console(brain)

  invisible(list(result = result, brain = brain))
}

here <- .resolve_examples_dir()

basic_app     <- file.path(here, "basic_app")
edge_case_app <- file.path(here, "edge_case_app")

basic_out <- run_one(basic_app,     "BASIC APP (happy path)",
                     verbose = TRUE)
edge_out  <- run_one(edge_case_app, "EDGE-CASE APP (missing + dynamic source)",
                     verbose = FALSE)

cat("\n================================================================\n")
cat("  Export artifacts for the basic app\n")
cat("================================================================\n")
out_dir <- file.path(tempdir(), "shinybrain_example")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

json_path <- file.path(out_dir, "basic_brain.json")
md_path   <- file.path(out_dir, "basic_brain.md")
html_path <- file.path(out_dir, "basic_brain.html")

export_brain_json(basic_out$brain,     file = json_path)
export_brain_markdown(basic_out$brain, file = md_path)
export_brain_html(basic_out$brain, file = html_path)

cat("\nExported artifacts:\n")
cat("  JSON: ", json_path, "\n")
cat("  MD:   ", md_path,   "\n")
cat("  HTML: ", html_path, "\n")
