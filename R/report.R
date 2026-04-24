#' @title Report Layer
#' @description Human-facing output: console summary and self-contained HTML
#'   report with a reactive graph visualization.
#' @name brain_report
NULL

# ---- Console report ---------------------------------------------------------

#' Print a formatted console report from an App Brain
#'
#' @param brain App Brain from build_brain()
#' @return Invisibly returns the brain.
#' @export
print_brain_console <- function(brain) {
  s   <- brain$summary
  ins <- brain$insights
  nd  <- brain$nodes
  ed  <- brain$edges

  .rule <- function(char = "-", width = 60) {
    cat(strrep(char, width), "\n")
  }
  .h <- function(txt) {
    cat("\n")
    .rule("=")
    cat(" ", txt, "\n")
    .rule("=")
  }
  .h2 <- function(txt) {
    cat("\n ", txt, "\n")
    cat(" ", strrep("-", nchar(txt)), "\n")
  }

  cat("\n")
  .rule("=")
  app_name <- tryCatch(
    basename(brain$project$root_path),
    error = function(e) "Shiny App"
  )
  cat("  ShinyBrain Report\u2003\u2003", app_name, "\n")
  cat("  shinybrain ", .brain_version(brain), "\u2003\u2003",
      format(Sys.time(), "%Y-%m-%d %H:%M", tz = "UTC"), " UTC\n")
  .rule("=")

  # Complexity badge
  cx <- s$complexity
  cx_bar <- .complexity_bar(cx$score)
  cat("\n  Complexity:", cx$label, "(", cx$score, "/ 100 )", cx_bar, "\n")
  cat("  Chain depth:", s$max_chain_depth,
      if (s$max_chain_depth > 4) " \u26a0  deep pipeline" else "", "\n")

  # Stats
  .h2("At a Glance")
  cat("  Files         :", s$n_files, "\n")
  cat("  Contexts      :", s$n_contexts, "\n")
  cat("  Nodes         :", s$n_nodes, "\n")
  cat("  Edges         :", s$n_edges, "\n")
  cat("  Unresolved    :", s$n_unresolved, "\n")

  if (length(s$node_breakdown) > 0) {
    cat("  Node types    :")
    for (nm in names(s$node_breakdown)) {
      cat("", nm, "\u00d7", s$node_breakdown[[nm]], " ")
    }
    cat("\n")
  }

  # Files
  if (nrow(brain$files) > 0) {
    .h2("Files")
    for (i in seq_len(nrow(brain$files))) {
      f <- brain$files[i, ]
      status <- if (isTRUE(f$parse_success)) "\u2713" else "\u2717"
      cat(" ", status, f$relative_path,
          "(", f$role, ",", f$line_count, "lines )\n")
    }
  }

  # Reactive graph summary
  if (nrow(nd) > 0) {
    .h2("Reactive Graph")
    types_present <- unique(nd$node_type)
    for (tp in types_present) {
      these <- nd[nd$node_type == tp, ]
      cat("  [", tp, "]\n")
      for (i in seq_len(nrow(these))) {
        uc <- these$usage_count[i]
        uc_note <- if (uc > 0) paste0("  \u2192 used by ", uc) else ""
        iso <- if (isTRUE(these$contains_isolate[i])) "  \u29b6 isolate" else ""
        cat("    \u2022", these$label[i], uc_note, iso, "\n")
      }
    }
  }

  # Insights
  .h2("Insights")
  if (nrow(ins) == 0) {
    cat("  OK  No issues found - looking clean!\n")
  } else {
    sev_icons <- c(error = "\u274c", warning = "\u26a0\ufe0f ", info = "\u2139\ufe0f ")
    sev_order <- c("error", "warning", "info")
    for (sev in sev_order) {
      rows <- ins[ins$severity == sev, ]
      if (nrow(rows) == 0) next
      for (i in seq_len(nrow(rows))) {
        icon <- sev_icons[sev]
        # Word-wrap at 72 chars
        msg <- .wrap(paste0("[", toupper(sev), "] ", rows$message[i]),
                     width = 68, indent = "     ")
        cat(" ", icon, msg, "\n\n")
      }
    }
  }

  # Hard issues from pipeline
  hard <- brain$issues[brain$issues$severity %in% c("error", "warning"), ]
  if (nrow(hard) > 0) {
    .h2("Pipeline Issues")
    for (i in seq_len(nrow(hard))) {
      cat("  \u26a0\ufe0f  [", toupper(hard$severity[i]), "] ", hard$message[i], "\n")
    }
  }

  .rule("=")
  cat("\n  Run shinybrain_report(..., format = \"html\") for the interactive report.\n\n")

  invisible(brain)
}

