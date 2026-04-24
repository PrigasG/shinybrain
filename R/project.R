#' @title Source Resolution and Multi-File Project Support
#' @description
#' Phase B: resolve source() chains, detect project entry points,
#' and analyze full project folders into a merged IR.
#' @name phase_b
NULL

# ---- source() call detection ------------------------------------------

#' Extract static source() call paths from parse data
#'
#' Only resolves string-literal paths. Dynamic paths produce issues.
#'
#' @param parse_data Data frame from getParseData()
#' @param calling_file_path Absolute path of the file containing the call
#' @param project_id Project ID
#' @param file_id File ID
#' @return Named list: list(paths = character vector, issues = sb_issue tibble)
extract_source_calls <- function(parse_data, calling_file_path,
                                 project_id, file_id) {
  resolved_paths <- character()
  missing_paths  <- character()
  missing_lines  <- integer()
  issues         <- new_sb_issue()

  if (is.null(parse_data) || nrow(parse_data) == 0) {
    return(list(
      paths = resolved_paths,
      missing_paths = missing_paths,
      missing_lines = missing_lines,
      issues = issues
    ))
  }

  # Find SYMBOL_FUNCTION_CALL tokens with text "source"
  source_calls <- parse_data[
    parse_data$token == "SYMBOL_FUNCTION_CALL" & parse_data$text == "source", ]

  if (nrow(source_calls) == 0) {
    return(list(
      paths = resolved_paths,
      missing_paths = missing_paths,
      missing_lines = missing_lines,
      issues = issues
    ))
  }

  calling_dir <- dirname(calling_file_path)

  for (i in seq_len(nrow(source_calls))) {
    sc_row <- source_calls[i, ]

    # Walk up to the call expr
    call_expr <- .walk_up_to_call_expr(sc_row$id, parse_data)
    if (is.null(call_expr)) next

    # Find STR_CONST children (the path argument)
    call_children <- parse_data[parse_data$parent == call_expr$id, ]
    # STR_CONST may be nested inside an expr child
    str_tokens <- .find_str_const(call_expr$id, parse_data)

    if (length(str_tokens) == 0) {
      # Dynamic source path: no string literal was found as the argument.
      issues <- rbind(issues, make_issue(
        project_id = project_id,
        severity   = "warning",
        issue_type = "unsupported_pattern",
        message    = paste0(
          "Dynamic source() path in ", basename(calling_file_path),
          " at line ", sc_row$line1,
          ". The argument is computed at runtime (e.g. paste0(), file.path(), ",
          "a variable) and cannot be resolved statically. The referenced file ",
          "will not appear in the graph. To include it, replace the argument ",
          "with a bare string literal, or call analyze_shiny_project() on the ",
          "directory that already contains the sourced file."
        ),
        file_id    = file_id,
        line_start = as.integer(sc_row$line1)
      ))
      next
    }

    # Clean the string literal (remove surrounding quotes)
    raw_path  <- str_tokens[1]
    rel_path  <- gsub('^["\']|["\']$', "", raw_path)

    # Validate that the source path argument is a bare string literal,
    # not a function call like paste0("R/", "helpers.R").
    # Find the first argument: expr children AFTER the '(' token.
    call_children <- parse_data[parse_data$parent == call_expr$id, ]
    paren_pos <- which(call_children$token == "'('")
    is_dynamic_path <- FALSE
    if (length(paren_pos) > 0) {
      after_paren <- call_children[(paren_pos[1] + 1):nrow(call_children), , drop = FALSE]
      first_arg_exprs <- after_paren[after_paren$token == "expr", ]
      if (nrow(first_arg_exprs) > 0) {
        arg_children <- parse_data[parse_data$parent == first_arg_exprs$id[1], ]
        # Check direct children AND grandchildren for function calls (catches paste0)
        arg_grandchildren <- parse_data[parse_data$parent %in% arg_children$id, ]
        all_arg_tokens <- rbind(arg_children, arg_grandchildren)
        if (any(all_arg_tokens$token == "SYMBOL_FUNCTION_CALL")) {
          is_dynamic_path <- TRUE
        }
      }
    }

    if (is_dynamic_path) {
      issues <- rbind(issues, make_issue(
        project_id = project_id,
        severity   = "warning",
        issue_type = "unsupported_pattern",
        message    = paste0(
          "Dynamic source() path in ", basename(calling_file_path),
          " at line ", sc_row$line1,
          ". The path is built from a function call (e.g. paste0, file.path) ",
          "which shinybrain cannot evaluate without running the app. ",
          "Replace with a bare string literal if you want it included in the graph."
        ),
        file_id    = file_id,
        line_start = as.integer(sc_row$line1)
      ))
      next
    }

    # Resolve path: absolute paths used as-is, relative paths joined to calling dir
    candidate <- if (startsWith(rel_path, "/") || grepl("^[A-Za-z]:", rel_path)) {
      normalizePath(rel_path, mustWork = FALSE)
    } else {
      normalizePath(file.path(calling_dir, rel_path), mustWork = FALSE)
    }

    if (file.exists(candidate)) {
      resolved_paths <- c(resolved_paths, candidate)
    } else {
      missing_paths <- c(missing_paths, candidate)
      missing_lines[candidate] <- as.integer(sc_row$line1)
      issues <- rbind(issues, make_issue(
        project_id = project_id,
        severity   = "warning",
        issue_type = "missing_file",
        message    = paste0(
          "source() target not found: '", rel_path, "' (sourced from ",
          basename(calling_file_path), " line ", sc_row$line1, ")",
          ". Looked in: ", candidate,
          ". Check the path is correct and relative to ",
          basename(calling_file_path), "."
        ),
        file_id    = file_id,
        line_start = as.integer(sc_row$line1)
      ))
    }
  }

  list(
    paths = unique(resolved_paths),
    missing_paths = unique(missing_paths),
    missing_lines = missing_lines[!duplicated(names(missing_lines))],
    issues = issues
  )
}

