#' @title Parse Layer
#' @description Five-pass static parser for Shiny source files.
#'
#' Pass 1: raw parse + parse data
#' Pass 2: top-level expression scanning
#' Pass 3: context extraction
#' Pass 4: intra-context reference extraction
#' Pass 5: snippet extraction
#'
#' @name parse_layer
NULL

# ---- Patterns for side-effect detection --------------------------------

SIDE_EFFECT_PATTERNS <- c(
  "^write\\.", "^db", "^sql",
  "^httr::", "^POST$", "^GET$",
  "^sendMail", "^send_mail",
  "^file\\.remove", "^unlink"
)

# Exact function names that should always be flagged as side effects
# regardless of pattern matching. Shared with the insights layer via
# package lexical scope.
SIDE_EFFECT_FNS <- c(
  "write.csv", "write.table", "writeLines", "saveRDS", "save",
  "dbWriteTable", "dbExecute", "httr::POST", "POST",
  "file.remove", "unlink", "sendMail", "send_mail",
  "message", "print", "cat", "warning", "stop"
)

#' Test whether a call target name matches a known side-effect function or pattern
#' @param name Character scalar. Function name as captured by the parser.
#' @return Logical scalar.
#' @keywords internal
is_side_effect_call <- function(name) {
  if (length(name) != 1L || is.na(name)) return(FALSE)
  name %in% SIDE_EFFECT_FNS ||
    any(vapply(SIDE_EFFECT_PATTERNS,
               function(p) grepl(p, name), logical(1)))
}

# ---- Pass 1: Raw parse -------------------------------------------------

#' Parse a file and attach parse data
#'
#' @param file_row One-row sb_file tibble (code must be populated)
#' @return Named list: list(file = updated sb_file row, issues = sb_issue tibble)
parse_raw <- function(file_row) {
  if (!isTRUE(file_row$parse_success)) {
    return(list(file = file_row, issues = new_sb_issue()))
  }

  code <- file_row$code
  pd   <- tryCatch(
    {
      exprs <- parse(text = code, keep.source = TRUE)
      pd    <- utils::getParseData(exprs, includeText = TRUE)
      list(exprs = exprs, parse_data = pd)
    },
    error = function(e) {
      list(error = conditionMessage(e))
    }
  )

  if (!is.null(pd$error)) {
    file_row$parse_success <- FALSE
    file_row$parse_error   <- pd$error
    # R's parse errors usually carry the form:
    #   "<text>:<line>:<col>: <cause>\n<line number>: <code line>\n..."
    # so file + the raw R message is almost always enough to locate the
    # problem. Surface it with a suggested reproducer.
    nm <- if (!is.na(file_row$path)) basename(file_row$path) else "the file"
    issue <- make_issue(
      project_id = file_row$project_id,
      severity   = "error",
      issue_type = "parse_failure",
      message    = paste0(
        "Could not parse ", nm, " as R code. ",
        "shinybrain skipped this file - no contexts, symbols, or edges were ",
        "extracted from it. R reported: ", pd$error,
        " To reproduce outside shinybrain, run: parse(file = \"",
        if (!is.na(file_row$path)) file_row$path else nm,
        "\")."
      ),
      file_id    = file_row$file_id
    )
    return(list(file = file_row, issues = issue))
  }

  list(
    file       = file_row,
    exprs      = pd$exprs,
    parse_data = pd$parse_data,
    issues     = new_sb_issue()
  )
}

# ---- Pass 2: Top-level scan --------------------------------------------

#' Scan top-level expressions from parse data
#'
#' @param parse_data Data frame from getParseData()
#' @param file_id File ID string
#' @return Tibble of top-level expression records
scan_top_level <- function(parse_data, file_id) {
  if (is.null(parse_data) || nrow(parse_data) == 0) {
    return(tibble::tibble())
  }

  # Find top-level parent tokens (parent == 0 is the root)
  top <- parse_data[parse_data$parent == 0, ]
  if (nrow(top) == 0) return(tibble::tibble())

  # Each child of root is a top-level expression
  top_ids <- top$id
  top_exprs <- parse_data[parse_data$parent %in% top_ids, ]

  tibble::tibble(
    file_id    = file_id,
    token_id   = top_exprs$id,
    token      = top_exprs$token,
    text       = top_exprs$text,
    line_start = as.integer(top_exprs$line1),
    line_end   = as.integer(top_exprs$line2)
  )
}

