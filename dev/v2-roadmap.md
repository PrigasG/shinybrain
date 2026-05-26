# shinybrain v2 roadmap

## Vision

`shinybrain v2` turns the package from a graph extractor into a practical
architecture review tool for real Shiny applications. The goal is not just to
show dependencies, but to help a developer answer:

- what depends on what
- what is risky or hard to maintain
- where the app is concentrated
- what to fix first

## Product shape

V2 should produce outputs that are useful for both people and tools:

- a cleaner architecture report
- prioritized findings instead of a flat list of notes
- actionable recommendations for the highest-signal issues
- stable JSON and Markdown exports for agents and downstream tooling

## Non-goals for v2

These are worth doing later, but they are not required for the first V2 cut:

- runtime profiling
- browser/session tracing
- automatic refactors
- IDE integration

## Workstreams

### 1. Analysis depth

- improve support for module patterns
- improve handling for dynamic UI and lower-confidence code paths
- tighten unsupported-pattern reporting so confidence is explicit

### 2. Architecture insights

- prioritize findings by severity and impact
- detect hotspots such as overused reactives and complex outputs
- identify dead reactives and side-effect-heavy contexts
- suggest likely refactors instead of only describing the problem

### 3. Report UX

- surface top findings first in console, HTML, Markdown, and JSON
- keep the full graph available, but make the report readable on large apps
- expose confidence and recommendation text consistently

### 4. Real-app validation

- grow the test fixtures beyond toy apps
- add acceptance tests around realistic multi-file apps
- track false positives so the insights layer stays trustworthy

## Delivery plan

### Phase 1: prioritized insights

Goal:
turn the existing insights layer into a ranked architecture review surface.

Deliverables:

- score and recommendation fields on findings
- top-findings summary in the App Brain
- console and Markdown output that surfaces the highest-priority issues first

Status:
completed

### Phase 2: hotspot diagnostics

Goal:
identify the parts of the reactive graph that are most likely to become
maintenance bottlenecks.

Deliverables:

- reactive hotspot detection
- complex output detection refinement
- stronger side-effect guidance

Status:
in progress

### Phase 3: module-aware analysis

Goal:
understand real Shiny modular structure well enough to connect definitions,
instances, and cross-file ownership.

Deliverables:

- module detection strategy
- partial support for `moduleServer()` and `callModule()`
- issue reporting when module linkage is incomplete

Status:
started

### Phase 4: report polish and scale

Goal:
make the report useful on larger apps without forcing the reader to inspect
raw tables first.

Deliverables:

- improved HTML report hierarchy
- stronger summaries for large apps
- fixture apps that exercise the new report behavior

Status:
planned

## Immediate execution queue

1. Land prioritized findings in the insights layer.
2. Add hotspot detection for highly reused reactives/state.
3. Expose top findings in the App Brain and Markdown export.
4. Add focused tests for the new insight behavior.

## Acceptance criteria for the first V2 slice

The first slice is successful when:

- a high-risk app no longer produces an undifferentiated list of findings
- findings include a recommendation, not just a warning
- the App Brain exposes the top issues in a stable machine-readable shape
- the new behavior is covered by targeted tests
