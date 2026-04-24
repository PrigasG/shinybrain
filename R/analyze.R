#' @title ShinyBrain Analysis Functions
#' @description Top-level user-facing functions
#' @name shinybrain_analysis
NULL

#' Analyze a single Shiny R file
#'
#' Runs the full static analysis pipeline on one file and returns
#' all internal representation objects as a named list.
#'
#' @param path Path to the Shiny R file (app.R or equivalent)
#' @return Named list with keys:
#'   project, files, contexts, symbols, references, nodes, edges, issues
#' @export
analyze_shiny_file <- function(path) {
  path <- normalizePath(path, mustWork = FALSE)

  # Project setup
  project_id <- make_id(path, prefix = "proj")
  root_path  <- dirname(path)

  project <- tibble::tibble(
    project_id         = project_id,
    root_path          = root_path,
    entry_point_type   = "single_file",
    entry_files        = list(path),
    parse_order        = list(path),
    shinybrain_version = tryCatch(
      as.character(utils::packageVersion("shinybrain")),
      error = function(e) "0.1.0"
    ),
    created_at         = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  )

  all_issues <- new_sb_issue()

  # IO
  loaded <- load_file(path, project_id, role = "entry")
  all_issues <- rbind(all_issues, loaded$issues)
  file_row   <- loaded$file
  files      <- file_row

  # Set relative_path
  file_row$relative_path <- basename(path)
  files$relative_path    <- basename(path)

  if (!isTRUE(file_row$parse_success)) {
    return(list(
      project    = project,
      files      = files,
      contexts   = new_sb_context(),
      symbols    = new_sb_symbol(),
      references = new_sb_reference(),
      nodes      = new_sb_node_candidate(),
      edges      = new_sb_edge_candidate(),
      issues     = all_issues
    ))
  }

  parsed_raw <- parse_raw(file_row)
  all_issues <- rbind(all_issues, parsed_raw$issues)
  if (!isTRUE(parsed_raw$file$parse_success)) {
    files$parse_success <- parsed_raw$file$parse_success
    files$parse_error   <- parsed_raw$file$parse_error
    return(list(
      project    = project,
      files      = files,
      contexts   = new_sb_context(),
      symbols    = new_sb_symbol(),
      references = new_sb_reference(),
      nodes      = new_sb_node_candidate(),
      edges      = new_sb_edge_candidate(),
      issues     = all_issues
    ))
  }

  src <- extract_source_calls(parsed_raw$parse_data, path, project_id, file_row$file_id)
  all_issues <- rbind(all_issues, src$issues)

  if (length(src$missing_paths) > 0) {
    missing_rows <- lapply(src$missing_paths, function(missing_path) {
      source_line <- src$missing_lines[[missing_path]]
      missing <- load_file(
        missing_path,
        project_id,
        role = "missing",
        source_line = source_line
      )$file
      missing$relative_path <- basename(missing_path)
      missing
    })
    files <- rbind(files, do.call(rbind, missing_rows))
  }

  # Parse
  parsed     <- parse_file(file_row)
  all_issues <- rbind(all_issues, parsed$issues)
  contexts   <- parsed$contexts
  references <- parsed$references

  # Symbols
  symbols <- build_symbols(
    contexts   = contexts,
    references = references,
    file_id    = file_row$file_id,
    project_id = project_id
  )

  # Resolve references
  references <- resolve_references(references, symbols, project_id)

  # Graph
  nodes <- build_nodes(contexts, symbols, project_id, files = files)
  edges <- build_edges(references, nodes, symbols, project_id)
  nodes <- compute_usage_weights(nodes, edges)

  # Graph validation
  graph_issues <- validate_graph(nodes, edges, project_id)
  all_issues   <- rbind(all_issues, graph_issues)

  list(
    project    = project,
    files      = files,
    contexts   = contexts,
    symbols    = symbols,
    references = references,
    nodes      = nodes,
    edges      = edges,
    issues     = all_issues
  )
}

#' Print a concise summary of a ShinyBrain analysis result
#'
#' @param result Named list from analyze_shiny_file()
#' @export
summarize_analysis <- function(result) {
  ctx   <- result$contexts
  nodes <- result$nodes
  edges <- result$edges
  iss   <- result$issues

  cat("ShinyBrain Analysis\n")
  cat("===================\n")
  cat("File:", result$files$relative_path, "\n\n")

  if (nrow(ctx) > 0) {
    type_counts <- table(ctx$context_type)
    cat("Contexts:\n")
    for (nm in names(type_counts)) {
      cat("  ", nm, ":", type_counts[nm], "\n")
    }
  } else {
    cat("Contexts: none\n")
  }

  cat("\nNodes:", nrow(nodes), "\n")
  cat("Edges:", nrow(edges), "\n")

  unresolved <- if (nrow(result$references) > 0) {
    sum(!is.na(result$references$unresolved_reason))
  } else 0L
  cat("Unresolved references:", unresolved, "\n")
  cat("Issues:", nrow(iss[iss$severity != "info", ]), "warnings/errors,",
      nrow(iss[iss$severity == "info", ]), "info\n")

  invisible(result)
}
