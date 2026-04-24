library(shiny)

source("helpers.R")

ui <- fluidPage(
  titlePanel("shinybrain example app"),
  sidebarLayout(
    sidebarPanel(
      selectInput("dataset", "Dataset:", choices = c("mtcars", "iris")),
      numericInput("cutoff", "Minimum column mean:", value = 5, min = 0),
      actionButton("go_btn",    "Run summary"),
      actionButton("save_btn",  "Save to CSV"),
      actionButton("reset_btn", "Reset state")
    ),
    mainPanel(
      textOutput("status"),
      tableOutput("preview"),
      plotOutput("chart")
    )
  )
)

server <- function(input, output, session) {

  # ---- State nodes -----------------------------------------------------
  saved    <- reactiveVal(NULL)
  counters <- reactiveValues(runs = 0, saves = 0)

  # ---- Derived reactives ----------------------------------------------
  dataset <- reactive({
    req(input$dataset)
    get(input$dataset)
  })

  filtered <- reactive({
    df <- dataset()
    filter_by_threshold(df, input$cutoff)
  })

  summary_data <- eventReactive(input$go_btn, {
    counters$runs <- counters$runs + 1
    summarize_numeric(filtered())
  })

  # ---- Observers -------------------------------------------------------
  observeEvent(input$save_btn, {
    df <- filtered()
    saved(df)
    counters$saves <- counters$saves + 1
    write.csv(df, file = "saved.csv", row.names = FALSE)
    message("Saved ", nrow(df), " rows")
  })

  observeEvent(input$reset_btn, {
    saved(NULL)
    counters$runs  <- 0
    counters$saves <- 0
  })

  observe({
    if (counters$runs > 10) {
      message("High run count: ", counters$runs)
    }
  })

  # ---- Outputs ---------------------------------------------------------
  output$status <- renderText({
    if (is.null(saved())) {
      sprintf("No save yet. Runs: %d", counters$runs)
    } else {
      sprintf("Saved %d rows. Runs: %d, Saves: %d",
              nrow(saved()), counters$runs, counters$saves)
    }
  })

  output$preview <- renderTable({
    head(filtered(), 10)
  })

  output$chart <- renderPlot({
    df <- summary_data()
    plot(df$mean, type = "h",
         main = "Column means above cutoff",
         xlab = "", ylab = "mean")
  })
}

shinyApp(ui, server)
