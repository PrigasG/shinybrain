# Package index

## Analyze Shiny code

- [`analyze_shiny_file()`](https://prigasg.github.io/shinybrain/reference/analyze_shiny_file.md)
  : Analyze a single Shiny R file
- [`analyze_shiny_project()`](https://prigasg.github.io/shinybrain/reference/analyze_shiny_project.md)
  : Analyze a full Shiny project directory
- [`detect_entry_point()`](https://prigasg.github.io/shinybrain/reference/detect_entry_point.md)
  : Detect the entry point of a Shiny project directory
- [`resolve_source_chain()`](https://prigasg.github.io/shinybrain/reference/resolve_source_chain.md)
  : Recursively resolve all source() chains from an entry file
- [`extract_source_calls()`](https://prigasg.github.io/shinybrain/reference/extract_source_calls.md)
  : Extract static source() call paths from parse data
- [`parse_file()`](https://prigasg.github.io/shinybrain/reference/parse_file.md)
  : Parse a single file through all 5 passes

## Build and inspect the App Brain

- [`brain_options()`](https://prigasg.github.io/shinybrain/reference/brain_options.md)
  : Brain export options
- [`build_brain()`](https://prigasg.github.io/shinybrain/reference/build_brain.md)
  : Build the App Brain from a ShinyBrain analysis result
- [`print_brain_console()`](https://prigasg.github.io/shinybrain/reference/print_brain_console.md)
  : Print a formatted console report from an App Brain
- [`summarize_analysis()`](https://prigasg.github.io/shinybrain/reference/summarize_analysis.md)
  : Print a concise summary of a ShinyBrain analysis result
- [`generate_insights()`](https://prigasg.github.io/shinybrain/reference/generate_insights.md)
  : Generate developer-facing insights from resolved IR
- [`compute_complexity()`](https://prigasg.github.io/shinybrain/reference/compute_complexity.md)
  : Compute a composite complexity score for the app

## Export outputs

- [`export_brain_json()`](https://prigasg.github.io/shinybrain/reference/export_brain_json.md)
  : Export App Brain to JSON
- [`export_brain_markdown()`](https://prigasg.github.io/shinybrain/reference/export_brain_markdown.md)
  : Export App Brain to Markdown
- [`export_brain_html()`](https://prigasg.github.io/shinybrain/reference/export_brain_html.md)
  : Export a self-contained HTML report from an App Brain

## Data structures and validation

- [`new_sb_context()`](https://prigasg.github.io/shinybrain/reference/new_sb_context.md)
  : Create an empty sb_context tibble
- [`new_sb_edge_candidate()`](https://prigasg.github.io/shinybrain/reference/new_sb_edge_candidate.md)
  : Create an empty sb_edge_candidate tibble
- [`new_sb_file()`](https://prigasg.github.io/shinybrain/reference/new_sb_file.md)
  : Create an empty sb_file tibble
- [`new_sb_issue()`](https://prigasg.github.io/shinybrain/reference/new_sb_issue.md)
  : Create an empty sb_issue tibble
- [`new_sb_node_candidate()`](https://prigasg.github.io/shinybrain/reference/new_sb_node_candidate.md)
  : Create an empty sb_node_candidate tibble
- [`new_sb_project()`](https://prigasg.github.io/shinybrain/reference/new_sb_project.md)
  : Create an empty sb_project tibble
- [`new_sb_reference()`](https://prigasg.github.io/shinybrain/reference/new_sb_reference.md)
  : Create an empty sb_reference tibble
- [`new_sb_symbol()`](https://prigasg.github.io/shinybrain/reference/new_sb_symbol.md)
  : Create an empty sb_symbol tibble
- [`validate_ir()`](https://prigasg.github.io/shinybrain/reference/validate_ir.md)
  : Validate an IR object against its expected schema
- [`validate_graph()`](https://prigasg.github.io/shinybrain/reference/validate_graph.md)
  : Validate graph integrity

## Supporting topics

- [`as_flag_list()`](https://prigasg.github.io/shinybrain/reference/as_flag_list.md)
  : Wrap a character vector into a list column value
- [`brain_builder`](https://prigasg.github.io/shinybrain/reference/brain_builder.md)
  : Brain Builder
- [`brain_export`](https://prigasg.github.io/shinybrain/reference/brain_export.md)
  : LLM Export Layer
- [`brain_report`](https://prigasg.github.io/shinybrain/reference/brain_report.md)
  : Report Layer
- [`build_edges()`](https://prigasg.github.io/shinybrain/reference/build_edges.md)
  : Build edge candidates from resolved references
- [`build_nodes()`](https://prigasg.github.io/shinybrain/reference/build_nodes.md)
  : Promote contexts to graph node candidates
- [`build_symbols()`](https://prigasg.github.io/shinybrain/reference/build_symbols.md)
  : Build sb_symbol tibble from parsed contexts and references
- [`compute_usage_weights()`](https://prigasg.github.io/shinybrain/reference/compute_usage_weights.md)
  : Compute usage_count for helper_fn and state nodes
- [`CONFIDENCE_LEVELS`](https://prigasg.github.io/shinybrain/reference/CONFIDENCE_LEVELS.md)
  : Valid confidence levels
- [`CONTEXT_TYPES`](https://prigasg.github.io/shinybrain/reference/CONTEXT_TYPES.md)
  : Valid context types Note: "module_def" and "module_instance" are
  reserved for future module support but are not produced by the current
  parser. "ui_block" and "global_block" were removed in 0.1.0; the
  parser classifies top-level UI and global.R content as "unknown" or
  "helper_fn" instead.
- [`EDGE_TYPES`](https://prigasg.github.io/shinybrain/reference/EDGE_TYPES.md)
  : Valid edge types
- [`extract_contexts()`](https://prigasg.github.io/shinybrain/reference/extract_contexts.md)
  : Extract context objects from parse data
- [`extract_references()`](https://prigasg.github.io/shinybrain/reference/extract_references.md)
  : Extract intra-context references from parse data
- [`extract_snippet()`](https://prigasg.github.io/shinybrain/reference/extract_snippet.md)
  : Extract a code snippet for a context
- [`graph_layer`](https://prigasg.github.io/shinybrain/reference/graph_layer.md)
  : Graph Layer
- [`insights_layer`](https://prigasg.github.io/shinybrain/reference/insights_layer.md)
  : Insights Layer
- [`io`](https://prigasg.github.io/shinybrain/reference/io.md) : IO
  Layer
- [`ir_constructors`](https://prigasg.github.io/shinybrain/reference/ir_constructors.md)
  : Internal Representation Constructors
- [`ISSUE_TYPES`](https://prigasg.github.io/shinybrain/reference/ISSUE_TYPES.md)
  : Valid issue types
- [`load_file()`](https://prigasg.github.io/shinybrain/reference/load_file.md)
  : Load a single R source file into an sb_file row
- [`lookup_symbol()`](https://prigasg.github.io/shinybrain/reference/lookup_symbol.md)
  : Look up a symbol by name in the symbols table
- [`make_id()`](https://prigasg.github.io/shinybrain/reference/make_id.md)
  : Generate a short deterministic ID from one or more strings
- [`make_issue()`](https://prigasg.github.io/shinybrain/reference/make_issue.md)
  : Build a single sb_issue row as a one-row tibble
- [`` `%||%` ``](https://prigasg.github.io/shinybrain/reference/null_coalesce.md)
  : Null coalescing operator
- [`parse_layer`](https://prigasg.github.io/shinybrain/reference/parse_layer.md)
  : Parse Layer
- [`parse_raw()`](https://prigasg.github.io/shinybrain/reference/parse_raw.md)
  : Parse a file and attach parse data
- [`phase_b`](https://prigasg.github.io/shinybrain/reference/phase_b.md)
  : Source Resolution and Multi-File Project Support
- [`REFERENCE_TYPES`](https://prigasg.github.io/shinybrain/reference/REFERENCE_TYPES.md)
  : Valid reference types
- [`resolve_layer`](https://prigasg.github.io/shinybrain/reference/resolve_layer.md)
  : Resolve Layer
- [`resolve_references()`](https://prigasg.github.io/shinybrain/reference/resolve_references.md)
  : Resolve references to symbol IDs where possible
- [`scan_top_level()`](https://prigasg.github.io/shinybrain/reference/scan_top_level.md)
  : Scan top-level expressions from parse data
- [`SEVERITY_LEVELS`](https://prigasg.github.io/shinybrain/reference/SEVERITY_LEVELS.md)
  : Valid severity levels
- [`shinybrain`](https://prigasg.github.io/shinybrain/reference/shinybrain-package.md)
  [`shinybrain-package`](https://prigasg.github.io/shinybrain/reference/shinybrain-package.md)
  : shinybrain: Static analysis for Shiny applications
- [`shinybrain_analysis`](https://prigasg.github.io/shinybrain/reference/shinybrain_analysis.md)
  : ShinyBrain Analysis Functions
- [`SYMBOL_TYPES`](https://prigasg.github.io/shinybrain/reference/SYMBOL_TYPES.md)
  : Valid symbol types Note: "module_def" and "module_instance" are
  reserved for future module support but are not produced by the current
  resolver.
- [`UNRESOLVED_TYPES`](https://prigasg.github.io/shinybrain/reference/UNRESOLVED_TYPES.md)
  : Valid unresolved reason types
- [`utils`](https://prigasg.github.io/shinybrain/reference/utils.md) :
  Internal utility functions
