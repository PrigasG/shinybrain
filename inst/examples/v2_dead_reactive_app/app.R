library(shiny)

ui <- fluidPage(
  titlePanel("V2 dead reactive example"),
  sliderInput("threshold", "Minimum mpg", min = 10, max = 35, value = 20),
  tableOutput("cars_table"),
  textOutput("row_count")
)

server <- function(input, output, session) {
  filtered <- reactive({
    mtcars[mtcars$mpg >= input$threshold, ]
  })

  unused_summary <- reactive({
    df <- filtered()
    data.frame(
      avg_mpg = mean(df$mpg),
      avg_hp = mean(df$hp)
    )
  })

  output$cars_table <- renderTable({
    filtered()[, c("mpg", "hp", "wt")]
  })

  output$row_count <- renderText({
    paste("Rows:", nrow(filtered()))
  })
}

shinyApp(ui, server)
