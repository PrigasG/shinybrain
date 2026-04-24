#' @title Graph Layer
#' @description Build node and edge candidates from resolved IR.
#' @name graph_layer
NULL

# Map context_type to graph node_type
CONTEXT_TO_NODE_TYPE <- c(
  "reactive"       = "reactive",
  "output_render"  = "output",
  "observer"       = "observer",
  "observe_event"  = "observer",
  "event_reactive" = "reactive",
  "helper_fn"      = "helper_fn",
  "state_val"      = "state",
  "state_values"   = "state",
  "unknown"        = "unknown"
)

# Map reference_type to edge_type
REFERENCE_TO_EDGE_TYPE <- c(
  "input_read"    = "depends_on",
  "reactive_read" = "feeds_into",
  "output_write"  = "feeds_into",
  "state_read"    = "reads_state",
  "state_write"   = "writes_state",
  "function_call" = "calls",
  "event_trigger" = "triggers"
)

# ---- Node construction ------------------------------------------------

#' Promote contexts to graph node candidates
#'
#' Also creates synthetic input nodes from symbols of type "input_ref" and
#' ghost nodes for files marked as missing (role == "missing") so the graph
#' visibly shows broken source() links rather than silently dropping them.
#'
#' @param contexts sb_context tibble
#' @param symbols sb_symbol tibble
#' @param project_id Project ID
#' @param files Optional sb_file tibble used to emit ghost nodes for missing
#'   files. Pass NULL to skip ghost-node emission.
#' @return sb_node_candidate tibble
#' @export
build_nodes <- function(contexts, symbols, project_id, files = NULL) {
  result <- list()

  # Nodes from contexts
  for (i in seq_len(nrow(contexts))) {
    ctx       <- contexts[i, ]
    node_type <- CONTEXT_TO_NODE_TYPE[ctx$context_type]
    if (is.na(node_type)) node_type <- "unknown"

    node_id <- make_id(ctx$context_id, prefix = "node")

    node <- tibble::tibble(
      node_id          = node_id,
      project_id       = project_id,
      context_id       = ctx$context_id,
      node_type        = node_type,
      label            = ctx$label,
      qualified_name   = ctx$qualified_name,
      file_id          = ctx$file_id,
      line_start       = ctx$line_start,
      module_id        = NA_character_,
      confidence       = ctx$confidence,
      contains_isolate = ctx$contains_isolate,
      usage_count      = 0L,
      flags            = ctx$flags,
      snippet          = ctx$snippet
    )
    result[[length(result) + 1]] <- node
  }

  # Synthetic input nodes from input_ref symbols
  input_syms <- symbols[symbols$symbol_type == "input_ref", ]
  for (i in seq_len(nrow(input_syms))) {
    sym     <- input_syms[i, ]
    node_id <- make_id(sym$symbol_id, prefix = "node")

    node <- tibble::tibble(
      node_id          = node_id,
      project_id       = project_id,
      context_id       = NA_character_,
      node_type        = "input",
      label            = sym$name,
      qualified_name   = sym$name,
      file_id          = NA_character_,
      line_start       = NA_integer_,
      module_id        = NA_character_,
      confidence       = "high",
      contains_isolate = FALSE,
      usage_count      = 0L,
      flags            = list(character()),
      snippet          = NA_character_
    )
    result[[length(result) + 1]] <- node
  }

  # Ghost nodes for files flagged as missing by resolve_source_chain
  if (!is.null(files) && nrow(files) > 0 && "role" %in% names(files)) {
    missing_files <- files[!is.na(files$role) & files$role == "missing", ]
    for (i in seq_len(nrow(missing_files))) {
      f       <- missing_files[i, ]
      node_id <- make_id(f$file_id, "missing_file", prefix = "node")
      node    <- tibble::tibble(
        node_id          = node_id,
        project_id       = project_id,
        context_id       = NA_character_,
        node_type        = "missing_file",
        label            = basename(f$path),
        qualified_name   = as.character(f$path),
        file_id          = f$file_id,
        line_start       = NA_integer_,
        module_id        = NA_character_,
        confidence       = "high",
        contains_isolate = FALSE,
        usage_count      = 0L,
        flags            = list(character()),
        snippet          = NA_character_
      )
      result[[length(result) + 1]] <- node
    }
  }

  if (length(result) == 0) return(new_sb_node_candidate())
  do.call(rbind, result)
}

# ---- Edge construction ------------------------------------------------

