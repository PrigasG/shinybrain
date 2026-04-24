# Pain points

Running log of friction encountered while working on shinybrain and project_hub.

## 2026-04-20 Posit Connect migration (project_hub Shiny app)

### Logout cookie path mismatch
- **Root cause**: The `doLogout` JS handler cleared the login cookie with `path=/` only.
  On Posit Connect the app lives at a subpath (e.g. `/content/123/`), so the `login` package
  sets the cookie scoped to that subpath. Clearing at `path=/` silently fails.
- **Symptom**: After clicking Logout or OK on the Pending Approval modal the page reloads
  but the user is still "logged in" according to the cookie, causing an infinite approval loop.
- **Fix (app.R ~line 3056)**: Replaced `doLogout` JS to call a shared helper
  `_clearCookieAllPaths` that iterates every path segment of `window.location.pathname`
  and deletes the cookie at each level. Also added a separate `clearLoginCookie` handler
  that does the same without reloading (used after account creation).

### Account creation triggers logout loop on Posit Connect
- **Root cause**: After a new user submits the Create Account form (`ca_submit` handler),
  `login::login_server` detects valid credentials in the DB and fires `USER$logged_in = TRUE`
  before the user dismisses the backup-codes modal. The approval observer sees `approved=0`,
  forces `USER$logged_in = FALSE`, and shows the "Account Pending Approval" modal. Clicking OK
  calls `doLogout`, which (before the cookie fix) failed to clear the cookie, causing an
  infinite reload loop.
- **Fix (app.R)**: Two changes:
  1. After successful account insert, set `session$userData$just_created_account <- TRUE`
     and call `clearLoginCookie` to silently clear any stale cookie.
  2. At the top of `observeEvent(USER$logged_in)`, if `just_created_account` is TRUE,
     silently reset login state and return without showing the Pending Approval modal.
     The flag is consumed on first use so subsequent real login attempts work normally.

### Files not to deploy to Posit Connect
- `run.R` and `LaunchApp.hta` are Windows local-launch scripts; exclude from the deploy manifest.
- The entire `/R/` directory (bundled portable R runtime) must not be pushed to Connect.
- `HUB_DATA_SRC_SP` env var must NOT be set on Connect (it references a Windows SharePoint path).
- `HUB_DATA_PATH` must be set on Connect to a persistent directory outside the app bundle so
  parquet files and `users.sqlite` survive redeployments.

### Windows-only code paths (low risk on Connect)
- `open_pdf()` in `utils.R` uses `shell.exec()` guarded by `.Platform$OS.type == "windows"`,
  so it falls through to `browseURL` on Linux. No crash risk but `browseURL` is a no-op on a
  headless server. Not called in any normal server-side flow.
- `to_file_uri()` produces `file://` URIs from Windows UNC/drive paths. These will not resolve
  for users hitting a remote server. Stored SOP paths that are Windows paths will be broken links.

## 2026-04-20 review and fixup pass

### Sandbox cannot run R
- R is not installed in the current execution sandbox (`R --version` reports `command not found`).
- All verification of test behaviour had to be done by static reading rather than running `devtools::test()` or `R CMD check`.
- Consequence: edits such as the state read/write classification cannot be dynamically proven correct here. They must be re-run by the user or in a CI environment that has R available.

### Cannot delete the brace-expansion cruft directory
- `tests/{testthat,fixtures/` and its nested child `{basic_single_file,observer_and_state,source_chain}}/` exist as the result of a `mkdir` command that used braces under a shell that did not expand them.
- Attempts to `rm -rf` and `python shutil.rmtree` both fail with `EPERM` (Operation not permitted) on the inner directory.
- Workaround: the outer directory is added to `.Rbuildignore` so `R CMD build` / `R CMD check` will not include it in the tarball. The user should delete the directory manually outside the sandbox using the native file manager or a shell with sufficient permissions.