# Find the first STR_CONST value inside a call expr (recursively, shallow)
.find_str_const <- function(expr_id, pd, depth = 0, max_depth = 3) {
  if (depth > max_depth) return(character())
  children <- pd[pd$parent == expr_id, ]
  str_direct <- children[children$token == "STR_CONST", ]
  if (nrow(str_direct) > 0) return(str_direct$text[1])
  for (child_id in children$id[children$token == "expr"]) {
    result <- .find_str_const(child_id, pd, depth + 1, max_depth)
    if (length(result) > 0) return(result)
  }
  character()
}

# ---- Source chain resolver --------------------------------------------

#' Recursively resolve all source() chains from an entry file
#'
#' Returns files in parse order (entry first, then sourced files DFS).
#' Detects and breaks cycles.
#'
#' @param entry_path Absolute path to entry file
#' @param project_id Project ID
#' @return Named list:
#'   list(ordered_paths = char vector, file_roles = named char vector,
#'        source_lines = named int vector, issues = sb_issue tibble)
#' @export
resolve_source_chain <- function(entry_path, project_id) {
  entry_path <- normalizePath(entry_path, mustWork = FALSE)

  # Mutable state held in an explicit environment to avoid <<- superassignment.
  state <- new.env(parent = emptyenv())
  state$ordered_paths <- character()
  state$file_roles    <- character()   # name = path, value = role
  state$source_lines  <- integer()     # name = path, value = line in parent
  state$all_issues    <- new_sb_issue()
  state$visited_stack <- character()   # for cycle detection

  .resolve_recursive <- function(path, role, parent_line) {
    norm_path <- normalizePath(path, mustWork = FALSE)

    # Cycle detection
    if (norm_path %in% state$visited_stack) {
      # Build a readable chain: a.R -> b.R -> a.R
      chain_names <- vapply(state$visited_stack, basename, character(1))
      cycle_display <- paste(
        c(chain_names, basename(norm_path)),
        collapse = " -> "
      )
      state$all_issues <- rbind(state$all_issues, make_issue(
        project_id = project_id,
        severity   = "error",
        issue_type = "source_cycle",
        message    = paste0(
          "Circular source() chain detected: ", cycle_display,
          ". shinybrain stopped following the chain at the repeat. ",
          "Remove the source() call that closes the loop, or restructure ",
          "shared code into a helper file that neither side sources back."
        ),
        line_start = as.integer(parent_line)
      ))
      return()
    }

    # Already fully processed (sourced from multiple places)
    if (norm_path %in% state$ordered_paths) return()

    if (!file.exists(norm_path)) {
      # Record the missing path so the graph layer can render a ghost node.
      # Severity is "warning" by default; strict mode (handled downstream
      # in analyze_shiny_project via brain_options) can elevate to "error".
      state$ordered_paths           <- c(state$ordered_paths, norm_path)
      state$file_roles[norm_path]   <- "missing"
      state$source_lines[norm_path] <- as.integer(parent_line)
      # When this fires for the entry file, visited_stack is empty and there
      # is no "sourced from" parent to cite. Otherwise name the last parent.
      sourced_from <- if (length(state$visited_stack) > 0) {
        paste0(" (sourced from ", basename(state$visited_stack[
          length(state$visited_stack)]), " line ",
          if (is.na(parent_line)) "?" else parent_line, ")")
      } else {
        " (entry file)"
      }
      state$all_issues <- rbind(state$all_issues, make_issue(
        project_id = project_id,
        severity   = "warning",
        issue_type = "missing_file",
        message    = paste0(
          "Sourced file not found: ", basename(norm_path), sourced_from,
          ". Full path tried: ", norm_path,
          ". A ghost node is shown in the graph so the broken link is visible; ",
          "set brain_options(strict_missing_sources = TRUE) to escalate to an error."
        ),
        line_start = as.integer(parent_line)
      ))
      return()
    }

    state$visited_stack <- c(state$visited_stack, norm_path)

    # Parse just enough to find source() calls
    code   <- paste(readLines(norm_path, warn = FALSE), collapse = "\n")
    pd_raw <- tryCatch({
      exprs <- parse(text = code, keep.source = TRUE)
      utils::getParseData(exprs, includeText = TRUE)
    }, error = function(e) NULL)

    # Add this file first (DFS pre-order)
    state$ordered_paths                  <- c(state$ordered_paths, norm_path)
    state$file_roles[norm_path]          <- role
    state$source_lines[norm_path]        <- as.integer(parent_line)

    # Find and recurse into source() calls
    if (!is.null(pd_raw)) {
      tmp_file_id <- make_id(project_id, norm_path, prefix = "file")
      src <- extract_source_calls(pd_raw, norm_path, project_id, tmp_file_id)
      state$all_issues <- rbind(state$all_issues, src$issues)
      for (child_path in src$paths) {
        .resolve_recursive(child_path, role = "sourced", parent_line = NA_integer_)
      }
      for (child_path in src$missing_paths) {
        parent_line <- src$missing_lines[[child_path]]
        .resolve_recursive(child_path, role = "missing", parent_line = parent_line)
      }
    }

    state$visited_stack <- state$visited_stack[state$visited_stack != norm_path]
  }

  .resolve_recursive(entry_path, role = "entry", parent_line = NA_integer_)

  list(
    ordered_paths = state$ordered_paths,
    file_roles    = state$file_roles,
    source_lines  = state$source_lines,
    issues        = state$all_issues
  )
}

