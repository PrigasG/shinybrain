library(shiny)

source("helpers.R")
source("modules.R")

ui <- fluidPage(
  titlePanel("V2 legacy app"),
  sidebarLayout(
    sidebarPanel(
      numericInput("min_mpg", "Minimum mpg", value = 18, min = 10, max = 35),
      actionButton("save_btn", "Save snapshot"),
      checkboxInput("show_details", "Show details", value = TRUE)
    ),
    mainPanel(
      legacySummaryUI("summary"),
      plotOutput("fleet_plot"),
      uiOutput("details_ui"),
      tableOutput("details_table")
    )
  )
)

server <- function(input, output, session) {
  legacySummaryServer("summary")
  orphanServer("orphan")

  filtered <- reactive({
    filter_fleet(mtcars, input$min_mpg)
  })

  dead_summary <- reactive({
    summarize_fleet(filtered())
  })

  observeEvent(input$save_btn, {
    write.csv(filtered(), tempfile(fileext = ".csv"), row.names = FALSE)
  })

  output$fleet_plot <- renderPlot({
    df <- filtered()
    plot(df$wt, df$mpg, xlab = "Weight", ylab = "MPG")
  })

  output$details_ui <- renderUI({
    if (isTRUE(input$show_details)) {
      tableOutput("details_table")
    } else {
      p("Details hidden")
    }
  })

  output$details_table <- renderTable({
    filtered()[, c("mpg", "hp", "wt")]
  })
}

shinyApp(ui, server)
