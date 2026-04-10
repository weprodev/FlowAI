# FlowAI Knowledge Graph

The knowledge graph is FlowAI's compiled understanding of your project. It solves the
fundamental cold-start problem in multi-agent AI workflows: every agent session normally
begins with no memory of past sessions, forcing agents to re-read raw files to understand
context — wasting tokens, time, and increasing hallucination risk.

Instead of re-deriving knowledge on every run, FlowAI builds and maintains a **persistent
knowledge graph** that agents read as their primary navigation layer.

> [!IMPORTANT]
> The graph is a first-class capability, not an optional add-on.
> `flowai start` enforces that a graph exists and prompts you to build one.

---

## What the Graph Contains

```
.flowai/wiki/
├── GRAPH_REPORT.md  ← Start here: god nodes, communities, suggested queries
├── graph.json       ← Full graph: nodes, edges, provenance, metadata
├── index.md         ← Content catalog: every wiki page with a one-line summary
├── log.md           ← Append-only log of all graph operations
└── cache/           ← SHA256 per-file hashes for incremental builds
```

### `GRAPH_REPORT.md`

The architectural map every agent reads before touching any file. Contains:

- **God nodes** — the highest-degree hubs in the codebase (everything converges here)
- **Community summaries** — clusters of closely-related modules
- **Architectural insights** — key design decisions extracted from source and docs
- **Suggested queries** — pre-generated questions about the architecture
- **Ambiguous relationships** — flagged for human review

### `graph.json`

The full graph in JSON. Each edge has a **provenance tag**:

| Tag | Meaning |
|---|---|
| `EXTRACTED` | Directly present in source (imports, function calls, links). High confidence. |
| `INFERRED` | Reasonable inference from context. Comes with a confidence score (0.0–1.0). Treat as hypothesis. |
| `AMBIGUOUS` | Uncertain. Flagged for review. Do not assume correct. |

---

## How the Graph is Built

FlowAI's graph engine runs a **dual-pass extraction**:

### Pass 1: Structural (no LLM, pure bash)

Extracts the objective, deterministic structure from your code:
- Source file inventory from configured `scan_paths` (`src/`, `docs/`, `specs/` by default)
- Function definitions and call relationships
- Module imports and dependencies
- Markdown cross-references and links
- JSON configuration key mapping

All results are tagged `EXTRACTED` (high confidence). No inference involved.

**Result:** `.flowai/wiki/cache/structural.json`

### Pass 2: Semantic (LLM, optional)

**Off by default.** Set `"semantic_enabled": true` under `graph` in `.flowai/config.json`
to run the LLM on changed files (adds API cost and latency).

The LLM reads each changed file and extracts:
- Key concepts and their relationships to other concepts
- Design rationale from comments and documentation
- Architectural decisions and their consequences
- Patterns and anti-patterns

Results are tagged `EXTRACTED`, `INFERRED`, or `AMBIGUOUS` with confidence scores.

**Result:** `.flowai/wiki/cache/semantic/<file-hash>.json`

### Merge + Community Detection

Both passes are merged into `graph.json`. Nodes are deduplicated by ID.
Community detection runs a degree-based clustering algorithm (no external dependencies):
- **God** — ≥10 edges (architectural load-bearers)
- **Hub** — 5–9 edges (well-connected modules)
- **Leaf** — <5 edges (peripheral files)

---

## Commands

```bash
# Build or rebuild the full graph
flowai graph build

# Force rebuild (ignores cache — reprocesses all files)
flowai graph build --force

# Incremental update (only changed files)
flowai graph update

# Mine git log → IMPLEMENTS edges + spec evolution[] (compiled project history)
flowai graph chronicle

# Ingest a document into the wiki
flowai graph ingest docs/ARCHITECTURE.md

# Query the wiki (answer is filed back as a wiki page)
flowai graph query "How does the skill resolution chain work?"

# Health-check: orphans, contradictions, stale claims
flowai graph lint

# Show graph health in the terminal
flowai graph status

# Read GRAPH_REPORT.md in the terminal pager
flowai graph report
```

---

## Chronicle & spec evolution (Karpathy-style compiled history)

Raw git history is expensive for agents to re-read every session. After `flowai graph chronicle`,
the graph stores a **persistent, incremental summary**:

- **`evolution[]` on spec nodes** — commits whose messages reference a spec ID (same ID must appear in the spec’s `feature_ids`, including YAML `id:` merged at build time).
- **`IMPLEMENTS` edges** — code files touched in those commits, linked to the spec node.

This matches the spirit of a **maintained wiki**: compile once, query many times. It is
language- and layout-agnostic; monorepos can widen `graph.scan_paths` to include each package root.

---

## How Agents Use the Graph

Every FlowAI agent (master, plan, tasks, impl, review) automatically receives the graph
context in its system prompt when a graph exists. The injected block looks like:

