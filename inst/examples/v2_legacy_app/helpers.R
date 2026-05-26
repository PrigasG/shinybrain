filter_fleet <- function(df, min_mpg) {
  df[df$mpg >= min_mpg, , drop = FALSE]
}

summarize_fleet <- function(df) {
  data.frame(
    rows = nrow(df),
    avg_mpg = mean(df$mpg),
    avg_hp = mean(df$hp)
  )
}
