library(shiny)

ui <- fluidPage(
  titlePanel("V2 side effect example"),
  numericInput("n_rows", "Rows to snapshot", value = 5, min = 1, max = 10),
  actionButton("refresh", "Refresh preview"),
  tableOutput("preview"),
  textOutput("status")
)

server <- function(input, output, session) {
  snapshot <- reactive({
    input$refresh
    rows <- head(mtcars, input$n_rows)
    message("Refreshing snapshot for ", input$n_rows, " rows")
    write.csv(rows, tempfile(fileext = ".csv"), row.names = FALSE)
    rows
  })

  output$preview <- renderTable({
    snapshot()
  })

  output$status <- renderText({
    paste("Snapshot rows:", nrow(snapshot()))
  })
}

shinyApp(ui, server)
