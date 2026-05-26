# Changelog

## shinybrain 0.2.0

- Added prioritized architecture findings with scores, recommendations,
  and top-finding summaries in the App Brain.
- Added reactive hotspot detection, stronger side-effect guidance, and
  explicit analysis-confidence scoring.
- Added partial module-aware analysis by tagging module-shaped helper
  functions, annotating nested module contexts, and reporting incomplete
  module wiring.
- Added runtime-generated UI confidence notes for `renderUI()` contexts.
- Added V2 example apps covering hotspots, dead reactives, side effects,
  and a larger legacy multi-file workflow.

## shinybrain 0.1.0

- Initial public release of `shinybrain`.
- Added static analysis for single-file and multi-file Shiny projects.
- Added source-chain resolution, missing-source detection, and
  ghost-node support.
- Added graph construction for inputs, reactives, outputs, observers,
  helpers, and state.
- Added JSON, Markdown, and HTML App Brain exports.
- Added example apps, vignettes, pkgdown configuration, and CRAN
  submission materials.