### No `man/` .Rd files generated
- The package has full `#' @export` and roxygen metadata but `man/` is empty because `devtools::document()` has never been run.
- `NAMESPACE` has been written by hand this pass so that `library(shinybrain)` will expose the public API.
- `R CMD check` will still warn about undocumented code objects until the user runs `devtools::document()` locally.

### State read vs write classification
- The spec (fixture 2 in `shinybrain_build.md`) wants `rv(val)` to be classified as `state_write` and `rv()` as `state_read`.
- The previous implementation left both as `function_call` and punted to a "Sprint 2" note.
- This pass adds argument-count detection on the parse tree to separate the two cases. The implementation relies on `getParseData()` shape which may vary slightly across R versions; if tests fail on older R, revisit `.call_arg_count()`.

### `%>%` pipe leaked into test files
- The three `tests/testthat/test_*.R` files used a magrittr pipe to locate source files without declaring magrittr as a dependency.
- Replaced with a base-R helper that looks under `<pkg_root>/R`. The helper only runs when functions are not already on the search path, so installed-package test runs skip the sourcing step.

## 2026-04-21 devtools::document() fallout

### Source files hidden inside `R/` subdirectories
- **Symptom**: `devtools::document()` warned `Objects listed as exports, but not present in namespace` for 29 of 31 exported symbols. Only `analyze_shiny_file` and `summarize_analysis` loaded.
- **Root cause**: The package was laid out with `R/brain/`, `R/graph/`, `R/io/`, `R/ir/`, `R/parse/`, `R/resolve/`, `R/utils/`. R package loading only sources `.R` files at the top level of `R/`; subdirectories are silently ignored. Every file inside the subdirectories was invisible to the package loader.
- **Fix**: Flattened the layout. All files moved to `R/` top level: `brain.R`, `export.R`, `insights.R`, `report.R`, `graph.R`, `io.R`, `project.R`, `constructors.R`, `parse.R`, `resolve.R`, `helpers.R`.
- **Sandbox blocker**: `rmdir` on the (now empty) `R/<subdir>/` directories fails with EPERM just like the earlier cruft directory. Added an `.Rbuildignore` rule so they are excluded from the source tarball. User must delete the empty directories manually on the host.

### NAMESPACE was skipped by `devtools::document()`
- **Symptom**: `Skipping NAMESPACE: It already exists and was not generated by roxygen2.`
- **Root cause**: roxygen2 refuses to overwrite a NAMESPACE that lacks its magic header comment.
- **Fix**: Replaced the first line of NAMESPACE with the expected `# Generated by roxygen2: do not edit by hand` marker. Created `R/shinybrain-package.R` containing the package-level `@importFrom` tags (for `tibble`, `rlang`, `utils`, `stats`) so that regeneration preserves those imports. Next `devtools::document()` should now overwrite NAMESPACE cleanly and produce the same 31 exports plus the four imports.

## 2026-04-22 basic_app example surfaced four bugs

Running the example runner against `examples/basic_app/` and reading the resulting HTML uncovered four concrete gaps. All four are now wired in.

### 1. `message`/`print`/`cat` were dropped before reaching insights
- **Root cause**: they sat in `skip_calls` inside `.extract_refs_for_context`, so no reference was ever emitted, and the side-effect insight layer had nothing to flag.
- **Fix**: moved them out of `skip_calls` and into `SIDE_EFFECT_FNS` so they flow through as `function_call` references and are recognized as side effects.

### 2. `reactiveValues` `$` reads and `$<-` writes produced no edges
- **Root cause**: the parser only emitted references for `input$x` / `output$y` dollar access. Any other `obj$key` read was silently dropped, so `counters$clicks` and similar had no edge to their state node.
- **Fix**: the `$` handler in `.extract_refs_for_context` now walks up to the enclosing assignment `expr` to detect whether the dollar access is on the LHS of `<-` / `=` / `->`. LHS becomes `state_write`, otherwise `state_read`. `resolve_references` verifies the base name is a known state symbol (matches `state_values` or `state_val`), otherwise marks it `not_a_state_object` and the edge builder skips it.

