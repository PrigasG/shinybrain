#' @title Insights Layer
#' @description Analyze the resolved IR for developer-facing findings:
#'   dead reactives, unguarded side effects, complex outputs, fan-out helpers,
#'   and a composite complexity score.
#' @name insights_layer
NULL

# Side-effect detection uses SIDE_EFFECT_FNS / SIDE_EFFECT_PATTERNS and
# is_side_effect_call() defined in R/parse/parse.R. They live in the same
# package namespace so lexical scope resolves them at call time.

# ---- Main entry point -------------------------------------------------------

#' Generate developer-facing insights from resolved IR
#'
#' @param nodes sb_node_candidate tibble
#' @param edges sb_edge_candidate tibble
#' @param references sb_reference tibble (resolved)
#' @param contexts sb_context tibble
#' @param issues sb_issue tibble
#' @return Tibble with columns: category, severity, label, message,
#'   recommendation, score
#' @export
generate_insights <- function(nodes, edges, references, contexts, issues) {
  found <- list()
  incoming_counts <- if (nrow(edges) > 0) table(edges$to_node_id) else integer()
  outgoing_counts <- if (nrow(edges) > 0) table(edges$from_node_id) else integer()

  # 1. Dead reactives: reactive/event_reactive with no consumers
  reactive_nodes <- nodes[nodes$node_type == "reactive", ]
  reactive_usage <- vapply(reactive_nodes$node_id, .edge_count, 0L, counts = outgoing_counts)
  dead_r <- reactive_nodes[reactive_usage == 0L, ]
  for (i in seq_len(nrow(dead_r))) {
    found[[length(found) + 1]] <- .insight(
      "dead_reactive", "warning", dead_r$label[i],
      paste0(
        "'", dead_r$label[i], "' is computed but never consumed by any ",
        "output or other reactive; it will never invalidate after startup."
      ),
      recommendation = paste0(
        "Remove '", dead_r$label[i],
        "' if it is obsolete, or connect it to an output or downstream reactive ",
        "if it is meant to participate in the app flow."
      )
    )
  }

  # 1b. Reactive hotspots: heavily reused reactive/state nodes become
  # architectural chokepoints.
  hotspot_nodes <- nodes[
    nodes$node_type %in% c("reactive", "state") &
      vapply(nodes$node_id, .edge_count, 0L, counts = outgoing_counts) >= 3L,
  ]
  for (i in seq_len(nrow(hotspot_nodes))) {
    downstream_count <- .edge_count(hotspot_nodes$node_id[i], outgoing_counts)
    noun <- if (hotspot_nodes$node_type[i] == "state") "state object" else "reactive"
    found[[length(found) + 1]] <- .insight(
      "reactive_hotspot", "warning", hotspot_nodes$label[i],
      paste0(
        "The ", noun, " '", hotspot_nodes$label[i], "' feeds ",
        downstream_count,
        " downstream nodes, making it a likely maintenance and invalidation hotspot."
      ),
      recommendation = paste0(
        "Review whether '", hotspot_nodes$label[i],
        "' should be split into smaller responsibilities, cached, or wrapped ",
        "behind helper reactives with narrower consumers."
      )
    )
  }

  # 2. Unguarded side effects: function calls matching side-effect patterns
  #    inside reactive contexts, without isolate() protection
  if (nrow(references) > 0) {
    fn_refs <- references[
      references$reference_type == "function_call" &
      !references$is_isolated &
      vapply(references$target_text, is_side_effect_call, logical(1)),
    ]
    if (nrow(fn_refs) > 0) {
      # Deduplicate by context + function name
      fn_refs <- fn_refs[!duplicated(paste0(fn_refs$from_context_id,
                                             ":", fn_refs$target_text)), ]
      for (i in seq_len(nrow(fn_refs))) {
        ctx_label <- .label_for_context(fn_refs$from_context_id[i], nodes)
        found[[length(found) + 1]] <- .insight(
          "unguarded_side_effect", "warning", ctx_label,
          paste0(
            "'", fn_refs$target_text[i], "()' inside '", ctx_label,
            "' is a side effect not wrapped in isolate(); it will re-run ",
            "on every reactive invalidation cycle."
          ),
          recommendation = paste0(
            "Check whether '", fn_refs$target_text[i],
            "()' belongs in an observer, behind an explicit event trigger, ",
            "or inside isolate() to avoid accidental repeated execution."
          )
        )
      }
    }
  }

  # 3. High fan-out helpers: helpers called by 3+ contexts
  helper_nodes <- nodes[nodes$node_type == "helper_fn" &
                          vapply(nodes$node_id, .edge_count, 0L, counts = incoming_counts) >= 3L, ]
  for (i in seq_len(nrow(helper_nodes))) {
    helper_usage <- .edge_count(helper_nodes$node_id[i], incoming_counts)
    found[[length(found) + 1]] <- .insight(
      "high_fan_out", "info", helper_nodes$label[i],
      paste0(
        "Helper '", helper_nodes$label[i], "' is called by ",
        helper_usage,
        " contexts; changes to this function will propagate widely."
      ),
      recommendation = paste0(
        "Keep '", helper_nodes$label[i],
        "' small and stable, and consider extracting sub-helpers if it is ",
        "accumulating multiple responsibilities."
      )
    )
  }

  # 4. Complex outputs: output nodes with 4+ incoming edges
  if (nrow(edges) > 0) {
    output_nodes <- nodes[nodes$node_type == "output", ]
    if (nrow(output_nodes) > 0) {
      for (i in seq_len(nrow(output_nodes))) {
        n <- .edge_count(output_nodes$node_id[i], incoming_counts)
        if (n >= 4L) {
          found[[length(found) + 1]] <- .insight(
            "complex_output", "info", output_nodes$label[i],
            paste0(
              "'", output_nodes$label[i], "' depends on ", n,
              " upstream nodes; consider caching expensive upstream ",
              "reactives with reactive() to avoid redundant re-computation."
            ),
            recommendation = paste0(
              "Inspect the dependency chain for '", output_nodes$label[i],
              "' and move expensive or repeated work into dedicated upstream reactives."
            )
          )
        }
      }
    }
  }

  # 5. Isolate usage note: contexts that contain isolate() blocks
  if (nrow(nodes) > 0 && "contains_isolate" %in% names(nodes)) {
    iso_nodes <- nodes[!is.na(nodes$contains_isolate) &
                         nodes$contains_isolate, ]
    if (nrow(iso_nodes) > 0) {
      found[[length(found) + 1]] <- .insight(
        "isolate_usage", "info",
        paste(iso_nodes$label, collapse = ", "),
        paste0(
          nrow(iso_nodes), " context(s) use isolate() to break reactive ",
          "dependencies (", paste(iso_nodes$label, collapse = ", "),
          "). Verify these reads are intentionally non-reactive."
        ),
        recommendation = "Review each isolate() block to make sure the non-reactive read is intentional and documented."
      )
    }
  }

  # 6. Parse/file errors surfaced from issues table
  hard <- issues[!is.na(issues$severity) &
                   issues$severity == "error" &
                   issues$issue_type %in% c("parse_failure", "missing_file"), ]
  for (i in seq_len(nrow(hard))) {
    found[[length(found) + 1]] <- .insight(
      "parse_error", "error",
      if (!is.na(hard$file_id[i])) basename(hard$file_id[i]) else "project",
      hard$message[i],
      recommendation = "Fix the missing or unparseable file first; downstream analysis is less reliable until the source tree is complete."
    )
  }

  if (length(found) == 0) {
    return(tibble::tibble(
      category = character(),
      severity = character(),
      label    = character(),
      message  = character(),
      recommendation = character(),
      score = integer()
    ))
  }

  insights <- tibble::tibble(
    category = vapply(found, `[[`, "", "category"),
    severity = vapply(found, `[[`, "", "severity"),
    label    = vapply(found, `[[`, "", "label"),
    message  = vapply(found, `[[`, "", "message"),
    recommendation = vapply(found, `[[`, "", "recommendation"),
    score = vapply(found, `[[`, 0L, "score")
  )

  insights[order(-insights$score, insights$label), , drop = FALSE]
}

