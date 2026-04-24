# Pure helper functions used by app.R.
# These become helper_fn nodes in the shinybrain graph and are linked by
# function_call edges from the reactives that invoke them.

#' Keep numeric columns whose mean is at least `cutoff`
filter_by_threshold <- function(df, cutoff) {
  num_cols <- vapply(df, is.numeric, logical(1))
  if (!any(num_cols)) return(df[, FALSE, drop = FALSE])
  means <- vapply(df[, num_cols, drop = FALSE],
                  function(x) mean(x, na.rm = TRUE),
                  numeric(1))
  keep_numeric <- names(means)[means >= cutoff]
  df[, keep_numeric, drop = FALSE]
}

#' Return a one-row-per-column summary table for numeric columns
summarize_numeric <- function(df) {
  num_cols <- vapply(df, is.numeric, logical(1))
  num <- df[, num_cols, drop = FALSE]
  if (ncol(num) == 0) {
    return(data.frame(column = character(), mean = numeric(),
                      sd = numeric(), min = numeric(), max = numeric()))
  }
  data.frame(
    column    = names(num),
    mean      = vapply(num, mean, numeric(1), na.rm = TRUE),
    sd        = vapply(num, stats::sd, numeric(1), na.rm = TRUE),
    min       = vapply(num, min,  numeric(1), na.rm = TRUE),
    max       = vapply(num, max,  numeric(1), na.rm = TRUE),
    row.names = NULL
  )
}
