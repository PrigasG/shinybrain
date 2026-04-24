dir.create("pkgdown", showWarnings = FALSE, recursive = TRUE)
cache_dir <- file.path("pkgdown", "cache")
dir.create(cache_dir, showWarnings = FALSE, recursive = TRUE)
Sys.setenv(R_USER_CACHE_DIR = normalizePath(cache_dir, winslash = "/", mustWork = FALSE))

ignored_md <- c(
  "README.md", "LICENSE.md", "LICENCE.md", "NEWS.md", "cran-comments.md",
  "CLAUDE.md", "pain-point.md", "shinybrain_build.md"
)

assignInNamespace(
  "cran_link",
  value = function(pkg) {
    list(
      repo = "GitHub",
      url = sprintf("https://github.com/PrigasG/%s", pkg)
    )
  },
  ns = "pkgdown"
)

assignInNamespace(
  "package_mds",
  value = function(path, in_dev = FALSE) {
    mds <- list.files(path, pattern = "\\.md$", full.names = TRUE, recursive = FALSE)
    github_path <- file.path(path, ".github")
    if (dir.exists(github_path)) {
      mds <- c(mds, list.files(github_path, pattern = "\\.md$", full.names = TRUE, recursive = FALSE))
    }
    mds <- mds[!basename(mds) %in% ignored_md]
    if (in_dev) {
      mds <- mds[basename(mds) != "404.md"]
    }
    unname(mds)
  },
  ns = "pkgdown"
)

pkgdown::build_site(
  ".",
  install = FALSE,
  new_process = FALSE,
  preview = FALSE,
  devel = FALSE,
  lazy = FALSE,
  examples = FALSE
)
