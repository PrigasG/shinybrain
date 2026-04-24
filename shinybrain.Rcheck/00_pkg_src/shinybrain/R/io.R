#' @title IO Layer
#' @description File loading and project entry point detection
#' @name io
NULL

#' Load a single R source file into an sb_file row
#'
#' Does not parse the code. Only reads the file and validates it exists.
#' On failure, returns a row with parse_success = FALSE and an issue row.
#'
#' @param path Absolute or relative path to the file
#' @param project_id Project ID string
#' @param role One of "entry", "sourced", "module"
#' @param source_line Line in the calling file where source() was found,
#'   or NA_integer_ for entry files
#' @return Named list: list(file = one-row sb_file tibble, issues = sb_issue tibble)
#' @export
load_file <- function(path, project_id, role = "entry",
                      source_line = NA_integer_) {
  path <- normalizePath(path, mustWork = FALSE)
  file_id <- make_id(project_id, path, prefix = "file")

  # File not found
  if (!file.exists(path)) {
    file_row <- tibble::tibble(
      file_id       = file_id,
      project_id    = project_id,
      path          = path,
      relative_path = NA_character_,
      role          = role,
      source_line   = as.integer(source_line),
      code          = NA_character_,
      line_count    = NA_integer_,
      parse_success = FALSE,
      parse_error   = "File not found"
    )
    # When the caller already marked this as a ghost via role = "missing",
    # resolve_source_chain has emitted the user-facing issue; skip a second
    # duplicate issue here.
    if (identical(role, "missing")) {
      return(list(file = file_row, issues = new_sb_issue()))
    }
    issue <- make_issue(
      project_id = project_id,
      severity   = "error",
      issue_type = "missing_file",
      message    = paste0(
        "File not found: ", path, ". ",
        "Expected an .R file at that path. Verify the path is spelled ",
        "correctly and that any relative paths are relative to getwd() ",
        "at the time analyze_shiny_project() was called."
      ),
      file_id    = file_id
    )
    return(list(file = file_row, issues = issue))
  }

  # Read file. Capture the underlying error so it appears in the message.
  read_err <- NULL
  code <- tryCatch(
    paste(readLines(path, warn = FALSE), collapse = "\n"),
    error = function(e) {
      read_err <<- conditionMessage(e)
      NULL
    }
  )

  if (is.null(code)) {
    err_detail <- if (is.null(read_err) || !nzchar(read_err))
      "unknown read error" else read_err
    file_row <- tibble::tibble(
      file_id       = file_id,
      project_id    = project_id,
      path          = path,
      relative_path = NA_character_,
      role          = role,
      source_line   = as.integer(source_line),
      code          = NA_character_,
      line_count    = NA_integer_,
      parse_success = FALSE,
      parse_error   = paste0("readLines() failed: ", err_detail)
    )
    issue <- make_issue(
      project_id = project_id,
      severity   = "error",
      issue_type = "missing_file",
      message    = paste0(
        "Could not read file: ", path,
        ". Underlying error: ", err_detail,
        ". Common causes: the file is locked by another process, the user ",
        "lacks read permission, or the encoding is not UTF-8 / native."
      ),
      file_id    = file_id
    )
    return(list(file = file_row, issues = issue))
  }

  line_count <- length(strsplit(code, "\n")[[1]])

  # Empty file
  issues <- new_sb_issue()
  if (nchar(trimws(code)) == 0) {
    issues <- make_issue(
      project_id = project_id,
      severity   = "info",
      issue_type = "empty_file",
      message    = paste0(
        "File is empty: ", basename(path),
        ". No contexts, symbols, or edges were extracted from it. ",
        "This is a notice, not an error - shinybrain still completed successfully."
      ),
      file_id    = file_id
    )
  }

  file_row <- tibble::tibble(
    file_id       = file_id,
    project_id    = project_id,
    path          = path,
    relative_path = NA_character_,  # set by caller when project root is known
    role          = role,
    source_line   = as.integer(source_line),
    code          = code,
    line_count    = as.integer(line_count),
    parse_success = TRUE,
    parse_error   = NA_character_
  )

  list(file = file_row, issues = issues)
}

#' Detect the entry point of a Shiny project directory
#'
#' @param path Path to project directory
#' @return Named list: list(type, files) where type is one of
#'   "app_r", "ui_server_pair", or throws with guidance
#' @export
detect_entry_point <- function(path) {
  path <- normalizePath(path, mustWork = FALSE)

  if (!dir.exists(path)) {
    rlang::abort(paste0(
      "Directory not found: ", path, ". ",
      "detect_entry_point() expects a path to an existing directory. ",
      "If you meant to analyze a single file, call analyze_shiny_file() instead."
    ))
  }

  app_r    <- file.path(path, "app.R")
  ui_r     <- file.path(path, "ui.R")
  server_r <- file.path(path, "server.R")

  if (file.exists(app_r)) {
    return(list(type = "app_r", files = app_r))
  }

  if (file.exists(ui_r) && file.exists(server_r)) {
    return(list(type = "ui_server_pair", files = c(ui_r, server_r)))
  }

  # Report what WAS present so the user can see the mismatch at a glance.
  present_r <- list.files(path, pattern = "\\.[Rr]$", full.names = FALSE)
  found_line <- if (length(present_r) == 0) {
    "This directory contains no .R files at all."
  } else {
    paste0("Files found: ", paste(present_r, collapse = ", "), ".")
  }

  # Point out the common near-miss of having only one of the pair.
  near_miss <- character()
  if (file.exists(ui_r) && !file.exists(server_r)) {
    near_miss <- "Found ui.R but not server.R - the pair is required."
  } else if (file.exists(server_r) && !file.exists(ui_r)) {
    near_miss <- "Found server.R but not ui.R - the pair is required."
  }

  rlang::abort(paste(c(
    paste0("Could not detect a Shiny entry point in: ", path),
    "Expected either app.R, or both ui.R and server.R, at the top level.",
    found_line,
    near_miss,
    "If your entry file lives in a subdirectory, point shinybrain at that subdirectory instead.",
    "To analyze a non-standard single file, use analyze_shiny_file(path_to_file)."
  ), collapse = "\n"))
}
