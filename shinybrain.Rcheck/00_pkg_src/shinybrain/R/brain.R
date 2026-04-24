#' @title Brain Builder
#' @description Assembles the portable App Brain object from analysis results.
#'   The brain is a self-contained summary consumed by both the human report
#'   layer and the LLM export layer.
#' @name brain_builder
NULL

#' Brain export options
#'
#' @param include_snippets Logical. Include code snippets in node data.
#' @param snippet_max_lines Integer. Max lines per snippet.
#' @param include_file_paths One of "relative", "basename", or "none".
#' @param include_unresolved Logical. Include unresolved references in export.
#' @param strict_missing_sources Logical. When TRUE, elevates missing-file
#'   warnings (from unresolved `source()` targets) to errors. The ghost node
#'   is still emitted either way.
#' @param verbose Logical. When TRUE, `build_brain()` prints a diagnostic
#'   report of every state-related reference (state_read, state_write,
#'   ambiguous state calls) with its `target_arg_count`. Useful when a
#'   state edge is expected but missing from the graph.
#' @return Named list of options
#' @export
brain_options <- function(
  include_snippets      = TRUE,
  snippet_max_lines     = 15L,
  include_file_paths    = "relative",
  include_unresolved    = TRUE,
  strict_missing_sources = FALSE,
  verbose               = FALSE
) {
  stopifnot(include_file_paths %in% c("relative", "basename", "none"))
  list(
    include_snippets       = include_snippets,
    snippet_max_lines      = as.integer(snippet_max_lines),
    include_file_paths     = include_file_paths,
    include_unresolved     = include_unresolved,
    strict_missing_sources = isTRUE(strict_missing_sources),
    verbose                = isTRUE(verbose)
  )
}

#' Build the App Brain from a ShinyBrain analysis result
#'
#' Assembles analysis output into a portable, self-contained object ready for
#' export (JSON/Markdown for LLMs) or reporting (console/HTML for developers).
#'
#' @param result Named list from analyze_shiny_file() or analyze_shiny_project()
#' @param options brain_options() list
#' @return Named list: project, files, summary, nodes, edges, insights, issues, options
#' @export
build_brain <- function(result, options = brain_options()) {
  nodes    <- result$nodes
  edges    <- result$edges
  refs     <- result$references
  contexts <- result$contexts
  issues   <- result$issues

  # Verbose mode: dump a state-call diagnostic table so we can pinpoint
  # references that were resolved but did not produce an edge, or that
  # came back with an unexpected target_arg_count.
  if (isTRUE(options$verbose)) {
    .dump_state_diagnostics(refs, nodes, edges)
  }

  # Strict mode: elevate missing_file warnings to errors so CI gates can
  # flag them. The ghost node remains in the graph either way.
  if (isTRUE(options$strict_missing_sources) && nrow(issues) > 0) {
    promote <- issues$issue_type == "missing_file" & issues$severity == "warning"
    if (any(promote, na.rm = TRUE)) {
      issues$severity[promote] <- "error"
    }
  }

  # Apply file path option to nodes
  nodes <- .apply_path_option(nodes, options$include_file_paths)

  # Trim snippets
  if (!options$include_snippets) {
    nodes$snippet <- NA_character_
  }

  # Generate insights and complexity
  insights   <- generate_insights(nodes, edges, refs, contexts, issues)
  complexity <- compute_complexity(nodes, edges, insights)
  depth      <- .max_chain_depth(nodes, edges)

  # Node type breakdown
  node_breakdown <- if (nrow(nodes) > 0) {
    as.list(table(nodes$node_type))
  } else list()

  edge_breakdown <- if (nrow(edges) > 0) {
    as.list(table(edges$edge_type))
  } else list()

  n_unresolved <- if (nrow(refs) > 0)
    sum(!is.na(refs$unresolved_reason)) else 0L

  summary <- list(
    n_files        = nrow(result$files),
    n_contexts     = nrow(contexts),
    n_nodes        = nrow(nodes),
    n_edges        = nrow(edges),
    n_symbols      = nrow(result$symbols),
    n_unresolved   = n_unresolved,
    n_issues       = nrow(issues),
    n_insights     = nrow(insights),
    max_chain_depth = depth,
    complexity     = complexity,
    node_breakdown = node_breakdown,
    edge_breakdown = edge_breakdown
  )

  list(
    project  = result$project,
    files    = result$files,
    summary  = summary,
    nodes    = nodes,
    edges    = edges,
    insights = insights,
    issues   = issues,
    options  = options
  )
}

# Apply file path display option to node tibble
.apply_path_option <- function(nodes, mode) {
  if (nrow(nodes) == 0) return(nodes)
  if (mode == "basename") {
    nodes$file_id <- ifelse(is.na(nodes$file_id), NA_character_,
                             basename(nodes$file_id))
  } else if (mode == "none") {
    nodes$file_id <- NA_character_
  }
  nodes
}

# Print a diagnostic table of state-related references.
# Called from build_brain() when options$verbose is TRUE.
# Helps pinpoint dropped state_write edges by showing each state call with
# its target_arg_count, resolved symbol, and whether an edge was emitted.
.dump_state_diagnostics <- function(refs, nodes, edges) {
  if (is.null(refs) || nrow(refs) == 0) {
    message("[shinybrain verbose] no references to diagnose")
    return(invisible(NULL))
  }
  state_types <- c("state_read", "state_write", "function_call")
  probe <- refs[refs$reference_type %in% state_types, , drop = FALSE]
  # Filter function_calls down to those that look like state calls:
  # target_text matches a node labeled as a state symbol.
  state_labels <- if (!is.null(nodes) && nrow(nodes) > 0) {
    nodes$label[nodes$node_type == "state"]
  } else character()
  keep <- probe$reference_type %in% c("state_read", "state_write") |
          probe$target_text %in% state_labels
  probe <- probe[keep, , drop = FALSE]
  if (nrow(probe) == 0) {
    message("[shinybrain verbose] no state-like references found")
    return(invisible(NULL))
  }
  edge_ref_ids <- if (!is.null(edges) && nrow(edges) > 0) edges$reference_id
                  else character()
  message("[shinybrain verbose] state-reference diagnostic:")
  for (i in seq_len(nrow(probe))) {
    r          <- probe[i, ]
    emitted    <- r$reference_id %in% edge_ref_ids
    arg_disp   <- if (is.na(r$target_arg_count)) "NA"
                  else as.character(r$target_arg_count)
    resolved   <- if (is.na(r$resolved_symbol_id)) "<unresolved>"
                  else r$resolved_symbol_id
    reason     <- if (is.na(r$unresolved_reason)) "" else
                  paste0(" reason=", r$unresolved_reason)
    message(sprintf(
      "  %-14s target=%-20s args=%-3s line=%-4s edge=%s resolved=%s%s",
      r$reference_type, r$target_text, arg_disp,
      as.character(r$line_start),
      if (emitted) "yes" else "NO",
      resolved, reason
    ))
  }
  invisible(NULL)
}
