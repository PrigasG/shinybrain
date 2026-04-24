#' @title Resolve Layer
#' @description Build symbols from contexts and link references to symbols.
#' @name resolve_layer
NULL

# ---- Symbol construction -----------------------------------------------

#' Build sb_symbol tibble from parsed contexts and references
#'
#' Creates:
#' - One symbol per context that defines a graphable entity
#' - Synthetic input_ref symbols for each distinct input$x encountered
#' - Synthetic state symbols for reactiveVal/reactiveValues
#'
#' @param contexts sb_context tibble
#' @param references sb_reference tibble
#' @param file_id File ID
#' @param project_id Project ID
#' @return sb_symbol tibble
#' @export
build_symbols <- function(contexts, references, file_id, project_id) {
  result <- list()

  # --- Symbols from contexts ---
  context_to_symbol_type <- c(
    "reactive"       = "reactive",
    "output_render"  = "output",
    "observer"       = "observer",
    "observe_event"  = "observe_event",
    "event_reactive" = "event_reactive",
    "helper_fn"      = "helper_fn",
    "state_val"      = "state_val",
    "state_values"   = "state_values"
  )

  for (i in seq_len(nrow(contexts))) {
    ctx      <- contexts[i, ]
    sym_type <- context_to_symbol_type[ctx$context_type]
    if (is.na(sym_type)) next

    sym_id <- make_id(file_id, sym_type, ctx$label,
                      as.character(ctx$line_start), prefix = "sym")
    sym <- tibble::tibble(
      symbol_id      = sym_id,
      project_id     = project_id,
      file_id        = file_id,
      context_id     = ctx$context_id,
      name           = ctx$label,
      qualified_name = ctx$qualified_name,
      symbol_type    = sym_type,
      line_start     = ctx$line_start,
      line_end       = ctx$line_end,
      module_id      = NA_character_,
      usage_count    = 0L,
      confidence     = ctx$confidence
    )
    result[[length(result) + 1]] <- sym
  }

  # --- Synthetic input_ref symbols ---
  if (nrow(references) > 0) {
    input_refs <- references[references$reference_type == "input_read" &
                               !references$is_dynamic, ]
    distinct_inputs <- unique(input_refs$target_text)

    for (inp in distinct_inputs) {
      sym_id <- make_id(project_id, "input_ref", inp, prefix = "sym")
      sym <- tibble::tibble(
        symbol_id      = sym_id,
        project_id     = project_id,
        file_id        = NA_character_,
        context_id     = NA_character_,
        name           = inp,
        qualified_name = inp,
        symbol_type    = "input_ref",
        line_start     = NA_integer_,
        line_end       = NA_integer_,
        module_id      = NA_character_,
        usage_count    = 0L,
        confidence     = "high"
      )
      result[[length(result) + 1]] <- sym
    }
  }

  if (length(result) == 0) return(new_sb_symbol())
  do.call(rbind, result)
}

# ---- Reference resolution ----------------------------------------------

#' Resolve references to symbol IDs where possible
#'
#' Links function_call and reactive_read references to known project symbols.
#' Re-types state_val reads/writes by checking if the target is a state symbol.
#' Sets unresolved_reason for cases where resolution was expected but failed.
#'
#' @param references sb_reference tibble
#' @param symbols sb_symbol tibble
#' @param project_id Project ID
#' @return Updated sb_reference tibble
#' @export
resolve_references <- function(references, symbols, project_id) {
  if (nrow(references) == 0) return(references)
  if (nrow(symbols) == 0)    return(references)

  # Build lookup: name -> symbol_id (prefer non-input_ref for function calls)
  sym_lookup <- stats::setNames(symbols$symbol_id, symbols$name)
  state_names <- symbols$name[symbols$symbol_type %in% c("state_val", "state_values")]
  reactive_names <- symbols$name[
    symbols$symbol_type %in% c("reactive", "event_reactive")
  ]

  for (i in seq_len(nrow(references))) {
    ref  <- references[i, ]
    text <- ref$target_text

    # Input reads: resolve to synthetic input_ref symbol
    if (ref$reference_type == "input_read" && !ref$is_dynamic) {
      sym_id <- sym_lookup[text]
      if (!is.na(sym_id)) {
        references$resolved_symbol_id[i] <- sym_id
        references$confidence[i]         <- "high"
      }
      next
    }

    # Dollar-access state reads/writes emitted by the parser. Verify the
    # base name is a known state symbol; otherwise leave unresolved so the
    # edge builder skips it.
    if (ref$reference_type %in% c("state_read", "state_write")) {
      if (text %in% state_names) {
        references$resolved_symbol_id[i] <- sym_lookup[text]
        references$confidence[i]         <- "high"
      }
      next
    }

    # Function calls: check if target matches a known project symbol
    if (ref$reference_type == "function_call") {
      # Strip trailing () if present
      bare_name <- sub("\\(\\)$", "", text)

      if (bare_name %in% state_names) {
        # Reclassify state calls using the argument count captured at parse
        # time: rv()      -> state_read
        #       rv(value) -> state_write
        # If arg count is unknown (NA) we fall back to state_read and flag
        # the confidence as medium so downstream tooling knows.
        arg_n <- ref$target_arg_count
        if (is.na(arg_n)) {
          references$reference_type[i]    <- "state_read"
          references$confidence[i]        <- "medium"
          references$unresolved_reason[i] <- "ambiguous_symbol"
        } else if (arg_n == 0L) {
          references$reference_type[i] <- "state_read"
          references$confidence[i]     <- "high"
        } else {
          references$reference_type[i] <- "state_write"
          references$confidence[i]     <- "high"
        }
        references$resolved_symbol_id[i] <- sym_lookup[bare_name]
        next
      }

      if (bare_name %in% reactive_names) {
        references$reference_type[i]     <- "reactive_read"
        references$resolved_symbol_id[i] <- sym_lookup[bare_name]
        references$confidence[i]         <- "high"
        next
      }

      sym_id <- sym_lookup[bare_name]
      if (!is.na(sym_id)) {
        references$resolved_symbol_id[i] <- sym_id
        references$confidence[i]         <- "high"
      }
      # Unknown callees (e.g. external library functions) are left as
      # function_call with NA resolved_symbol_id; the insights layer treats
      # them as side-effect candidates when they match SIDE_EFFECT_PATTERNS.
      next
    }
  }

  references
}

#' Look up a symbol by name in the symbols table
#'
#' @param name Symbol name string
#' @param symbols sb_symbol tibble
#' @param from_context_id Context ID for disambiguation (unused in Sprint 1)
#' @return List: list(symbol_id, unresolved_reason)
lookup_symbol <- function(name, symbols, from_context_id = NA_character_) {
  matches <- symbols[symbols$name == name, ]
  if (nrow(matches) == 0) {
    return(list(symbol_id = NA_character_, unresolved_reason = "unknown_callee"))
  }
  if (nrow(matches) > 1) {
    return(list(symbol_id = matches$symbol_id[1],
                unresolved_reason = "ambiguous_symbol"))
  }
  list(symbol_id = matches$symbol_id[1], unresolved_reason = NA_character_)
}