### 3. Missing sourced files were silently dropped from the graph
- **Root cause**: `resolve_source_chain` bailed out when a `source()` target did not exist, so the user saw nothing in the nodes table about the broken link.
- **Fix**: missing paths are now appended to `state$ordered_paths` with `role = "missing"` and a `severity = "warning"` issue is emitted. `build_nodes` accepts a `files` argument and emits a `missing_file` ghost node for each missing path. `.vis_nodes` renders these with a dashed red box so they are visually distinct. `brain_options(strict_missing_sources = TRUE)` elevates the warnings to errors for CI gates. `load_file` suppresses a second duplicate issue when called with `role = "missing"`.

### 4. `saved(NULL)` was classified as `state_read` instead of `state_write`
- **Root cause**: `.count_call_args` counted `expr` children between the parens. R's parser does not always wrap literal constants (`NULL_CONST`, `NUM_CONST`, `STR_CONST`, `TRUE`, `FALSE`, `NA`) in an enclosing `expr` token, so for `saved(NULL)` the sole argument appeared as a bare `NULL_CONST` and the count came back 0. `resolve_references` then used 0 to classify it as a read.
- **Fix**: `.count_call_args` now counts top-level commas between the parens. Zero children returns 0; otherwise it returns `n_commas + 1`. This is independent of whether the parser wraps literals in `expr`.
- **Diagnostic**: added `brain_options(verbose = TRUE)`. When set, `build_brain` prints every state-like reference with its `target_arg_count`, resolved symbol, and whether an edge was produced, so future mystery drops surface immediately.

## 2026-04-22 error message audit

Swept every `rlang::abort` and `make_issue` call and rewrote each to answer three questions: what happened, where (file + line), what to do next. The previous messages were too terse to be useful on their own, e.g. `"Dynamic source() path at line 12 - skipped"` did not say which file the line referred to, what a "dynamic" path meant, or how to fix it.

Concrete changes (all in the `R/` top-level sources):

- `R/project.R`: dynamic `source()` warnings now name the calling file, explain the runtime-path cause, and suggest replacing with a bare string literal. Missing `source()` targets show the raw path, the resolved candidate, and the calling file + line. Circular source chains now print the full `a.R -> b.R -> a.R` cycle and suggest a fix. The catch-all "Directory not found" from `analyze_shiny_project()` explains what paths are accepted and points at `analyze_shiny_file()` for single-file use.
- `R/io.R`: `detect_entry_point()` now lists the .R files that WERE present in the directory, flags ui.R-without-server.R (or vice versa) as a near-miss, and suggests `analyze_shiny_file()` or a subdirectory if the layout is non-standard. `load_file()` surfaces the underlying `readLines()` error (locked file, permissions, bad encoding) instead of the useless "Could not read file" string. "File is empty" notes it is informational only and completed successfully.
- `R/parse.R`: parse-failure messages are prefixed with the file basename, include R's own parse error, and show the exact `parse(file = "...")` call to reproduce outside shinybrain. Side-effect flag messages now explain WHY shinybrain flagged the call (effect is not represented as a graph edge) and when it is safe to ignore.
- `R/constructors.R`: `validate_ir()` schema errors list the valid schema names, the columns it expected, the columns it actually got, and point at `new_sb_<schema>()` as the starting point for a hand-built tibble. Type-mismatch errors suggest the fix.
- `R/graph.R`: duplicate-node-id and orphan-edge messages are tagged "Internal" and labelled as shinybrain bugs with a request to report them. End users should never see these, but if they do they now know it's not their code.
- `R/export.R`: the `jsonlite` missing-package error mentions `export_brain_markdown()` as a dependency-free alternative.

All touched files pass a state-machine paren/brace balance check and contain no em-dashes. Messages were kept as plain ASCII so they render correctly in the CLI, the HTML report, and JSON export.
