library(shiny)

ui <- fluidPage(
  numericInput("threshold", "Threshold", value = 5),
  actionButton("reset_btn", "Reset"),
  actionButton("save_btn", "Save"),
  textOutput("status"),
  tableOutput("filtered_table")
)

server <- function(input, output, session) {

  # State node - should NOT be classified as input
  rv <- reactiveVal(NULL)

  filtered <- reactive({
    req(input$threshold)
    mtcars[mtcars$cyl >= input$threshold, ]
  })

  # observeEvent - triggered by button
  observeEvent(input$reset_btn, {
    rv(NULL)
    updateNumericInput(session, "threshold", value = 5)
  })

  # observeEvent - save action with side effect
  observeEvent(input$save_btn, {
    data <- filtered()
    rv(data)
    write.csv(data, "output.csv")
  })

  output$status <- renderText({
    if (is.null(rv())) "No data saved." else paste("Saved", nrow(rv()), "rows.")
  })

  output$filtered_table <- renderTable({
    filtered()
  })

}

shinyApp(ui, server)
