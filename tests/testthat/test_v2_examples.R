library(testthat)

.sb_source_all <- function() {
  r_dir <- testthat::test_path("..", "..", "R")
  if (!dir.exists(r_dir)) return(invisible())
  r_files <- list.files(r_dir, pattern = "\\.R$",
                        recursive = TRUE, full.names = TRUE)
  invisible(lapply(r_files, source))
}
if (!exists("analyze_shiny_file", mode = "function")) .sb_source_all()

.example_dir <- function(name) {
  testthat::test_path("..", "..", "inst", "examples", name)
}

test_that("v2_hotspot_app surfaces a reactive hotspot in prioritized findings", {
  app_dir <- .example_dir("v2_hotspot_app")
  skip_if_not(dir.exists(app_dir), "v2_hotspot_app not found")

  brain <- build_brain(analyze_shiny_project(app_dir))

  hotspot <- brain$insights[brain$insights$category == "reactive_hotspot", ]
  expect_gte(nrow(hotspot), 1L)
  expect_true(any(hotspot$label %in% c("filtered", "shared_metrics")))
  expect_true(length(brain$summary$top_findings) >= 1L)
  expect_true(any(vapply(brain$summary$top_findings, `[[`, "", "category") ==
                    "reactive_hotspot"))
})

test_that("v2_dead_reactive_app surfaces an unused reactive with guidance", {
  app_dir <- .example_dir("v2_dead_reactive_app")
  skip_if_not(dir.exists(app_dir), "v2_dead_reactive_app not found")

  brain <- build_brain(analyze_shiny_project(app_dir))

  dead <- brain$insights[brain$insights$category == "dead_reactive", ]
  expect_gte(nrow(dead), 1L)
  expect_true(any(dead$label == "unused_summary"))
  expect_true(any(grepl("Remove|connect", dead$recommendation)))
})

test_that("v2_side_effect_app surfaces unguarded side effects", {
  app_dir <- .example_dir("v2_side_effect_app")
  skip_if_not(dir.exists(app_dir), "v2_side_effect_app not found")

  brain <- build_brain(analyze_shiny_project(app_dir))

  sidefx <- brain$insights[brain$insights$category == "unguarded_side_effect", ]
  expect_gte(nrow(sidefx), 1L)
  expect_true(any(grepl("observer|event|isolate", sidefx$recommendation)))
})

test_that("v2_legacy_app surfaces module linkage and lower confidence cues", {
  app_dir <- .example_dir("v2_legacy_app")
  skip_if_not(dir.exists(app_dir), "v2_legacy_app not found")

  result <- analyze_shiny_project(app_dir)
  brain <- build_brain(result)

  module_issues <- result$issues[result$issues$issue_type == "module_link_incomplete", ]
  expect_gte(nrow(module_issues), 1L)
  expect_true(any(grepl("orphan", module_issues$message, ignore.case = TRUE)))

  dynamic_ui <- result$issues[result$issues$issue_type == "unsupported_pattern", ]
  expect_gte(nrow(dynamic_ui), 1L)
  expect_true(any(grepl("renderUI", dynamic_ui$message, fixed = TRUE)))

  module_contexts <- result$contexts[!is.na(result$contexts$module_id), ]
  expect_gte(nrow(module_contexts), 1L)
  expect_true(any(module_contexts$label == "ranked_data"))

  expect_true(brain$summary$analysis_confidence$label %in% c("Moderate", "Low"))
})
