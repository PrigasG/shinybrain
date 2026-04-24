#' @title Internal Representation Constructors
#' @description
#' These functions create empty, typed tibbles for each IR object.
#' They are the contract that all pipeline layers read and write.
#' Call validate_ir() to verify conformance.
#'
#' @name ir_constructors
NULL

# ---- Taxonomy constants ------------------------------------------------

#' Valid context types
#' Note: "module_def" and "module_instance" are reserved for future module
#' support but are not produced by the current parser. "ui_block" and
#' "global_block" were removed in 0.1.0; the parser classifies top-level
#' UI and global.R content as "unknown" or "helper_fn" instead.
CONTEXT_TYPES <- c(
  "reactive", "output_render", "observer", "observe_event",
  "event_reactive", "helper_fn",
  "state_val", "state_values", "unknown"
)

#' Valid symbol types
#' Note: "module_def" and "module_instance" are reserved for future module
#' support but are not produced by the current resolver.
SYMBOL_TYPES <- c(
  "input_ref", "output", "reactive", "event_reactive",
  "observer", "observe_event", "helper_fn", "state_val",
  "state_values", "unresolved"
)

#' Valid reference types
REFERENCE_TYPES <- c(
  "input_read", "reactive_read", "output_write", "state_read",
  "state_write", "function_call", "event_trigger", "namespace_use",
  "source_call", "module_instantiation", "ui_update_call"
)

#' Valid edge types
EDGE_TYPES <- c(
  "depends_on", "feeds_into", "triggers", "calls",
  "reads_state", "writes_state", "contains", "cross_module",
  "defines", "unresolved_link"
)

#' Valid confidence levels
CONFIDENCE_LEVELS <- c("high", "medium", "low")

#' Valid severity levels
SEVERITY_LEVELS <- c("info", "warning", "error")

#' Valid issue types
ISSUE_TYPES <- c(
  "missing_file", "parse_failure", "possible_side_effect",
  "unsupported_pattern", "source_cycle", "module_link_incomplete",
  "graph_validation_failure", "empty_file", "entry_point_not_found"
)

#' Valid unresolved reason types
UNRESOLVED_TYPES <- c(
  "dynamic_input_id", "dynamic_output_id", "dynamic_source_path",
  "runtime_generated_ui", "conditional_definition", "ambiguous_symbol",
  "unknown_callee", "nonstandard_evaluation", "unsupported_pattern",
  "module_link_incomplete", "source_cycle"
)

# ---- Constructors -------------------------------------------------------

#' Create an empty sb_project tibble
#' @return tibble with 0 rows and correct column types
#' @export
new_sb_project <- function() {
  tibble::tibble(
    project_id         = character(),
    root_path          = character(),
    entry_point_type   = character(),
    entry_files        = list(),
    parse_order        = list(),
    shinybrain_version = character(),
    created_at         = character()
  )
}

#' Create an empty sb_file tibble
#' @return tibble with 0 rows and correct column types
#' @export
new_sb_file <- function() {
  tibble::tibble(
    file_id       = character(),
    project_id    = character(),
    path          = character(),
    relative_path = character(),
    role          = character(),
    source_line   = integer(),
    code          = character(),
    line_count    = integer(),
    parse_success = logical(),
    parse_error   = character()
  )
}

#' Create an empty sb_context tibble
#' @return tibble with 0 rows and correct column types
#' @export
new_sb_context <- function() {
  tibble::tibble(
    context_id        = character(),
    project_id        = character(),
    file_id           = character(),
    context_type      = character(),
    label             = character(),
    qualified_name    = character(),
    line_start        = integer(),
    line_end          = integer(),
    parent_context_id = character(),
    module_id         = character(),
    snippet           = character(),
    contains_isolate  = logical(),
    confidence        = character(),
    flags             = list()
  )
}

#' Create an empty sb_symbol tibble
#' @return tibble with 0 rows and correct column types
#' @export
new_sb_symbol <- function() {
  tibble::tibble(
    symbol_id      = character(),
    project_id     = character(),
    file_id        = character(),
    context_id     = character(),
    name           = character(),
    qualified_name = character(),
    symbol_type    = character(),
    line_start     = integer(),
    line_end       = integer(),
    module_id      = character(),
    usage_count    = integer(),
    confidence     = character()
  )
}

