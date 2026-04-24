# Intentionally broken app used as a fixture for shinybrain's error paths.
# DO NOT RUN this with shiny::runApp. It exists only to feed the static
# analyzer missing and dynamic source() calls plus an input read inside a
# dynamic key lookup.

library(shiny)

source("helpers.R")              # resolves: ships next to this file
source("does_not_exist.R")       # triggers a missing_file issue
source(paste0("dyna", "mic.R"))  # triggers an unsupported_pattern issue

ui <- fluidPage(
  textInput("name",  "Name"),
  textInput("email", "Email"),
  textOutput("out")
)

server <- function(input, output, session) {

  # Dynamic key: cannot be resolved statically; should flag as is_dynamic.
  output$out <- renderText({
    key <- sample(c("name", "email"), 1)
    input[[key]]
  })
}

shinyApp(ui, server)
