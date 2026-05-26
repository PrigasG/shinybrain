library(testthat)

.sb_source_all <- function() {
  r_dir <- testthat::test_path("..", "..", "R")
  if (!dir.exists(r_dir)) return(invisible())
  r_files <- list.files(r_dir, pattern = "\\.R$",
                        recursive = TRUE, full.names = TRUE)
  invisible(lapply(r_files, source))
}
if (!exists("analyze_shiny_file", mode = "function")) .sb_source_all()

test_that("build_brain surfaces prioritized findings with recommendations", {
  tmp <- tempfile(fileext = ".R")
  writeLines(c(
    "library(shiny)",
    "server <- function(input, output, session) {",
    "  shared <- reactive({ input$x + input$y })",
    "  derived <- reactive({ shared() * 2 })",
    "  output$one <- renderText({ shared() })",
    "  output$two <- renderText({ shared() + derived() })",
    "  output$three <- renderText({ shared() + derived() + 1 })",
    "}"
  ), tmp)
  on.exit(unlink(tmp))

  result <- analyze_shiny_file(tmp)
  brain <- build_brain(result)

  expect_true(nrow(brain$insights) >= 1L)
  expect_true(all(c("recommendation", "score") %in% names(brain$insights)))
  expect_true(any(brain$insights$category == "reactive_hotspot"))
  expect_true(length(brain$summary$top_findings) >= 1L)
  expect_true(is.character(brain$summary$top_findings[[1]]$recommendation))
  expect_true(is.numeric(brain$insights$score) || is.integer(brain$insights$score))
  expect_true("analysis_confidence" %in% names(brain$summary))
  expect_true(brain$summary$analysis_confidence$label %in% c("High", "Moderate", "Low"))
})

test_that("Markdown export includes prioritized findings and recommendations", {
  tmp <- tempfile(fileext = ".R")
  writeLines(c(
    "library(shiny)",
    "server <- function(input, output, session) {",
    "  shared <- reactive({ input$x + input$y })",
    "  output$one <- renderText({ shared() })",
    "  output$two <- renderText({ shared() + 1 })",
    "  output$three <- renderText({ shared() + 2 })",
    "}"
  ), tmp)
  on.exit(unlink(tmp))

  brain <- build_brain(analyze_shiny_file(tmp))
  md <- export_brain_markdown(brain)

  expect_match(md, "## Prioritized Findings", fixed = TRUE)
  expect_match(md, "Recommendation:", fixed = TRUE)
})