#' Create an empty sb_reference tibble
#'
#' `target_arg_count` is an implementation-detail column populated during
#' reference extraction. It is used by the resolver to distinguish state
#' reads (`rv()`, 0 args) from state writes (`rv(val)`, 1+ args). NA means
#' argument count is unknown or not applicable.
#'
#' @return tibble with 0 rows and correct column types
#' @export
new_sb_reference <- function() {
  tibble::tibble(
    reference_id       = character(),
    project_id         = character(),
    from_context_id    = character(),
    reference_type     = character(),
    target_text        = character(),
    resolved_symbol_id = character(),
    line_start         = integer(),
    line_end           = integer(),
    is_isolated        = logical(),
    is_dynamic         = logical(),
    confidence         = character(),
    unresolved_reason  = character(),
    target_arg_count   = integer()
  )
}

#' Create an empty sb_node_candidate tibble
#' @return tibble with 0 rows and correct column types
#' @export
new_sb_node_candidate <- function() {
  tibble::tibble(
    node_id          = character(),
    project_id       = character(),
    context_id       = character(),
    node_type        = character(),
    label            = character(),
    qualified_name   = character(),
    file_id          = character(),
    line_start       = integer(),
    module_id        = character(),
    confidence       = character(),
    contains_isolate = logical(),
    usage_count      = integer(),
    flags            = list(),
    snippet          = character()
  )
}

#' Create an empty sb_edge_candidate tibble
#' @return tibble with 0 rows and correct column types
#' @export
new_sb_edge_candidate <- function() {
  tibble::tibble(
    edge_id      = character(),
    project_id   = character(),
    from_node_id = character(),
    to_node_id   = character(),
    edge_type    = character(),
    reference_id = character(),
    is_isolated  = logical(),
    confidence   = character(),
    file_id      = character(),
    line_start   = integer(),
    flags        = list()
  )
}

#' Create an empty sb_issue tibble
#' @return tibble with 0 rows and correct column types
#' @export
new_sb_issue <- function() {
  tibble::tibble(
    issue_id   = character(),
    project_id = character(),
    file_id    = character(),
    context_id = character(),
    severity   = character(),
    issue_type = character(),
    message    = character(),
    line_start = integer(),
    line_end   = integer()
  )
}

# ---- Validation -------------------------------------------------------

#' Validate an IR object against its expected schema
#'
#' @param x The tibble to validate
#' @param schema_name One of: "project", "file", "context", "symbol",
#'   "reference", "node_candidate", "edge_candidate", "issue"
#' @return Invisibly returns x; throws error on schema mismatch
#' @export
validate_ir <- function(x, schema_name) {
  expected <- switch(schema_name,
    project        = new_sb_project(),
    file           = new_sb_file(),
    context        = new_sb_context(),
    symbol         = new_sb_symbol(),
    reference      = new_sb_reference(),
    node_candidate = new_sb_node_candidate(),
    edge_candidate = new_sb_edge_candidate(),
    issue          = new_sb_issue(),
    rlang::abort(paste0(
      "validate_ir(): unknown schema_name '", schema_name, "'. ",
      "Valid schema names are: project, file, context, symbol, reference, ",
      "node_candidate, edge_candidate, issue."
    ))
  )

  expected_cols <- names(expected)
  actual_cols   <- names(x)
  missing_cols  <- setdiff(expected_cols, actual_cols)
  extra_cols    <- setdiff(actual_cols, expected_cols)

  if (length(missing_cols) > 0) {
    rlang::abort(paste0(
      "validate_ir('", schema_name, "'): the sb_", schema_name,
      " tibble is missing required column(s): ",
      paste(missing_cols, collapse = ", "),
      ". Expected columns: ", paste(expected_cols, collapse = ", "),
      ". Got columns: ",
      if (length(actual_cols) == 0) "<none>" else paste(actual_cols, collapse = ", "),
      ". If you built this tibble by hand, start from new_sb_", schema_name,
      "() to get the correct shape."
    ))
  }

  # Check types for each expected column
  for (col in expected_cols) {
    expected_type <- class(expected[[col]])
    actual_type   <- class(x[[col]])
    if (!identical(expected_type, actual_type)) {
      rlang::abort(paste0(
        "validate_ir('", schema_name, "'): column '", col,
        "' has the wrong type. Expected: ",
        paste(expected_type, collapse = "/"),
        ". Got: ", paste(actual_type, collapse = "/"),
        ". Cast the column to the expected type before validating, or ",
        "rebuild the tibble starting from new_sb_", schema_name, "()."
      ))
    }
  }

  invisible(x)
}
