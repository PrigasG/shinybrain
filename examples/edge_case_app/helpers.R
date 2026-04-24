# Minimal helpers file for the edge-case app. Resolves successfully; its
# purpose is to make the missing_file issue point only at "does_not_exist.R"
# and not at this file as well.

noop <- function(...) invisible(NULL)