# Top-level Shiny names that are NOT helper functions
SHINY_ENTRY_NAMES <- c("server", "ui", "shinyApp", "shinyUI", "shinyServer",
                        "app", "App")

# ---- Pass 3: Context extraction ----------------------------------------

#' Extract context objects from parse data
#'
#' Identifies all reactive, observer, output, helper function, and state
#' contexts in the file.
#'
#' @param parse_data Data frame from getParseData()
#' @param code Raw code string
#' @param file_id File ID
#' @param project_id Project ID
#' @return sb_context tibble
extract_contexts <- function(parse_data, code, file_id, project_id) {
  if (is.null(parse_data) || nrow(parse_data) == 0) {
    return(new_sb_context())
  }

  lines  <- strsplit(code, "\n")[[1]]
  result <- list()

  # Walk through all SYMBOL tokens that are function calls
  # Strategy: find assignment expressions, then classify the RHS call

  # Get all expr tokens - look for <- assignments
  assigns <- .find_assignments(parse_data)

  for (a in assigns) {
    ctx <- .classify_assignment(a, parse_data, lines, file_id, project_id)
    if (!is.null(ctx)) result[[length(result) + 1]] <- ctx
  }

  # Also find non-assigned calls: observe(), observeEvent()
  standalone <- .find_standalone_calls(parse_data, lines, file_id, project_id)
  for (s in standalone) result[[length(result) + 1]] <- s

  if (length(result) == 0) return(new_sb_context())
  do.call(rbind, result)
}

# ---- Internal context helpers -----------------------------------------

# Find assignment expressions in parse data
.find_assignments <- function(pd) {
  # LEFT_ASSIGN token marks <- ; EQ_ASSIGN marks =
  assign_rows <- pd[pd$token %in% c("LEFT_ASSIGN", "EQ_ASSIGN"), ]
  lapply(seq_len(nrow(assign_rows)), function(i) {
    row    <- assign_rows[i, ]
    parent <- pd[pd$id == row$parent, ]
    if (nrow(parent) == 0) return(NULL)
    # Siblings of the assign token are the LHS and RHS
    siblings <- pd[pd$parent == parent$id, ]
    list(
      parent_id  = parent$id,
      assign_row = row,
      siblings   = siblings,
      line_start = as.integer(parent$line1),
      line_end   = as.integer(parent$line2)
    )
  })
}