# ---- Project analysis -------------------------------------------------

#' Analyze a full Shiny project directory
#'
#' Detects entry point, resolves source() chains, parses all files,
#' and merges the IR into a single project model.
#'
#' @param path Path to project directory (or path to app.R / server.R)
#' @return Named list with keys:
#'   project, files, contexts, symbols, references, nodes, edges, issues
#' @export
analyze_shiny_project <- function(path) {
  path <- normalizePath(path, mustWork = FALSE)

  # Accept either a directory or a direct file path
  if (file.exists(path) && !dir.exists(path)) {
    return(analyze_shiny_file(path))
  }

  if (!dir.exists(path)) {
    project_id <- make_id(path, prefix = "proj")
    return(list(
      project  = .make_empty_project(project_id, path, "single_file"),
      files    = new_sb_file(),
      contexts = new_sb_context(),
      symbols  = new_sb_symbol(),
      references = new_sb_reference(),
      nodes    = new_sb_node_candidate(),
      edges    = new_sb_edge_candidate(),
      issues   = make_issue(project_id, "error", "missing_file",
                            paste0(
                              "Directory not found: ", path,
                              ". analyze_shiny_project() expects a path to a ",
                              "directory containing app.R (or both ui.R and server.R), ",
                              "or a direct path to a single .R file. Check for typos ",
                              "and that the path is absolute or relative to getwd()."
                            ))
    ))
  }

  ep         <- detect_entry_point(path)
  project_id <- make_id(path, prefix = "proj")

  # Resolve full source chain from each entry file
  all_ordered  <- character()
  all_roles    <- character()
  all_src_lines <- integer()
  all_issues   <- new_sb_issue()

  for (entry_file in ep$files) {
    chain <- resolve_source_chain(entry_file, project_id)
    all_issues    <- rbind(all_issues, chain$issues)

    for (p in chain$ordered_paths) {
      if (!p %in% all_ordered) {
        all_ordered              <- c(all_ordered, p)
        all_roles[p]             <- chain$file_roles[p]
        all_src_lines[p]         <- chain$source_lines[p]
      }
    }
  }

  # Parse and merge all files
  .merge_project_files(
    ordered_paths = all_ordered,
    file_roles    = all_roles,
    source_lines  = all_src_lines,
    project_id    = project_id,
    root_path     = path,
    entry_files   = ep$files,
    entry_type    = ep$type,
    prior_issues  = all_issues
  )
}

