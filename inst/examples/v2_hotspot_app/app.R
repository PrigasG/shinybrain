library(shiny)

metric_card <- function(label, value) {
  div(
    strong(label),
    span(": "),
    span(value)
  )
}

ui <- fluidPage(
  titlePanel("V2 hotspot example"),
  sidebarLayout(
    sidebarPanel(
      selectInput("cyl", "Cylinder filter", choices = sort(unique(mtcars$cyl))),
      sliderInput("mpg_min", "Minimum mpg", min = 10, max = 35, value = 18)
    ),
    mainPanel(
      uiOutput("summary_card"),
      tableOutput("preview"),
      textOutput("count"),
      plotOutput("scatter")
    )
  )
)

server <- function(input, output, session) {
  filtered <- reactive({
    mtcars[mtcars$cyl == as.numeric(input$cyl) & mtcars$mpg >= input$mpg_min, ]
  })

  shared_metrics <- reactive({
    df <- filtered()
    data.frame(
      rows = nrow(df),
      avg_mpg = mean(df$mpg),
      avg_hp = mean(df$hp)
    )
  })

  output$summary_card <- renderUI({
    stats <- shared_metrics()
    tagList(
      metric_card("Rows", stats$rows),
      metric_card("Average mpg", round(stats$avg_mpg, 1)),
      metric_card("Average hp", round(stats$avg_hp, 1))
    )
  })

  output$preview <- renderTable({
    df <- filtered()
    df[, c("mpg", "hp", "wt")]
  })

  output$count <- renderText({
    paste("Filtered rows:", shared_metrics()$rows)
  })

  output$scatter <- renderPlot({
    df <- filtered()
    stats <- shared_metrics()
    plot(df$wt, df$mpg,
         main = paste("Average hp", round(stats$avg_hp, 1)),
         xlab = "wt", ylab = "mpg")
  })
}

shinyApp(ui, server)