# Classify a single assignment into a context or NULL
.classify_assignment <- function(a, pd, lines, file_id, project_id) {
  if (is.null(a)) return(NULL)
  siblings <- a$siblings
  if (nrow(siblings) < 2) return(NULL)

  # Siblings are direct children of the assignment parent expr.
  # Structure: [LHS_expr, LEFT_ASSIGN, RHS_expr]
  # LHS_expr contains a SYMBOL or output$id pattern one level deeper.
  # We need to separate LHS expr from RHS expr.

  assign_pos <- which(siblings$token %in% c("LEFT_ASSIGN", "EQ_ASSIGN"))
  if (length(assign_pos) == 0) return(NULL)

  lhs_exprs <- siblings[seq_len(assign_pos[1] - 1), , drop = FALSE]
  rhs_exprs <- siblings[(assign_pos[1] + 1):nrow(siblings), , drop = FALSE]

  if (nrow(lhs_exprs) == 0 || nrow(rhs_exprs) == 0) return(NULL)

  # ---- Resolve LHS name ----
  lhs_name  <- NA_character_
  is_output <- FALSE

  # Get direct children of the LHS expr (1 level deep)
  lhs_direct <- pd[pd$parent %in% lhs_exprs$id, ]

  dollar_in_direct <- lhs_direct[lhs_direct$token == "'$'", ]
  if (nrow(dollar_in_direct) > 0) {
    # output$field pattern.
    # Direct children of lhs_exprs$id are: [expr(base), '$', SYMBOL(field)]
    # The field SYMBOL is a direct child; the base SYMBOL is inside the expr child.
    field_sym <- lhs_direct[lhs_direct$token == "SYMBOL", ]
    base_expr  <- lhs_direct[lhs_direct$token == "expr", ]
    base_sym   <- if (nrow(base_expr) > 0) pd[pd$parent == base_expr$id[1] & pd$token == "SYMBOL", ] else data.frame()

    base_name  <- if (nrow(base_sym)  > 0) base_sym$text[1]  else NA_character_
    field_name <- if (nrow(field_sym) > 0) field_sym$text[1] else NA_character_

    if (!is.na(base_name) && base_name == "output" && !is.na(field_name)) {
      is_output <- TRUE
      lhs_name  <- paste0("output$", field_name)
    }
  } else {
    # Simple symbol assignment: filtered_data <- reactive({...})
    # Direct children of lhs_exprs$id should include a SYMBOL
    sym_direct <- lhs_direct[lhs_direct$token %in% c("SYMBOL", "SYMBOL_FUNCTION_CALL"), ]
    if (nrow(sym_direct) > 0) {
      lhs_name <- sym_direct$text[1]
    }
  }

  if (is.na(lhs_name)) return(NULL)

  # ---- Resolve RHS call name ----
  rhs_all <- .descendants(rhs_exprs$id, pd)

  # Check function definition first (FUNCTION keyword as direct child of rhs expr)
  rhs_direct <- pd[pd$parent %in% rhs_exprs$id, ]
  if (any(rhs_direct$token == "FUNCTION")) {
    # Skip well-known Shiny entry-point names
    if (lhs_name %in% SHINY_ENTRY_NAMES) return(NULL)
    return(.make_context_row(
      context_type = "helper_fn",
      label        = lhs_name,
      file_id      = file_id,
      project_id   = project_id,
      line_start   = a$line_start,
      line_end     = a$line_end,
      lines        = lines
    ))
  }

  # The first SYMBOL_FUNCTION_CALL in the RHS is the outer call name
  rhs_direct_calls <- rhs_direct[rhs_direct$token == "SYMBOL_FUNCTION_CALL", ]
  rhs_call <- if (nrow(rhs_direct_calls) > 0) rhs_direct_calls$text[1] else NULL

  # If not in direct children, look one level deeper (handles expr wrapper)
  if (is.null(rhs_call)) {
    rhs_lvl2 <- pd[pd$parent %in% rhs_direct$id[rhs_direct$token == "expr"], ]
    calls_lvl2 <- rhs_lvl2[rhs_lvl2$token == "SYMBOL_FUNCTION_CALL", ]
    if (nrow(calls_lvl2) > 0) rhs_call <- calls_lvl2$text[1]
  }

  if (is.null(rhs_call)) return(NULL)

  ctx_type <- .map_call_to_context(rhs_call, is_output)
  if (is.null(ctx_type)) return(NULL)

  .make_context_row(
    context_type = ctx_type,
    label        = lhs_name,
    file_id      = file_id,
    project_id   = project_id,
    line_start   = a$line_start,
    line_end     = a$line_end,
    lines        = lines
  )
}

# Get all descendant rows for a set of parent IDs (1 level deep = direct children)
# For LHS resolution, we only need 1-2 levels
.descendants <- function(parent_ids, pd, max_depth = 3) {
  result <- pd[0, ]
  current_parents <- parent_ids
  for (i in seq_len(max_depth)) {
    kids <- pd[pd$parent %in% current_parents, ]
    if (nrow(kids) == 0) break
    result <- rbind(result, kids)
    current_parents <- kids$id
  }
  result
}

# Map RHS call name to context_type
.map_call_to_context <- function(call_name, is_output) {
  if (is_output && grepl("^render", call_name)) return("output_render")
  switch(call_name,
    "reactive"       = "reactive",
    "eventReactive"  = "event_reactive",
    "reactiveVal"    = "state_val",
    "reactiveValues" = "state_values",
    NULL  # Not a recognized reactive construct
  )
}