# ---- Internal merge ---------------------------------------------------

.merge_project_files <- function(ordered_paths, file_roles, source_lines,
                                  project_id, root_path, entry_files,
                                  entry_type, prior_issues) {

  all_files      <- new_sb_file()
  all_contexts   <- new_sb_context()
  all_references <- new_sb_reference()
  all_issues     <- prior_issues

  for (p in ordered_paths) {
    role <- file_roles[p] %||% "sourced"
    src_line <- source_lines[p]

    loaded <- load_file(p, project_id,
                        role        = role,
                        source_line = src_line)
    all_issues <- rbind(all_issues, loaded$issues)
    file_row   <- loaded$file

    # Set relative path
    rel <- tryCatch(
      .relative_path(p, root_path),
      error = function(e) basename(p)
    )
    file_row$relative_path <- rel

    all_files <- rbind(all_files, file_row)

    if (!isTRUE(file_row$parse_success)) next

    parsed     <- parse_file(file_row)
    all_issues <- rbind(all_issues, parsed$issues)
    all_contexts   <- rbind(all_contexts,   parsed$contexts)
    all_references <- rbind(all_references, parsed$references)
  }

  # Build cross-file symbols and resolve
  symbols <- build_symbols(all_contexts, all_references,
                            file_id    = NA_character_,  # multi-file
                            project_id = project_id)
  # Override file_id for context-backed symbols
  for (i in seq_len(nrow(symbols))) {
    if (!is.na(symbols$context_id[i])) {
      ctx_match <- all_contexts[all_contexts$context_id == symbols$context_id[i], ]
      if (nrow(ctx_match) > 0) symbols$file_id[i] <- ctx_match$file_id[1]
    }
  }

  references <- resolve_references(all_references, symbols, project_id)

  nodes  <- build_nodes(all_contexts, symbols, project_id, files = all_files)
  edges  <- build_edges(references, nodes, symbols, project_id)
  nodes  <- compute_usage_weights(nodes, edges)

  graph_issues <- validate_graph(nodes, edges, project_id)
  all_issues   <- rbind(all_issues, graph_issues)

  project <- tibble::tibble(
    project_id         = project_id,
    root_path          = root_path,
    entry_point_type   = entry_type,
    entry_files        = list(entry_files),
    parse_order        = list(ordered_paths),
    shinybrain_version = tryCatch(
      as.character(utils::packageVersion("shinybrain")),
      error = function(e) "0.1.0"
    ),
    created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  )

  list(
    project    = project,
    files      = all_files,
    contexts   = all_contexts,
    symbols    = symbols,
    references = references,
    nodes      = nodes,
    edges      = edges,
    issues     = all_issues
  )
}

# Compute a path relative to a root
.relative_path <- function(path, root) {
  path <- normalizePath(path, mustWork = FALSE)
  root <- normalizePath(root, mustWork = FALSE)
  if (startsWith(path, root)) {
    rel <- substring(path, nchar(root) + 2)  # +2 for the separator
    if (nchar(rel) == 0) rel <- basename(path)
    return(rel)
  }
  basename(path)
}

.make_empty_project <- function(project_id, root_path, entry_type) {
  tibble::tibble(
    project_id         = project_id,
    root_path          = root_path,
    entry_point_type   = entry_type,
    entry_files        = list(character()),
    parse_order        = list(character()),
    shinybrain_version = "0.1.0",
    created_at         = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  )
}