# ---- Complexity scoring -----------------------------------------------------

#' Compute a composite complexity score for the app
#'
#' Returns a list with `score` (0-100) and `label` (Low/Moderate/High/Complex).
#' @param nodes sb_node_candidate tibble
#' @param edges sb_edge_candidate tibble
#' @param insights Insights tibble from generate_insights()
#' @export
compute_complexity <- function(nodes, edges, insights) {
  n_nodes <- nrow(nodes)
  n_edges <- nrow(edges)
  n_se    <- if (nrow(insights) > 0)
    sum(insights$category == "unguarded_side_effect") else 0L

  nodes_score <- min(n_nodes / 25 * 40, 40)
  edges_score <- min(n_edges / 50 * 30, 30)
  se_score    <- min(n_se * 5, 20)
  depth_score <- min(.max_chain_depth(nodes, edges) / 6 * 10, 10)

  score <- round(nodes_score + edges_score + se_score + depth_score)
  label <- dplyr_free_cut(score,
                          breaks = c(0, 25, 50, 75, 100),
                          labels = c("Low", "Moderate", "High", "Complex"))
  list(score = as.integer(score), label = label)
}

# Simple cut without dplyr
dplyr_free_cut <- function(x, breaks, labels) {
  for (i in seq_along(labels)) {
    if (x <= breaks[i + 1]) return(labels[i])
  }
  labels[length(labels)]
}

