legacySummaryUI <- function(id) {
  ns <- NS(id)
  tagList(
    textOutput(ns("status")),
    tableOutput(ns("summary_table"))
  )
}

legacySummaryServer <- function(id) {
  moduleServer(id, function(input, output, session) {
    base_data <- reactive({
      mtcars
    })

    ranked_data <- reactive({
      base_data()[order(base_data()$mpg, decreasing = TRUE), ]
    })

    unused_ranked <- reactive({
      head(ranked_data(), 2)
    })

    output$status <- renderText({
      paste("Rows in ranking:", nrow(ranked_data()))
    })

    output$summary_table <- renderTable({
      summarize_fleet(ranked_data())
    })
  })
}

orphanServer <- function(id) {
  moduleServer(id, function(input, output, session) {
    orphan_note <- reactive({
      paste("orphan", id)
    })
  })
}