# Find standalone (non-assigned) calls like observe(), observeEvent()
.find_standalone_calls <- function(pd, lines, file_id, project_id) {
  result <- list()
  call_rows <- pd[pd$token == "SYMBOL_FUNCTION_CALL" &
                    pd$text %in% c("observe", "observeEvent"), ]

  for (i in seq_len(nrow(call_rows))) {
    row    <- call_rows[i, ]
    # Walk up to the full call expression (not just the symbol wrapper)
    expr   <- .walk_up_to_call_expr(row$id, pd)
    if (is.null(expr)) next

    # Only process if NOT part of an assignment (parent of parent is not assign)
    grandparent <- pd[pd$id == expr$parent, ]
    if (nrow(grandparent) > 0 &&
        grandparent$token %in% c("LEFT_ASSIGN", "EQ_ASSIGN")) next

    ctx_type <- if (row$text == "observe") "observer" else "observe_event"
    label    <- paste0(row$text, "_", row$line1)

    ctx <- .make_context_row(
      context_type = ctx_type,
      label        = label,
      file_id      = file_id,
      project_id   = project_id,
      line_start   = as.integer(expr$line1),
      line_end     = as.integer(expr$line2),
      lines        = lines
    )
    result[[length(result) + 1]] <- ctx
  }
  result
}

# Walk up parse tree to find the enclosing CALL expression (not just any expr).
# The SYMBOL_FUNCTION_CALL is typically wrapped in a single-line expr node.
# We want the expr that is the full function call (contains '(' as a child).
.walk_up_to_call_expr <- function(id, pd, max_depth = 10) {
  current <- id
  for (i in seq_len(max_depth)) {
    row <- pd[pd$id == current, ]
    if (nrow(row) == 0) return(NULL)
    if (row$parent == 0) return(row)

    parent_row <- pd[pd$id == row$parent, ]
    if (nrow(parent_row) == 0) return(row)

    if (parent_row$token == "expr") {
      # Check if this parent expr is a call expr (has a '(' child)
      siblings <- pd[pd$parent == parent_row$id, ]
      if (any(siblings$token == "'('")) {
        # This is the call expr; return it.
        return(parent_row)
      }
    }
    current <- row$parent
  }
  NULL
}

# Build a single context row
.make_context_row <- function(context_type, label, file_id, project_id,
                               line_start, line_end, lines) {
  snippet <- .extract_lines(lines, line_start, line_end, max_lines = 20)
  context_id <- make_id(file_id, context_type, label,
                         as.character(line_start), as.character(line_end),
                         prefix = "ctx")
  tibble::tibble(
    context_id        = context_id,
    project_id        = project_id,
    file_id           = file_id,
    context_type      = context_type,
    label             = label,
    qualified_name    = paste0(basename(file_id), "::", label),
    line_start        = as.integer(line_start),
    line_end          = as.integer(line_end),
    parent_context_id = NA_character_,
    module_id         = NA_character_,
    snippet           = snippet,
    contains_isolate  = FALSE,   # updated in pass 4
    confidence        = "high",
    flags             = list(character())
  )
}

# ---- Pass 4: Reference extraction -------------------------------------

#' Extract intra-context references from parse data
#'
#' @param contexts sb_context tibble
#' @param parse_data Data frame from getParseData()
#' @param code Raw code string
#' @param file_id File ID
#' @param project_id Project ID
#' @return sb_reference tibble
extract_references <- function(contexts, parse_data, code, file_id, project_id) {
  if (nrow(contexts) == 0 || nrow(parse_data) == 0) return(new_sb_reference())

  result <- list()

  for (i in seq_len(nrow(contexts))) {
    ctx <- contexts[i, ]
    refs <- .extract_refs_for_context(ctx, parse_data, file_id, project_id)
    if (!is.null(refs) && nrow(refs) > 0) result[[length(result) + 1]] <- refs
  }

  # Update contexts with contains_isolate (side effect via environments in real
  # implementation; here we just return the refs)
  if (length(result) == 0) return(new_sb_reference())
  do.call(rbind, result)
}