# ---- HTML report ------------------------------------------------------------

#' Export a self-contained HTML report from an App Brain
#'
#' Produces a polished HTML file with a reactive graph visualization
#' (powered by vis.js via CDN), insight cards, and full node/edge tables.
#'
#' @param brain App Brain from build_brain()
#' @param file Path to write the HTML file. NULL auto-generates in the working
#'   directory.
#' @param open Logical. Open the file in the default browser after writing.
#' @return Invisibly returns the file path.
#' @export
export_brain_html <- function(brain, file = NULL, open = TRUE) {
  if (is.null(file)) {
    app_slug <- gsub("[^a-zA-Z0-9_-]", "_",
                     basename(brain$project$root_path %||% "shinybrain"))
    file <- file.path(getwd(),
                      paste0("shinybrain_", app_slug, "_",
                             format(Sys.Date(), "%Y%m%d"), ".html"))
  }

  html <- .build_html(brain)
  writeLines(html, file, useBytes = FALSE)
  message("Report saved to: ", file)
  if (open && interactive()) utils::browseURL(file)
  invisible(file)
}

# ---- HTML builder -----------------------------------------------------------

.build_html <- function(brain) {
  s       <- brain$summary
  nodes   <- brain$nodes
  edges   <- brain$edges
  ins     <- brain$insights
  issues  <- brain$issues
  files   <- brain$files

  app_name <- tryCatch(basename(brain$project$root_path),
                        error = function(e) "Shiny App")
  version  <- .brain_version(brain)
  ts       <- format(Sys.time(), "%Y-%m-%d %H:%M UTC", tz = "UTC")
  cx       <- s$complexity

  # Vis.js node/edge data
  vis_nodes <- .vis_nodes(nodes)
  vis_edges <- .vis_edges(edges, nodes)

  # Insight cards HTML
  insight_cards <- .insight_cards_html(ins)

  # Node table rows
  node_rows <- .table_rows(nodes, c("label", "node_type", "file_id",
                                     "line_start", "usage_count", "confidence"))
  # Edge table rows
  node_labels <- if (nrow(nodes) > 0)
    stats::setNames(nodes$label, nodes$node_id) else character()
  edge_rows <- .edge_table_rows(edges, node_labels)

  # Files table
  file_rows <- .table_rows(files, c("relative_path", "role", "line_count",
                                     "parse_success"))

  cx_pct   <- cx$score
  cx_color <- if (cx$score <= 25) "#22c55e"
              else if (cx$score <= 50) "#f59e0b"
              else if (cx$score <= 75) "#f97316"
              else "#ef4444"

  n_errors   <- sum(ins$severity == "error",   na.rm = TRUE)
  n_warnings <- sum(ins$severity == "warning", na.rm = TRUE)
  n_info     <- sum(ins$severity == "info",    na.rm = TRUE)

  paste0('<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>ShinyBrain: ', .he(app_name), '</title>
<style>
  *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
  body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
         background: #f1f5f9; color: #1e293b; font-size: 14px; line-height: 1.6; }
  a { color: #6366f1; }

  /* Header */
  .header { background: linear-gradient(135deg, #1e1b4b 0%, #312e81 60%, #4c1d95 100%);
             color: #fff; padding: 28px 36px; display: flex;
             align-items: center; justify-content: space-between; flex-wrap: wrap; gap: 12px; }
  .header h1 { font-size: 22px; font-weight: 700; letter-spacing: -0.3px; }
  .header h1 span { color: #a5b4fc; }
  .header-meta { font-size: 12px; color: #c7d2fe; }
  .badge { display: inline-block; padding: 2px 10px; border-radius: 99px;
           font-size: 11px; font-weight: 600; background: rgba(255,255,255,0.15);
           color: #e0e7ff; border: 1px solid rgba(255,255,255,0.2); }

  /* Layout */
  .container { max-width: 1400px; margin: 0 auto; padding: 24px 24px 48px; }

  /* Stat cards */
  .stat-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(140px, 1fr));
               gap: 14px; margin-bottom: 24px; }
  .stat-card { background: #fff; border-radius: 12px; padding: 18px 20px;
               box-shadow: 0 1px 3px rgba(0,0,0,.08); border: 1px solid #e2e8f0; }
  .stat-card .value { font-size: 32px; font-weight: 700; color: #1e293b;
                       line-height: 1.1; }
  .stat-card .label { font-size: 11px; font-weight: 600; text-transform: uppercase;
                       letter-spacing: .6px; color: #94a3b8; margin-top: 4px; }
  .stat-card.accent .value { color: #6366f1; }

  /* Complexity bar */
  .complexity-card { background: #fff; border-radius: 12px; padding: 20px 24px;
                     box-shadow: 0 1px 3px rgba(0,0,0,.08); border: 1px solid #e2e8f0;
                     margin-bottom: 24px; }
  .complexity-card h3 { font-size: 12px; font-weight: 600; text-transform: uppercase;
                         letter-spacing: .6px; color: #94a3b8; margin-bottom: 12px; }
  .cx-row { display: flex; align-items: center; gap: 16px; }
  .cx-score { font-size: 40px; font-weight: 800; color: ', cx_color, '; min-width: 56px; }
  .cx-label { font-size: 16px; font-weight: 600; color: #1e293b; }
  .cx-bar-track { flex: 1; height: 10px; background: #e2e8f0; border-radius: 99px;
                   overflow: hidden; }
  .cx-bar-fill  { height: 100%; border-radius: 99px;
                   background: ', cx_color, ';
                   width: ', cx_pct, '%; transition: width .6s ease; }
  .cx-depth { font-size: 12px; color: #64748b; margin-top: 8px; }

  /* Two-column layout */
  .two-col { display: grid; grid-template-columns: 1fr 360px; gap: 20px;
             margin-bottom: 24px; }
  @media (max-width: 900px) { .two-col { grid-template-columns: 1fr; } }

  /* Graph panel */
  .panel { background: #fff; border-radius: 12px; padding: 0;
           box-shadow: 0 1px 3px rgba(0,0,0,.08); border: 1px solid #e2e8f0;
           overflow: hidden; }
  .panel-header { padding: 14px 20px; border-bottom: 1px solid #f1f5f9;
                   font-weight: 600; font-size: 13px; color: #374151;
                   display: flex; align-items: center; gap: 8px; }
  #network { width: 100%; height: 420px; background: #fafbff; }

  /* Graph legend */
  .legend { display: flex; flex-wrap: wrap; gap: 10px; padding: 12px 20px;
             border-top: 1px solid #f1f5f9; }
  .legend-item { display: flex; align-items: center; gap: 5px;
                  font-size: 11px; color: #64748b; }
  .legend-dot { width: 10px; height: 10px; border-radius: 50%; flex-shrink: 0; }

  /* Insights panel */
  .insights-panel { overflow-y: auto; max-height: 480px; }
  .insight-card { padding: 14px 18px; border-bottom: 1px solid #f8fafc; }
  .insight-card:last-child { border-bottom: none; }
  .insight-card .ic-header { display: flex; align-items: center; gap: 8px;
                               margin-bottom: 4px; }
  .ic-badge { font-size: 10px; font-weight: 700; padding: 2px 8px;
               border-radius: 99px; text-transform: uppercase; letter-spacing: .5px; }
  .ic-badge.error   { background: #fee2e2; color: #b91c1c; }
  .ic-badge.warning { background: #fef3c7; color: #92400e; }
  .ic-badge.info    { background: #ede9fe; color: #5b21b6; }
  .ic-label { font-size: 12px; font-weight: 600; color: #374151; }
  .ic-msg   { font-size: 12px; color: #6b7280; line-height: 1.5; }
  .no-insights { padding: 40px 20px; text-align: center; color: #22c55e;
                  font-size: 14px; font-weight: 500; }

  /* Tables */
  .section { background: #fff; border-radius: 12px; padding: 0;
              box-shadow: 0 1px 3px rgba(0,0,0,.08); border: 1px solid #e2e8f0;
              margin-bottom: 20px; overflow: hidden; }
  .section-header { padding: 14px 20px; border-bottom: 1px solid #f1f5f9;
                     font-weight: 600; font-size: 13px; color: #374151;
                     display: flex; justify-content: space-between; align-items: center; }
  .section-toggle { font-size: 11px; color: #6366f1; cursor: pointer;
                     font-weight: 500; background: none; border: none; }
  .table-wrap { overflow-x: auto; }
  table { width: 100%; border-collapse: collapse; font-size: 12px; }
  th { background: #f8fafc; padding: 9px 14px; text-align: left; font-weight: 600;
       color: #64748b; font-size: 11px; text-transform: uppercase; letter-spacing: .5px;
       border-bottom: 1px solid #e2e8f0; white-space: nowrap; }
  td { padding: 9px 14px; border-bottom: 1px solid #f8fafc; vertical-align: top; }
  tr:last-child td { border-bottom: none; }
  tr:hover td { background: #f8fafc; }
  .tag { display: inline-block; padding: 1px 8px; border-radius: 99px;
          font-size: 10px; font-weight: 600; }
  .tag-reactive     { background: #ede9fe; color: #5b21b6; }
  .tag-output       { background: #d1fae5; color: #065f46; }
  .tag-input        { background: #dbeafe; color: #1e40af; }
  .tag-helper_fn    { background: #fef3c7; color: #92400e; }
  .tag-state        { background: #cffafe; color: #155e75; }
  .tag-observer     { background: #f1f5f9; color: #475569; }
  .tag-missing_file { background: #fee2e2; color: #b91c1c;
                      border: 1px dashed #b91c1c; }
  .mono { font-family: "SFMono-Regular", Menlo, Monaco, Consolas, monospace; }
  .muted { color: #94a3b8; }

  /* Search */
  .search-wrap { padding: 10px 20px; border-bottom: 1px solid #f1f5f9; }
  .search-input { width: 100%; padding: 7px 12px; border: 1px solid #e2e8f0;
                   border-radius: 8px; font-size: 12px; outline: none;
                   color: #374151; }
  .search-input:focus { border-color: #6366f1; }

  /* Footer */
  .footer { text-align: center; padding: 20px; color: #94a3b8; font-size: 11px; }
</style>
</head>
<body>

<div class="header">
  <div>
    <div class="header-meta" style="margin-bottom:6px">ShinyBrain</div>
    <h1>', .he(app_name), ' <span>App Brain Report</span></h1>
    <div class="header-meta" style="margin-top:6px">',
    ts, ' &nbsp;\u00b7&nbsp; shinybrain v', .he(version), '</div>
  </div>
  <div style="text-align:right">
    <div class="badge">', s$n_nodes, ' nodes</div>
    &nbsp;
    <div class="badge">', s$n_edges, ' edges</div>
    &nbsp;
    <div class="badge" style="background:',
    if (cx$score <= 25) 'rgba(34,197,94,.25)' else if (cx$score <= 50)
      'rgba(245,158,11,.25)' else 'rgba(239,68,68,.25)', '">\u25cf ',
    cx$label, ' Complexity</div>
  </div>
</div>

<div class="container">

  <!-- Stat cards -->
  <div class="stat-grid">
    <div class="stat-card">
      <div class="value">', s$n_files, '</div>
      <div class="label">Files</div>
    </div>
    <div class="stat-card">
      <div class="value">', s$n_contexts, '</div>
      <div class="label">Contexts</div>
    </div>
    <div class="stat-card">
      <div class="value">', s$n_nodes, '</div>
      <div class="label">Graph Nodes</div>
    </div>
    <div class="stat-card">
      <div class="value">', s$n_edges, '</div>
      <div class="label">Edges</div>
    </div>
    <div class="stat-card">
      <div class="value">', s$max_chain_depth, '</div>
      <div class="label">Chain Depth</div>
    </div>
    <div class="stat-card', if (n_errors > 0) ' accent' else '', '">
      <div class="value">', n_errors + n_warnings, '</div>
      <div class="label">Insights</div>
    </div>
  </div>

  <!-- Complexity bar -->
  <div class="complexity-card">
    <h3>App Complexity</h3>
    <div class="cx-row">
      <div class="cx-score">', cx$score, '</div>
      <div style="flex:1">
        <div class="cx-label">', cx$label, '</div>
        <div class="cx-bar-track" style="margin-top:8px">
          <div class="cx-bar-fill"></div>
        </div>
      </div>
    </div>
    <div class="cx-depth">Longest reactive chain: ', s$max_chain_depth,
    ' hop(s) from input to output</div>
  </div>

  <!-- Graph + Insights -->
  <div class="two-col">

    <!-- Reactive graph -->
    <div class="panel">
      <div class="panel-header">\ud83d\udd78\ufe0f Reactive Dependency Graph</div>
      <div id="network"></div>
      <div class="legend">
        <div class="legend-item"><div class="legend-dot" style="background:#3b82f6"></div> input</div>
        <div class="legend-item"><div class="legend-dot" style="background:#8b5cf6"></div> reactive</div>
        <div class="legend-item"><div class="legend-dot" style="background:#10b981"></div> output</div>
        <div class="legend-item"><div class="legend-dot" style="background:#f59e0b"></div> helper</div>
        <div class="legend-item"><div class="legend-dot" style="background:#06b6d4"></div> state</div>
        <div class="legend-item"><div class="legend-dot" style="background:#64748b"></div> observer</div>
        <div class="legend-item"><div class="legend-dot" style="background:#fee2e2;border:1px dashed #b91c1c"></div> missing file</div>
      </div>
    </div>

    <!-- Insights -->
    <div class="panel insights-panel">
      <div class="panel-header">\ud83d\udca1 Insights
        <span style="margin-left:auto;font-size:11px;font-weight:400;color:#94a3b8">',
        nrow(ins), ' finding(s)</span>
      </div>',
      insight_cards,
    '</div>

  </div>

  <!-- Nodes table -->
  <div class="section">
    <div class="section-header">
      Reactive Contexts &amp; Nodes
      <button class="section-toggle" onclick="toggleSection(\'nodes-body\')">hide/show</button>
    </div>
    <div id="nodes-body">
      <div class="search-wrap">
        <input class="search-input" placeholder="Filter nodes\u2026"
               oninput="filterTable(\'nodes-tbl\', this.value)">
      </div>
      <div class="table-wrap">
        <table id="nodes-tbl">
          <thead>
            <tr>
              <th>Label</th><th>Type</th><th>File</th>
              <th>Line</th><th>Usage</th><th>Confidence</th>
            </tr>
          </thead>
          <tbody>', node_rows, '</tbody>
        </table>
      </div>
    </div>
  </div>

  <!-- Edges table -->
  <div class="section">
    <div class="section-header">
      Dependency Edges
      <button class="section-toggle" onclick="toggleSection(\'edges-body\')">hide/show</button>
    </div>
    <div id="edges-body">
      <div class="search-wrap">
        <input class="search-input" placeholder="Filter edges\u2026"
               oninput="filterTable(\'edges-tbl\', this.value)">
      </div>
      <div class="table-wrap">
        <table id="edges-tbl">
          <thead>
            <tr><th>From</th><th>To</th><th>Type</th><th>Isolated</th><th>Confidence</th></tr>
          </thead>
          <tbody>', edge_rows, '</tbody>
        </table>
      </div>
    </div>
  </div>

  <!-- Files table -->
  <div class="section">
    <div class="section-header">
      Files
      <button class="section-toggle" onclick="toggleSection(\'files-body\')">hide/show</button>
    </div>
    <div id="files-body">
      <div class="table-wrap">
        <table>
          <thead>
            <tr><th>Path</th><th>Role</th><th>Lines</th><th>Parsed</th></tr>
          </thead>
          <tbody>', file_rows, '</tbody>
        </table>
      </div>
    </div>
  </div>

  <div class="footer">
    Generated by <strong>shinybrain</strong> v', .he(version), ' &nbsp;\u00b7&nbsp; ', ts, '
  </div>

</div>

<script src="https://unpkg.com/vis-network@9.1.9/standalone/umd/vis-network.min.js"></script>
<script>
var nodes = new vis.DataSet(', vis_nodes, ');
var edges = new vis.DataSet(', vis_edges, ');
var container = document.getElementById("network");
var data = { nodes: nodes, edges: edges };
var options = {
  layout: {
    hierarchical: {
      enabled: true,
      direction: "UD",
      sortMethod: "directed",
      levelSeparation: 90,
      nodeSpacing: 140
    }
  },
  physics: { enabled: false },
  interaction: { tooltipDelay: 100, hover: true },
  nodes: {
    shape: "box",
    font: { size: 12, face: "system-ui" },
    borderWidth: 1.5,
    shadow: { enabled: true, color: "rgba(0,0,0,.08)", size: 6, x: 2, y: 2 }
  },
  edges: {
    arrows: { to: { enabled: true, scaleFactor: 0.7 } },
    smooth: { enabled: true, type: "cubicBezier", forceDirection: "vertical", roundness: 0.4 },
    font: { size: 10, align: "middle" },
    color: { color: "#94a3b8", highlight: "#6366f1" }
  }
};
var network = new vis.Network(container, data, options);

function toggleSection(id) {
  var el = document.getElementById(id);
  el.style.display = el.style.display === "none" ? "" : "none";
}

function filterTable(tableId, query) {
  var tbl = document.getElementById(tableId);
  if (!tbl) return;
  var rows = tbl.getElementsByTagName("tr");
  var q = query.toLowerCase();
  for (var i = 1; i < rows.length; i++) {
    rows[i].style.display = rows[i].textContent.toLowerCase().includes(q) ? "" : "none";
  }
}
</script>
</body>
</html>')
}

# ---- HTML helpers -----------------------------------------------------------

.vis_nodes <- function(nodes) {
  if (nrow(nodes) == 0) return("[]")
  colors <- c(
    input        = "#3b82f6",
    reactive     = "#8b5cf6",
    output       = "#10b981",
    helper_fn    = "#f59e0b",
    state        = "#06b6d4",
    observer     = "#64748b",
    ui           = "#e879f9",
    global       = "#94a3b8",
    missing_file = "#fee2e2",
    unknown      = "#d1d5db"
  )
  border_colors <- c(
    input        = "#1d4ed8",
    reactive     = "#5b21b6",
    output       = "#065f46",
    helper_fn    = "#92400e",
    state        = "#155e75",
    observer     = "#334155",
    ui           = "#a21caf",
    global       = "#64748b",
    missing_file = "#b91c1c",
    unknown      = "#9ca3af"
  )
  rows <- vapply(seq_len(nrow(nodes)), function(i) {
    n   <- nodes[i, ]
    col <- colors[n$node_type]   %||% "#d1d5db"
    bor <- border_colors[n$node_type] %||% "#9ca3af"
    shp <- switch(n$node_type,
      input        = "ellipse",
      output       = "box",
      helper_fn    = "diamond",
      state        = "hexagon",
      missing_file = "box",
      "roundRect"
    )
    dashes <- identical(n$node_type, "missing_file")
    title <- paste0(n$node_type,
                    if (!is.na(n$file_id)) paste0("\\n", n$file_id) else "",
                    if (!is.na(n$line_start)) paste0(" L", n$line_start) else "",
                    "\\nused by: ", n$usage_count,
                    if (dashes) "\\n(file not found on disk)" else "")
    font_str <- if (dashes) ',"font":{"color":"#991b1b","face":"monospace"}' else ""
    dash_str <- if (dashes) ',"shapeProperties":{"borderDashes":[5,5]}' else ""
    paste0('{"id":"', .je(n$node_id), '","label":"', .je(n$label),
           '","color":{"background":"', col, '","border":"', bor,
           '"},"shape":"', shp, '"',
           font_str, dash_str,
           ',"title":"', .je(title), '"}')
  }, "")
  paste0("[", paste(rows, collapse = ","), "]")
}

.vis_edges <- function(edges, nodes) {
  if (nrow(edges) == 0) return("[]")
  rows <- vapply(seq_len(nrow(edges)), function(i) {
    e     <- edges[i, ]
    dash  <- isTRUE(e$is_isolated)
    label <- switch(e$edge_type,
      feeds_into  = "",
      depends_on  = "",
      calls       = "calls",
      reads_state = "reads",
      writes_state = "writes",
      triggers    = "triggers",
      e$edge_type
    )
    dash_str <- if (dash) ',"dashes":true' else ""
    lbl_str  <- if (nchar(label) > 0)
      paste0(',"label":"', .je(label), '"') else ""
    paste0('{"from":"', .je(e$from_node_id), '","to":"', .je(e$to_node_id), '"',
           dash_str, lbl_str, '}')
  }, "")
  paste0("[", paste(rows, collapse = ","), "]")
}

.insight_cards_html <- function(ins) {
  if (nrow(ins) == 0) {
    return('<div class="no-insights">No issues found - looking clean!</div>')
  }
  sev_order <- c("error", "warning", "info")
  parts <- character()
  for (sev in sev_order) {
    rows <- ins[ins$severity == sev, ]
    if (nrow(rows) == 0) next
    for (i in seq_len(nrow(rows))) {
      parts <- c(parts, paste0(
        '<div class="insight-card">',
        '<div class="ic-header">',
        '<span class="ic-badge ', sev, '">', toupper(sev), '</span>',
        '<span class="ic-label"> ', .he(rows$label[i]), '</span>',
        '</div>',
        '<div class="ic-msg">', .he(rows$message[i]), '</div>',
        '</div>'
      ))
    }
  }
  paste(parts, collapse = "\n")
}

.table_rows <- function(df, cols) {
  if (nrow(df) == 0 || length(cols) == 0) return("<tr><td colspan='99' class='muted'>No data</td></tr>")
  cols <- intersect(cols, names(df))
  paste(vapply(seq_len(nrow(df)), function(i) {
    cells <- vapply(cols, function(col) {
      val <- df[[col]][i]
      disp <- if (is.na(val)) '<span class="muted">-</span>'
              else if (col == "node_type") .node_tag(as.character(val))
              else if (col == "parse_success") (if (isTRUE(val)) "\u2713" else "\u2717")
              else .he(as.character(val))
      paste0("<td>", disp, "</td>")
    }, "")
    paste0("<tr>", paste(cells, collapse = ""), "</tr>")
  }, ""), collapse = "\n")
}

.edge_table_rows <- function(edges, node_labels) {
  if (nrow(edges) == 0)
    return("<tr><td colspan='5' class='muted'>No edges</td></tr>")
  paste(vapply(seq_len(nrow(edges)), function(i) {
    e    <- edges[i, ]
    from <- .he(node_labels[e$from_node_id] %||% e$from_node_id)
    to   <- .he(node_labels[e$to_node_id]   %||% e$to_node_id)
    iso  <- if (isTRUE(e$is_isolated)) "\u29b6" else ""
    paste0(
      "<tr>",
      "<td class='mono'>", from, "</td>",
      "<td class='mono'>", to,   "</td>",
      "<td>", .he(e$edge_type), "</td>",
      "<td>", iso, "</td>",
      "<td>", .he(e$confidence), "</td>",
      "</tr>"
    )
  }, ""), collapse = "\n")
}

.node_tag <- function(type) {
  paste0('<span class="tag tag-', type, '">', type, '</span>')
}

# HTML-escape
.he <- function(x) {
  if (is.null(x) || is.na(x)) return("")
  x <- as.character(x)
  x <- gsub("&",  "&amp;",  x, fixed = TRUE)
  x <- gsub("<",  "&lt;",   x, fixed = TRUE)
  x <- gsub(">",  "&gt;",   x, fixed = TRUE)
  x <- gsub('"',  "&quot;", x, fixed = TRUE)
  x
}

# JSON-escape (for inline JS)
.je <- function(x) {
  if (is.null(x) || is.na(x)) return("")
  x <- as.character(x)
  x <- gsub("\\\\", "\\\\\\\\", x)
  x <- gsub('"',  '\\\\"', x, fixed = TRUE)
  x <- gsub("\n", "\\\\n",  x, fixed = TRUE)
  x <- gsub("\r", "",       x, fixed = TRUE)
  x
}

# ---- Console helpers --------------------------------------------------------

.complexity_bar <- function(score, width = 20) {
  filled <- round(score / 100 * width)
  paste0("[", strrep("\u2588", filled), strrep("\u2591", width - filled), "]")
}

.wrap <- function(text, width = 72, indent = "  ") {
  words <- strsplit(text, " ")[[1]]
  lines <- character(); current <- ""
  for (w in words) {
    if (nchar(current) + nchar(w) + 1 > width && nchar(current) > 0) {
      lines <- c(lines, current)
      current <- paste0(indent, w)
    } else {
      current <- if (nchar(current) == 0) w else paste(current, w)
    }
  }
  if (nchar(current) > 0) lines <- c(lines, current)
  paste(lines, collapse = "\n")
}