# ---- Longest reactive chain ------------------------------------------------

#' Compute the longest dependency chain depth (input to output hop count)
#'
#' Internal helper. Exported only for brain layer use inside the package.
#' @param nodes sb_node_candidate tibble
#' @param edges sb_edge_candidate tibble
#' @return Integer
#' @keywords internal
.max_chain_depth <- function(nodes, edges) {
  if (nrow(edges) == 0 || nrow(nodes) == 0) return(0L)

  # Build adjacency list
  adj <- list()
  for (i in seq_len(nrow(edges))) {
    from <- edges$from_node_id[i]
    to   <- edges$to_node_id[i]
    adj[[from]] <- c(adj[[from]], to)
  }

  # Memoized DFS; cycle-safe via visiting set.
  memo <- new.env(parent = emptyenv())

  dfs <- function(id, visiting) {
    if (id %in% visiting) return(0L)
    cached <- memo[[id]]
    if (!is.null(cached)) return(cached)
    children <- adj[[id]]
    if (is.null(children) || length(children) == 0L) {
      memo[[id]] <- 0L
      return(0L)
    }
    d <- 1L + max(vapply(children, dfs, 0L, visiting = c(visiting, id)))
    memo[[id]] <- d
    d
  }

  seeds <- nodes$node_id[nodes$node_type == "input"]
  if (length(seeds) == 0L) seeds <- nodes$node_id
  depths <- vapply(seeds, dfs, 0L, visiting = character())
  if (length(depths) == 0L) 0L else max(depths)
}

# ---- Helpers ----------------------------------------------------------------

.insight <- function(category, severity, label, message, recommendation = NULL) {
  recommendation <- recommendation %||% .default_recommendation(category, label)
  list(
    category = category,
    severity = severity,
    label = label,
    message = message,
    recommendation = recommendation,
    score = .insight_score(category, severity)
  )
}

.label_for_context <- function(context_id, nodes) {
  if (is.na(context_id)) return("unknown")
  hit <- nodes$label[!is.na(nodes$context_id) &
                       nodes$context_id == context_id]
  if (length(hit) > 0) hit[1] else "unknown"
}

.edge_count <- function(node_id, counts) {
  n <- unname(counts[as.character(node_id)])
  if (length(n) == 0L || is.na(n)) 0L else as.integer(n[[1]])
}

.default_recommendation <- function(category, label) {
  switch(
    category,
    dead_reactive = paste0("Remove or reconnect '", label, "' so it has a clear consumer."),
    reactive_hotspot = paste0("Split or narrow '", label, "' so fewer downstream nodes depend on it."),
    unguarded_side_effect = paste0("Move side effects around '", label, "' behind explicit events or isolate() where appropriate."),
    high_fan_out = paste0("Keep '", label, "' stable and consider smaller helper boundaries."),
    complex_output = paste0("Pull shared work for '", label, "' into dedicated upstream reactives."),
    isolate_usage = "Confirm the isolate() boundary is intentional.",
    parse_error = "Repair the source tree before trusting deeper architecture findings.",
    "Review this finding and decide whether it needs a structural change."
  )
}

.insight_score <- function(category, severity) {
  severity_base <- switch(
    severity,
    error = 95L,
    warning = 70L,
    info = 40L,
    30L
  )

  category_bonus <- switch(
    category,
    parse_error = 5L,
    unguarded_side_effect = 15L,
    reactive_hotspot = 12L,
    dead_reactive = 8L,
    complex_output = 6L,
    high_fan_out = 4L,
    isolate_usage = 0L,
    0L
  )

  as.integer(severity_base + category_bonus)
}