# Extract references for one context
.extract_refs_for_context <- function(ctx, pd, file_id, project_id) {
  # Get tokens within this context's line range
  in_range <- pd[pd$line1 >= ctx$line_start & pd$line2 <= ctx$line_end, ]
  if (nrow(in_range) == 0) return(NULL)

  result <- list()

  # Check for isolate() blocks
  isolate_ranges <- .find_isolate_ranges(in_range)

  # --- input$ references ---
  # For input$year: the $ expr has children: [expr(SYMBOL("input")), '$', SYMBOL("year")]
  # The base name is nested one level deeper (inside expr), field name is direct SYMBOL
  dollar_rows <- in_range[in_range$token == "'$'", ]
  for (di in seq_len(nrow(dollar_rows))) {
    drow <- dollar_rows[di, ]
    # Get the parent expr of this $ token
    dollar_parent <- pd[pd$id == drow$parent, ]
    if (nrow(dollar_parent) == 0) next
    # Direct children of the dollar expr
    dollar_siblings <- pd[pd$parent == dollar_parent$id, ]

    # Field SYMBOL: direct SYMBOL child of the dollar expr
    field_syms <- dollar_siblings[dollar_siblings$token == "SYMBOL", ]
    # Base: inside an expr child of the dollar expr
    base_expr_child <- dollar_siblings[dollar_siblings$token == "expr", ]
    base_sym <- if (nrow(base_expr_child) > 0) {
      pd[pd$parent == base_expr_child$id[1] & pd$token == "SYMBOL", ]
    } else {
      data.frame(text = character(0))
    }

    if (nrow(field_syms) == 0 || nrow(base_sym) == 0) next

    base_name  <- base_sym$text[1]
    field_name <- field_syms$text[1]
    ref_text   <- paste0(base_name, "$", field_name)
    line_n     <- as.integer(drow$line1)

    ref_type <- switch(base_name,
      "input"  = "input_read",
      "output" = "output_write",
      NULL
    )

    # Non-input/output $ access: may be a reactiveValues read or write.
    # Emit as state_read / state_write candidates; the resolver filters out
    # any whose base name is not a known state symbol.
    if (is.null(ref_type)) {
      # Detect LHS-of-assignment: the $ expr's parent expr must contain a
      # LEFT_ASSIGN or EQ_ASSIGN token AND the $ expr must be the first expr
      # child of that assignment expr.
      is_write <- FALSE
      assign_parent <- pd[pd$id == dollar_parent$parent, ]
      if (nrow(assign_parent) > 0 && assign_parent$token == "expr") {
        assign_siblings <- pd[pd$parent == assign_parent$id, ]
        has_assign <- any(assign_siblings$token %in%
                          c("LEFT_ASSIGN", "EQ_ASSIGN", "RIGHT_ASSIGN"))
        if (has_assign) {
          expr_children <- assign_siblings[assign_siblings$token == "expr", ]
          if (nrow(expr_children) > 0 &&
              expr_children$id[1] == dollar_parent$id) {
            is_write <- TRUE
          }
        }
      }

      is_iso <- .is_in_isolate(line_n, isolate_ranges)
      ref <- .make_reference_row(
        project_id      = project_id,
        from_context_id = ctx$context_id,
        reference_type  = if (is_write) "state_write" else "state_read",
        target_text     = base_name,
        line_start      = line_n,
        line_end        = line_n,
        is_isolated     = is_iso,
        is_dynamic      = FALSE,
        confidence      = "medium"
      )
      result[[length(result) + 1]] <- ref
      next
    }

    is_iso <- .is_in_isolate(line_n, isolate_ranges)
    ref <- .make_reference_row(
      project_id      = project_id,
      from_context_id = ctx$context_id,
      reference_type  = ref_type,
      target_text     = ref_text,
      line_start      = line_n,
      line_end        = line_n,
      is_isolated     = is_iso,
      is_dynamic      = FALSE,
      confidence      = "high"
    )
    result[[length(result) + 1]] <- ref
  }

  # --- input[[ dynamic pattern ]] ---
  # In R 4.x getParseData, [[ is tokenized as "LBB" (not "'[['")
  lbb_rows <- in_range[in_range$token %in% c("LBB", "'[['"), ]
  for (li in seq_len(nrow(lbb_rows))) {
    lrow <- lbb_rows[li, ]
    # Check if the parent expr's first child is "input" symbol
    lbb_parent <- pd[pd$id == lrow$parent, ]
    if (nrow(lbb_parent) == 0) next
    # input is wrapped in an expr child: [expr(SYMBOL("input")), LBB, expr(...), ']']
    lbb_siblings  <- pd[pd$parent == lbb_parent$id, ]
    first_expr_sib <- lbb_siblings[lbb_siblings$token == "expr", ]
    if (nrow(first_expr_sib) == 0) next
    base_sym <- pd[pd$parent == first_expr_sib$id[1] &
                     pd$token %in% c("SYMBOL", "SYMBOL_FUNCTION_CALL"), ]
    if (nrow(base_sym) == 0 || base_sym$text[1] != "input") next
    line_n <- as.integer(lrow$line1)
    ref <- .make_reference_row(
      project_id        = project_id,
      from_context_id   = ctx$context_id,
      reference_type    = "input_read",
      target_text       = "input[[...]]",
      line_start        = line_n,
      line_end          = line_n,
      is_isolated       = FALSE,
      is_dynamic        = TRUE,
      confidence        = "low",
      unresolved_reason = "dynamic_input_id"
    )
    result[[length(result) + 1]] <- ref
  }

  # --- Function calls (SYMBOL_FUNCTION_CALL) ---
  call_toks <- in_range[in_range$token == "SYMBOL_FUNCTION_CALL", ]
  skip_calls <- c(
    "reactive", "reactiveVal", "reactiveValues", "observe",
    "observeEvent", "eventReactive", "renderPlot", "renderTable",
    "renderText", "renderUI", "renderImage", "renderPrint",
    "renderCachedPlot", "req", "isolate", "shinyApp", "fluidPage",
    "sidebarLayout", "sidebarPanel", "mainPanel", "titlePanel",
    "sliderInput", "selectInput", "numericInput", "textInput",
    "actionButton", "checkboxInput", "radioButtons", "dateInput",
    "plotOutput", "tableOutput", "textOutput", "uiOutput",
    "paste", "paste0", "c", "list", "data.frame", "mean",
    "nrow", "ncol", "is.null",
    "function", "if", "for", "while", "return"
  )

  # We emit one reference per (call name, arg count) pair so that a symbol
  # used once with zero args (read) and once with one arg (write) produces
  # two distinct references. Without this the resolver could only see one.
  seen_calls <- character()
  for (j in seq_len(nrow(call_toks))) {
    fn_name <- call_toks$text[j]
    if (fn_name %in% skip_calls) next
    line_n <- as.integer(call_toks$line1[j])
    arg_n  <- .count_call_args(call_toks$id[j], pd)
    key    <- paste0(fn_name, ":", ifelse(is.na(arg_n), "NA", arg_n))
    if (key %in% seen_calls) next
    seen_calls <- c(seen_calls, key)
    is_iso <- .is_in_isolate(line_n, isolate_ranges)

    # Classify as function_call; the resolver will retype state and reactive
    # calls once it knows which symbols exist in the project. Side-effect
    # flagging is done later via .get_ref_flags() on target_text.
    ref_type <- "function_call"

    ref <- .make_reference_row(
      project_id       = project_id,
      from_context_id  = ctx$context_id,
      reference_type   = ref_type,
      target_text      = fn_name,
      line_start       = line_n,
      line_end         = line_n,
      is_isolated      = is_iso,
      is_dynamic       = FALSE,
      confidence       = "medium",
      target_arg_count = arg_n
    )
    result[[length(result) + 1]] <- ref
  }

  # --- reactiveVal reads/writes (rv() and rv(val)) ---
  # These are detected in the resolver after state symbols are known.
  # The function_call references above capture them; resolver re-types them.

  # --- update*Input calls: reclassify from function_call ---
  for (i in seq_along(result)) {
    if (!is.null(result[[i]]) &&
        grepl("^update.*Input$|^update.*Select$|^update.*Choices$",
              result[[i]]$target_text)) {
      result[[i]]$reference_type <- "ui_update_call"
    }
  }

  if (length(result) == 0) return(NULL)
  do.call(rbind, result)
}

