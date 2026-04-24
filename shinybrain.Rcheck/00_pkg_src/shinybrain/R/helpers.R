#' @title Internal utility functions
#' @name utils
NULL

# ---- Deterministic ID generation ---------------------------------------

#' Generate a short deterministic ID from one or more strings
#'
#' Uses a digest-style hash (base conversion of sum of char codes + length),
#' keeping it short and readable. Deterministic for same inputs.
#'
#' NA and NULL inputs are coerced to the literal string "NA" so that two
#' callers with the same NA pattern produce the same ID; callers that pass
#' genuinely distinct values should ensure their inputs are not NA.
#'
#' @param ... Values to combine. Non-character inputs are coerced via
#'   as.character(); NULL entries are dropped; NA becomes "NA".
#' @param prefix Optional prefix string e.g. "ctx", "sym"
#' @return Single character ID string of the form "<prefix>_<6-hex-digits>".
make_id <- function(..., prefix = "") {
  raw <- list(...)
  # Drop NULL entries; coerce everything else to character scalars
  raw <- Filter(Negate(is.null), raw)
  chr <- vapply(raw, function(x) {
    if (length(x) == 0L) return("")
    x <- as.character(x)
    x[is.na(x)] <- "NA"
    if (length(x) > 1L) paste(x, collapse = ",") else x
  }, character(1))

  parts <- paste(chr, collapse = "|")
  if (!nzchar(parts)) parts <- "_empty_"

  bytes <- utf8ToInt(parts)
  h <- 0L
  for (i in seq_along(bytes)) {
    h <- bitwXor(bitwShiftL(h, 5L), bytes[i]) + i * 31L
    h <- h %% 2147483647L  # keep positive
  }
  hex <- format(as.hexmode(abs(h)), width = 6, flag = "0")

  prefix <- if (length(prefix) == 0L || is.na(prefix[1])) "" else as.character(prefix[1])
  if (nchar(prefix) > 0) paste0(prefix, "_", hex) else hex
}

# ---- Issue row builder -------------------------------------------------

#' Build a single sb_issue row as a one-row tibble
#'
#' @param project_id Project ID string
#' @param severity One of "info", "warning", "error"
#' @param issue_type One of ISSUE_TYPES
#' @param message Human-readable message
#' @param file_id Optional file ID
#' @param context_id Optional context ID
#' @param line_start Optional line number
#' @param line_end Optional line number
#' @return One-row sb_issue tibble
make_issue <- function(
  project_id,
  severity,
  issue_type,
  message,
  file_id    = NA_character_,
  context_id = NA_character_,
  line_start = NA_integer_,
  line_end   = NA_integer_
) {
  issue_id <- make_id(project_id, severity, issue_type, message,
                      file_id %||% "", prefix = "issue")
  tibble::tibble(
    issue_id   = issue_id,
    project_id = project_id,
    file_id    = as.character(file_id),
    context_id = as.character(context_id),
    severity   = severity,
    issue_type = issue_type,
    message    = message,
    line_start = as.integer(line_start),
    line_end   = as.integer(line_end)
  )
}

# ---- Null coalesce -----------------------------------------------------

#' Null coalescing operator
#'
#' @name null_coalesce
#' @aliases %||%
#' @param x Primary value to return when it is not NULL and not length 0.
#' @param y Fallback value returned when `x` is NULL or empty.
#' @return `x` when present, otherwise `y`.
`%||%` <- function(x, y) if (is.null(x) || length(x) == 0) y else x

# ---- Safe list column --------------------------------------------------

#' Wrap a character vector into a list column value
#'
#' @param x Character vector or NULL
#' @return List of length 1 containing x (suitable for list columns)
as_flag_list <- function(x = character()) {
  list(if (is.null(x)) character() else x)
}

# ---- Safe NA defaults --------------------------------------------------

na_chr <- function() NA_character_
na_int <- function() NA_integer_
na_lgl <- function() NA
