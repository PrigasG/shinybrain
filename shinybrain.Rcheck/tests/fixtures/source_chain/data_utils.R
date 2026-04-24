# Core data prep - used in 1 reactive context
prepare_data <- function(df, metric) {
  df <- df[!is.na(df[[metric]]), ]
  df[order(df[[metric]]), ]
}