# ---- Isolate detection helpers ----------------------------------------

.find_isolate_ranges <- function(in_range) {
  iso_calls <- in_range[in_range$token == "SYMBOL_FUNCTION_CALL" &
                           in_range$text == "isolate", ]
  if (nrow(iso_calls) == 0) return(list())

  lapply(seq_len(nrow(iso_calls)), function(i) {
    row <- iso_calls[i, ]
    list(start = as.integer(row$line1), end = as.integer(row$line2))
  })
}

.is_in_isolate <- function(line_n, isolate_ranges) {
  if (length(isolate_ranges) == 0) return(FALSE)
  any(sapply(isolate_ranges, function(r) line_n >= r$start && line_n <= r$end))
}

# ---- Reference row builder --------------------------------------------

.make_reference_row <- function(project_id, from_context_id, reference_type,
                                 target_text, line_start, line_end,
                                 is_isolated = FALSE, is_dynamic = FALSE,
                                 confidence = "medium",
                                 unresolved_reason = NA_character_,
                                 target_arg_count = NA_integer_) {
  ref_id <- make_id(from_context_id, reference_type, target_text,
                     as.character(line_start), prefix = "ref")
  tibble::tibble(
    reference_id       = ref_id,
    project_id         = project_id,
    from_context_id    = from_context_id,
    reference_type     = reference_type,
    target_text        = target_text,
    resolved_symbol_id = NA_character_,
    line_start         = as.integer(line_start),
    line_end           = as.integer(line_end),
    is_isolated        = as.logical(is_isolated),
    is_dynamic         = as.logical(is_dynamic),
    confidence         = confidence,
    unresolved_reason  = as.character(unresolved_reason),
    target_arg_count   = as.integer(target_arg_count)
  )
}