```
--- [FLOWAI KNOWLEDGE GRAPH] ---
A compiled knowledge graph of this codebase is available...
  Graph:  .flowai/wiki/graph.json — 234 nodes · 891 edges · 3 communities · built 2h ago
  Start:  .flowai/wiki/GRAPH_REPORT.md
  Index:  .flowai/wiki/index.md
Navigation protocol:
  1. Read GRAPH_REPORT.md before searching any files
  2. Use index.md to find the exact wiki page for any concept
  ...
---
```

This is platform-level behavior — every agent gets it regardless of which skills are assigned.

The `graph-aware-navigation` skill (bundled, assigned to all roles by default) teaches agents
the full navigation protocol: `GRAPH_REPORT.md → index.md → wiki pages → graph.json → source files`.

---

## Sharing the Graph with Your Team

By default, `.flowai/wiki/` is local to your machine (gitignored via `.flowai/`).

**To share the graph with your team** — so everyone benefits from a pre-built graph:

1. Remove `.flowai/wiki/` from your `.gitignore` (or the line that ignores `.flowai/`)
2. Commit `.flowai/wiki/` to your repository
3. Add a CI step: `flowai graph update` (runs the structural pass + any changed files)

All team members and CI agents will then read the same compiled graph, making cold-starts
a solved problem across the team.

---

## Performance Characteristics

- **Incremental builds:** Only files with changed SHA256 hashes are reprocessed
- **Token efficiency:** Agents navigate compiled artifacts instead of raw files
- **No external dependencies:** The structural pass (Pass 1) requires only bash + jq
- **Graceful degradation:** If the graph is missing, agents fall back to raw file reads
  (but `flowai start` will prompt you to build it)

---

## Configuration

The `graph` section in `.flowai/config.json`:

```json
{
  "graph": {
    "enabled": true,
    "scan_paths": ["src", "docs", "specs"],
    "ignore_patterns": ["*.generated.*", "*.min.js", "*.min.css"],
    "max_age_hours": 24,
    "auto_build": false
  }
}
```

| Key | Default | Description |
|---|---|---|
| `enabled` | `true` | Whether the graph system is active |
| `scan_paths` | `["src","docs","specs"]` | Project-relative directories to scan |
| `ignore_patterns` | `[]` | Glob patterns to exclude from scanning |
| `max_age_hours` | `24` | Age threshold before graph is considered stale |
| `auto_build` | `false` | Reserved for future CI integration |

---

## Spec-Driven Development Integration

FlowAI uses Spec-Driven Development (SDD): specs are the **authoritative source of intent**
before any code is written. The graph engine treats spec files differently from source files:

### Spec nodes vs source nodes

| Property | Source file node | Spec node |
|---|---|---|
| Node type | `file` | `spec` |
| Trust level | standard | `HIGH` |
| Edge type | `sources`, `defines`, `references` | `SPECIFIES` |
| Extra metadata | — | `feature_ids`, `criteria` |
| In `GRAPH_REPORT.md` | God Nodes section | Spec Coverage section |

### What qualifies as a spec file

FlowAI detects spec files by path and naming convention:
- **By path**: `specs/`, `.specify/`, `spec/`
- **By name**: `*.spec.md`, `requirements*.md`, `acceptance*.md`, `adr*.md`, `rfc*.md`,
  `user-story*.md`, `prd*.md`, `feature*.md`

### What gets extracted from specs

- **Feature IDs**: patterns like `UC-XXX-NNN`, `FEAT-NNN`, `STORY-NNN`, `REQ-NNN`, `RFC-NNN`
- **Acceptance criteria**: headings starting with Acceptance, Given, When, Then, Must, Should, Shall
- **SPECIFIES edges**: every project-relative link from a spec to a source file or wiki page
  creates a `SPECIFIES` edge, making spec-to-code traceability machine-readable

### Spec coverage in GRAPH_REPORT.md

The **Spec Coverage** section in `GRAPH_REPORT.md` shows:
- How many spec documents exist
- How many `SPECIFIES` edges were found (spec → code traceability)
- Which specs have zero implementation edges (possible unimplemented features)

Run `flowai graph lint` to detect specs with no corresponding implementation and
code that has no spec coverage.

### SDD navigation protocol

```
Specs (.specify/, specs/)  ─ SPECIFIES edges ─►  Implementation (src/)
                      ↑
          flowai graph lint detects divergence
```

**Before touching any source file, agents read the relevant spec node first.** This ensures
implementation faithfully reflects intent and reduces hallucinated behavior.

---

## Inspiration

The persistent wiki pattern is inspired by [Andrej Karpathy's llm-wiki concept](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f) —
the idea of compiling knowledge into a persistent wiki maintained by the LLM rather than
re-deriving context from scratch every session.

FlowAI's implementation is purpose-built for multi-agent agentic pipelines and
Spec-Driven Development workflows. All code is original — graph extraction, community
detection, wiki operations, and CLI integration are written from scratch in bash + jq,
designed to work without Python, external graph databases, or network dependencies.
