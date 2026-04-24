library(shiny)

source("helpers.R")
source("data_utils.R")

ui <- fluidPage(
  selectInput("metric", "Metric", choices = c("mpg", "hp", "wt")),
  plotOutput("metric_plot"),
  tableOutput("metric_table")
)

server <- function(input, output, session) {

  processed <- reactive({
    prepare_data(mtcars, input$metric)
  })

  output$metric_plot <- renderPlot({
    plot_metric(processed(), input$metric)
  })

  output$metric_table <- renderTable({
    format_table(processed())
  })

}

shinyApp(ui, server)