# Count arguments of a call by inspecting its enclosing call expr.
# Returns NA_integer_ if the call expr cannot be found.
#
# Counts by top-level commas rather than expr children, because R's parser
# does not always wrap literal constants (NULL_CONST, NUM_CONST, STR_CONST,
# TRUE, FALSE, NA) in an enclosing expr token. For example, rv(NULL) can
# appear as: expr '(' NULL_CONST ')' -- with no expr wrapper around NULL.
# The original expr-only count returned 0 for such calls and caused them
# to be misclassified as state_read instead of state_write.
.count_call_args <- function(symbol_call_id, pd) {
  call_expr <- .walk_up_to_call_expr(symbol_call_id, pd)
  if (is.null(call_expr)) return(NA_integer_)
  siblings <- pd[pd$parent == call_expr$id, ]
  lparen <- which(siblings$token == "'('")
  rparen <- which(siblings$token == "')'")
  if (length(lparen) == 0 || length(rparen) == 0) return(NA_integer_)
  lo <- lparen[1] + 1L
  hi <- rparen[length(rparen)] - 1L
  if (lo > hi) return(0L)  # empty argument list e.g. rv()
  between <- siblings[lo:hi, , drop = FALSE]
  # Ignore pure whitespace/comment rows if getParseData ever returns them.
  between <- between[!between$token %in% c("COMMENT"), , drop = FALSE]
  if (nrow(between) == 0) return(0L)
  n_commas <- sum(between$token == "','")
  as.integer(n_commas + 1L)
}

# ---- Pass 5: Snippet extraction ----------------------------------------

#' Extract a code snippet for a context
#'
#' @param context_row One-row sb_context tibble
#' @param code Full source code string
#' @param max_lines Maximum lines to include in snippet
#' @return Character string snippet
#' @export
extract_snippet <- function(context_row, code, max_lines = 20) {
  .extract_lines(
    lines      = strsplit(code, "\n")[[1]],
    line_start = context_row$line_start,
    line_end   = context_row$line_end,
    max_lines  = max_lines
  )
}

