library(shiny)

# Simple helper function
clean_data <- function(df) {
  df[complete.cases(df), ]
}

ui <- fluidPage(
  titlePanel("Basic App"),
  sidebarLayout(
    sidebarPanel(
      sliderInput("year", "Year", min = 2000, max = 2023, value = 2010),
      selectInput("region", "Region",
                  choices = c("North", "South", "East", "West"))
    ),
    mainPanel(
      plotOutput("trend_plot"),
      tableOutput("summary_table"),
      textOutput("record_count")
    )
  )
)

server <- function(input, output, session) {

  filtered_data <- reactive({
    df <- mtcars
    df <- clean_data(df)
    df[df$cyl >= input$year %% 4 + 4, ]
  })

  summary_stats <- reactive({
    data.frame(
      region = input$region,
      mean_mpg = mean(filtered_data()$mpg)
    )
  })

  output$trend_plot <- renderPlot({
    plot(filtered_data()$mpg, main = input$region)
  })

  output$summary_table <- renderTable({
    summary_stats()
  })

  output$record_count <- renderText({
    paste("Records:", nrow(filtered_data()))
  })

}

shinyApp(ui, server)
