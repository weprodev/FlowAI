# FlowAI Architecture Blueprint

FlowAI is built on **Domain-Driven Design (DDD)** and the Unix philosophy. It aggressively isolates the orchestration engine (the driver) from the vendor tools (the implementers).

## The Orchestration Loop

Currently, FlowAI operates inside a `tmux` session. 

```mermaid
flowchart TD
    subgraph FlowAITerminal["Tmux Session (FlowAI Orchestrator)"]
        direction TB
        Master["Master Agent<br/>(Coordinator)"]
        
        subgraph Phases["Phase Injection (Isolated Context)"]
            direction LR
            Plan["1. Plan"] --> Impl["2. Implement"] --> Verify["3. Review"]
        end

        Master -->|"Delegates Work"| Phases
        
        subgraph Guardrails["Security Guardrails"]
            Gum["Terminal UI (Gum)"]
            Editor["Manual file review ($EDITOR)"]
        end
        
        Phases -->|"Proposes Changes"| Guardrails
        Guardrails -->|"Human Approval"| Files[(Local Filesystem)]
    end
```

1. **The Master Agent**: Governs the core terminal window, deciding which phase to execute next.
2. **Phase Injection**: Standard Bash files (like `plan.sh` and `implement.sh`) receive isolated prompts and execute strictly constrained loops.
3. **Guardrails**: No AI agent is permitted to hijack the editor or UI natively. Output is verified strictly through `$EDITOR` via explicit terminal approval mechanisms (`gum pager`).

---

## Evolution Roadmap

FlowAI is designed toward enterprise-grade scaling. The following modules form the core of our mid-term architectural evolution:

```mermaid
flowchart LR
    subgraph FlowAI_v2["FlowAI Scalable Orchestrator"]
        direction TB
        Master2["Master Agent"]
        
        subgraph parallelDAG["Parallel Distributed Execution"]
            direction LR
            Pane1["Tmux Pane 1<br/>(Backend)"]
            Pane2["Tmux Pane 2<br/>(Frontend)"]
        end
        
        Master2 -->|"Spins up jobs"| parallelDAG
    end

    subgraph ExpansionLayers["Native Integrations"]
        MCP["MCP Servers<br/>(Real-time Context)"]
        VCS["GitHub / GitLab<br/>(CI Log Interception)"]
    end
    
    MCP -.->|"Supplies Intelligence"| Master2
    VCS -.->|"Supplies Error Logs"| parallelDAG
```

### 1. Model Context Protocol (MCP) Integration
Instead of injecting monolithic text prompts dynamically through Bash processing, FlowAI will intercept native [Model Context Protocol (MCP)](https://github.com/microsoft/model-context-protocol) services.
- **Goal**: Allow the Planning phase to query an MCP endpoint for localized architectural context (e.g., retrieving exact TypeScript AST structures natively before proposing edits).
- **Wiring**: Future `flowai.json` configurations will define `mcp_servers` that `run.sh` bounds to the session context cleanly.

### 2. Version Control System (VCS) Integrations
The orchestrator must break beyond local filesystems and map seamlessly to automated continuous deployments.
- **Goal**: Full integration with **GitHub PRs** and **GitLab MRs**.
- **Wiring**: The Spec Kit (`.specify/`) currently scaffolds features. FlowAI will expand internal phases (`flowai run review`) to pull isolated CI logs from GitHub Actions directly into the Terminal for the AI implementation layer to automatically revise broken commits.

### 3. Distributed Parallel DAG Phases
Currently, FlowAI operates in a strict procedural loop (Plan -> Implement -> Verify).
- **Goal**: Break large features into decoupled dependency graphs.
- **Wiring**: Future orchestrator versions will support spinning up localized `tmux` windows operating concurrently on distinct features, merging their Git states safely before the final Review phase.