.extract_lines <- function(lines, line_start, line_end, max_lines = 20) {
  if (is.na(line_start) || is.na(line_end)) return(NA_character_)
  start <- max(1L, as.integer(line_start))
  end   <- min(length(lines), as.integer(line_end))
  if (start > end) return(NA_character_)

  selected <- lines[start:end]
  if (length(selected) > max_lines) {
    selected <- c(selected[seq_len(max_lines)],
                  paste0("# ... (", length(selected) - max_lines, " more lines)"))
  }
  paste(selected, collapse = "\n")
}

# ---- Main parse_file orchestrator --------------------------------------

#' Parse a single file through all 5 passes
#'
#' @param file_row One-row sb_file tibble (from load_file)
#' @return Named list with keys: file, contexts, symbols_partial,
#'   references, issues
#' @export
parse_file <- function(file_row) {
  all_issues <- new_sb_issue()

  # Pass 1
  p1 <- parse_raw(file_row)
  all_issues <- rbind(all_issues, p1$issues)
  if (!isTRUE(p1$file$parse_success)) {
    return(list(
      file             = p1$file,
      contexts         = new_sb_context(),
      symbols_partial  = new_sb_symbol(),
      references       = new_sb_reference(),
      issues           = all_issues
    ))
  }

  pd   <- p1$parse_data
  code <- file_row$code

  # Pass 2 (scan_top_level) is available for future source() discovery but
  # is not needed on the single-file path; skip it here.

  # Pass 3
  contexts <- extract_contexts(
    parse_data = pd,
    code       = code,
    file_id    = file_row$file_id,
    project_id = file_row$project_id
  )

  # Pass 4
  references <- new_sb_reference()
  if (nrow(contexts) > 0) {
    references <- extract_references(
      contexts   = contexts,
      parse_data = pd,
      code       = code,
      file_id    = file_row$file_id,
      project_id = file_row$project_id
    )
  }

  # Update contains_isolate on contexts
  if (nrow(references) > 0 && nrow(contexts) > 0) {
    iso_ctx <- unique(
      references$from_context_id[references$is_isolated]
    )
    contexts$contains_isolate[contexts$context_id %in% iso_ctx] <- TRUE
  }

  # Check for side-effect issues
  if (nrow(references) > 0) {
    se_refs <- references[sapply(seq_len(nrow(references)), function(i) {
      "possible_side_effect" %in% .get_ref_flags(references[i, ])
    }), ]
    if (nrow(se_refs) > 0) {
      for (j in seq_len(nrow(se_refs))) {
        issue <- make_issue(
          project_id = file_row$project_id,
          severity   = "info",
          issue_type = "possible_side_effect",
          message    = paste0(
            "Possible side-effect call to '", se_refs$target_text[j],
            "()' at line ", se_refs$line_start[j], ". ",
            "This function typically writes outside the reactive graph ",
            "(e.g. disk I/O, console output, network). shinybrain flags it ",
            "because its effect will not be represented as an edge, so a ",
            "downstream context that depends on the effect may look ",
            "unconnected in the graph. Safe to ignore if the call is purely ",
            "diagnostic or the effect is intentional."
          ),
          file_id    = file_row$file_id,
          line_start = se_refs$line_start[j],
          line_end   = se_refs$line_end[j]
        )
        all_issues <- rbind(all_issues, issue)
      }
    }
  }

  list(
    file            = p1$file,
    parse_data      = pd,
    contexts        = contexts,
    symbols_partial = new_sb_symbol(),  # built in symbol layer
    references      = references,
    issues          = all_issues
  )
}

# Flag accessor (references don't currently store flags as list col,
# so we match against known patterns on target_text)
.get_ref_flags <- function(ref_row) {
  flags <- character()
  if (is_side_effect_call(ref_row$target_text)) {
    flags <- c(flags, "possible_side_effect")
  }
  flags
}