#' Build edge candidates from resolved references
#'
#' @param references sb_reference tibble (resolved)
#' @param nodes sb_node_candidate tibble
#' @param symbols sb_symbol tibble
#' @param project_id Project ID
#' @return sb_edge_candidate tibble
#' @export
build_edges <- function(references, nodes, symbols, project_id) {
  if (nrow(references) == 0) return(new_sb_edge_candidate())

  # Build lookup: context_id -> node_id
  ctx_to_node <- stats::setNames(nodes$node_id, nodes$context_id)
  # Build lookup: symbol_id -> node_id (via context_id)
  sym_to_node <- .build_symbol_to_node(symbols, nodes)

  result <- list()

  for (i in seq_len(nrow(references))) {
    ref <- references[i, ]

    # Only emit edges for resolved, non-dynamic references
    if (ref$is_dynamic) next

    # Get FROM node (the context containing this reference)
    from_node_id <- ctx_to_node[ref$from_context_id]
    if (is.na(from_node_id)) next

    # Get TO node (the symbol being referenced)
    if (is.na(ref$resolved_symbol_id)) next
    to_node_id <- sym_to_node[ref$resolved_symbol_id]
    if (is.na(to_node_id)) next

    # Skip self-loops
    if (from_node_id == to_node_id) next

    # Determine edge direction based on reference semantics.
    # All references have: from_context_id = CONSUMER, resolved_symbol_id = DEPENDENCY.
    # Graph arrows point FROM source TO consumer for data-flow edges.
    # For call edges, arrow points FROM caller TO callee.
    actual_from <- from_node_id
    actual_to   <- to_node_id

    if (ref$reference_type %in% c("input_read", "reactive_read", "state_read")) {
      # Data flows FROM dependency TO consumer; swap.
      actual_from <- to_node_id
      actual_to   <- from_node_id
    }
    # function_call: caller(from_context) -> callee(resolved_symbol); no swap.
    # state_write:   writer(from_context) -> state(resolved_symbol); no swap.
    # event_trigger: observer(from_context) -> input(resolved_symbol); no swap.

    edge_type <- REFERENCE_TO_EDGE_TYPE[ref$reference_type]
    if (is.na(edge_type)) edge_type <- "unresolved_link"

    edge_id <- make_id(actual_from, actual_to, edge_type, prefix = "edge")

    edge <- tibble::tibble(
      edge_id      = edge_id,
      project_id   = project_id,
      from_node_id = actual_from,
      to_node_id   = actual_to,
      edge_type    = edge_type,
      reference_id = ref$reference_id,
      is_isolated  = ref$is_isolated,
      confidence   = ref$confidence,
      file_id      = if (!is.na(ref$from_context_id)) {
                       ctx_file <- nodes$file_id[nodes$context_id == ref$from_context_id]
                       if (length(ctx_file) > 0) ctx_file[1] else NA_character_
                     } else NA_character_,
      line_start   = ref$line_start,
      flags        = list(character())
    )
    result[[length(result) + 1]] <- edge
  }

  if (length(result) == 0) return(new_sb_edge_candidate())
  # Deduplicate edges by edge_id
  edges <- do.call(rbind, result)
  edges[!duplicated(edges$edge_id), ]
}

# Build lookup: symbol_id -> node_id
.build_symbol_to_node <- function(symbols, nodes) {
  lookup <- character()

  # Context-backed symbols: symbol -> context_id -> node_id
  ctx_backed <- symbols[!is.na(symbols$context_id), ]
  ctx_to_node <- stats::setNames(nodes$node_id, nodes$context_id)

  for (i in seq_len(nrow(ctx_backed))) {
    sym    <- ctx_backed[i, ]
    nid    <- ctx_to_node[sym$context_id]
    if (!is.na(nid)) lookup[sym$symbol_id] <- nid
  }

  # Synthetic input symbols: symbol -> input node (node_id from make_id(symbol_id))
  input_syms <- symbols[symbols$symbol_type == "input_ref", ]
  for (i in seq_len(nrow(input_syms))) {
    sym <- input_syms[i, ]
    nid <- make_id(sym$symbol_id, prefix = "node")
    lookup[sym$symbol_id] <- nid
  }

  lookup
}

# ---- Usage weights ----------------------------------------------------

#' Compute usage_count for helper_fn and state nodes
#'
#' @param nodes sb_node_candidate tibble
#' @param edges sb_edge_candidate tibble
#' @return Updated sb_node_candidate tibble
#' @export
compute_usage_weights <- function(nodes, edges) {
  if (nrow(edges) == 0) return(nodes)

  # Count incoming edges (how many nodes depend on this one)
  incoming <- table(edges$to_node_id)

  for (i in seq_len(nrow(nodes))) {
    nid <- nodes$node_id[i]
    if (nid %in% names(incoming)) {
      nodes$usage_count[i] <- as.integer(incoming[nid])
    }
  }
  nodes
}

# ---- Graph validation -------------------------------------------------

#' Validate graph integrity
#'
#' Checks for: orphan edges, duplicate node IDs, unrecognized node types
#'
#' @param nodes sb_node_candidate tibble
#' @param edges sb_edge_candidate tibble
#' @param project_id Project ID
#' @return sb_issue tibble (empty if no problems)
#' @export
validate_graph <- function(nodes, edges, project_id) {
  issues <- new_sb_issue()

  if (nrow(nodes) == 0) return(issues)

  node_ids <- nodes$node_id

  # Duplicate node IDs
  dupes <- node_ids[duplicated(node_ids)]
  for (d in unique(dupes)) {
    issues <- rbind(issues, make_issue(
      project_id = project_id,
      severity   = "error",
      issue_type = "graph_validation_failure",
      message    = paste0(
        "Internal: duplicate node_id '", d, "' in the graph. ",
        "This is a shinybrain bug - two contexts produced the same node ID. ",
        "Please report it with the offending app, noting that make_id() ",
        "collided for this context."
      )
    ))
  }

  if (nrow(edges) == 0) return(issues)

  # Orphan edges
  all_edge_nodes <- unique(c(edges$from_node_id, edges$to_node_id))
  orphans <- setdiff(all_edge_nodes, node_ids)
  for (o in orphans) {
    issues <- rbind(issues, make_issue(
      project_id = project_id,
      severity   = "warning",
      issue_type = "graph_validation_failure",
      message    = paste0(
        "Internal: edge references unknown node_id '", o,
        "'. The edge will still be rendered but may point nowhere. ",
        "This is a shinybrain bug - build_edges() produced an edge whose ",
        "endpoint was not emitted by build_nodes(). Please report it."
      )
    ))
  }

  issues
}
