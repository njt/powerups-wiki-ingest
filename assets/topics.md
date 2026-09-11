# Topics

Every source is filed under one or two of these. The slug goes in the
`topics:` list in the summary's frontmatter; the title is the compiled page
under `topic/`; the scope line tells the ingest what belongs. Edit this
table freely. After a change, run `wiki-retag` for anything that moved and
`wiki-recompile` to rebuild the affected pages. The tools read only the
table; everything else on this page is for people.

`misc` must exist. It is where a source goes when nothing else fits, and
`wiki-curate topics` lists its contents so a topic that wants to exist can
be noticed.

| slug | title | scope |
|---|---|---|
| agent-coding-workflow | Agent Coding Workflow | How practitioners actually work with coding agents day to day: the loop, prompting habits, planning and review rituals, verification over generation, maturity models, and what changes about the craft. |
| agent-architecture | Agent Architecture | How a single agent is built: harness design, tool and capability models, control loops, state, error handling, and the internals of specific agents and frameworks. |
| agent-orchestration | Agent Orchestration | Many agents working together: multi-agent topologies, delegation, subagents, queues and schedulers, coordination protocols, and the control planes that run fleets of agents. |
| agent-memory-and-context | Agent Memory and Context | What an agent remembers and what it sees: context engineering, memory architectures, retrieval, summarisation, compaction, and the limits of long context. |
| guardrails-and-feedback-loops | Guardrails and Feedback Loops | Keeping agents honest: linters and deterministic checks over instructions, evaluation and testing of agent output, review gates, observability, and the loops that make quality self-correcting. |
| specifications-as-the-product | Specifications as the Product | Specs, plans and requirements as the durable artifact: spec-driven development, planning before coding, design documents, and the economics of disposable code. |
| security-and-sandboxing | Security and Sandboxing | Threats and containment for agents and the software they touch: sandboxing, permissions, prompt injection, supply chain, secrets, zero trust, and incident write-ups. |
| software-engineering-craft | Software Engineering Craft | Engineering practice that predates and outlasts agents: simplicity, architecture, code review, testing, refactoring, debugging, technical writing, and how teams ship. |
| databases-and-data | Databases and Data | Storage engines, query systems, data modelling, file formats, data pipelines, and how data systems are designed and operated. |
| distributed-systems | Distributed Systems | Consensus, replication, failure modes, networking, event-driven versus polling designs, and the operational realities of systems spread over many machines. |
| developer-tools | Developer Tools | Tools a developer picks up and uses: editors, terminals, CLIs, build systems, version control, and standalone utilities. A tool is filed here when the interesting thing is the tool itself rather than the idea behind it. |
| local-and-open-source-inference | Local and Open Source Inference | Running models yourself: open-weight models, local inference engines, quantisation, hardware for inference at home or on the edge, and how open models track the frontier. |
| ai-research-and-models | AI Research and Models | Papers, model releases and evaluations: architectures, training, reasoning, benchmarks, and what the frontier labs and researchers are finding. |
| ai-infrastructure-and-hardware | AI Infrastructure and Hardware | The physical and platform layer: chips, data centres, energy, serving infrastructure, cloud platforms, and the economics of compute. |
| personal-agents | Personal Agents | Agents that work for one person: assistants, personal automation, home and life management, messaging integrations, and the local-first tools people build for themselves. |
| ai-product-and-business | AI Product and Business | Pricing, unit economics, adoption inside organisations, strategy, competition, labour and market effects, and how AI products get built and sold. |
| ideas-and-culture | Ideas and Culture | Essays and arguments about how we think and work: philosophy, history, creativity, organisations, learning, and the culture around technology. |
| misc | Miscellany | Anything that fits none of the above. Reviewed periodically for topics that want to exist. |
