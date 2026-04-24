# Plot utility
plot_metric <- function(df, metric) {
  barplot(df[[metric]], main = paste("Distribution of", metric))
}

# Table utility
format_table <- function(df) {
  head(df, 10)
}
