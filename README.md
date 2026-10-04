# ◆ LifeFlow — what should I do next?

Most to-do apps ask *"what reminders do I have?"*
LifeFlow asks *"what do I need to accomplish, what depends on what, and what should I do **right now**?"*

Tell it "HW2 is due Friday". It asks whether anything has to happen first, then builds the real plan:

```
Download dataset ──▶ Run experiment ──▶ Write report ──▶ ★ Submit HW2 (Fri 11:59 PM)
```

From then on it knows the real work is downloading the dataset today, not submitting on Friday.

Built end-to-end in **[Jac](https://jaclang.org)** — one language for the graph data model, the API, the AI
calls and the React UI — and deployed on **[JacHammer](https://jachammer.ai)**.

---

## Features

| | |
|---|---|
| 🧠 **AI planning interview** | A sentence becomes a typed dependency plan (`by llm()` → `PlanDraft`). The AI asks one follow-up question ("Do you need to download a dataset first?"), you answer, it refines. It reuses your existing items instead of duplicating them. |
| ⚡ **What now?** | "I have 30 min, at home": graph analysis ranks every *unblocked* task by deadline pressure and how much it unlocks. The LLM then picks 1–3 and explains why. If no AI is available, you still get the graph ranking. |
| ⏱ **Deadline propagation** | Deadlines flow *backwards* through dependencies. If HW2 is due Fri 23:59 and the report takes 2.5h, the experiment has to be done earlier still. Each task gets a computed **start-by** time and slack, and is flagged *behind schedule* before it's actually late. |
| 🔓 **Unlock cascade** | Completing a task walks back up the dependency edges and tells you what just became available: *"✓ Run experiment 🔓 unlocked: Write HW2 report"*. |
| ↻ **Recurring items** | Rent (monthly) and laundry (weekly) schedule their next instance when you complete them. |
| 🕸 **Live dependency graph** | Column layout (prerequisites → goals), colored ready / blocked / behind / done. |
| 🔒 **Per-user graphs** | Built-in auth; every user gets an isolated `root`. |

---

## Why Jac fits this problem

A life plan **is a graph**. In a typical stack you'd fake it with SQL join tables, recursive CTEs and an ORM.
In Jac the graph *is* the data model and the persistence layer:

```jac
node Item { has title: str, due: str = "", effort_min: int = 30, done: bool = False, ... }
edge DependsOn: Item --> Item { has reason: str = ""; }

hw2 +>: DependsOn(reason="report is the submission") :+> report;
```

| Jac concept | Where LifeFlow uses it |
|---|---|
| `node` | `Item` — persisted automatically by being reachable from the user's `root`. No database code. |
| `edge` (typed) | `DependsOn` — traversed with `[it ->:DependsOn:->]` (prerequisites) and `[it <-:DependsOn:<-]` (dependents). |
| `walker` | All business logic. `Analyze`, `WhatNow`, `CompleteItem`, `DraftPlan`, `CommitPlan`, `GetGraph`, … |
| `visit` / `here` / `report` | `Analyze` re-visits prerequisites whenever a node's deadline tightens, so changes ripple through the graph until it settles. |
| entry / exit abilities | `Analyze` propagates on `Item entry` and computes status/slack/risk on `Root exit`, after the traversal finishes. |
| `by llm()` + `obj` + `sem` + `enum` | `draft_plan(...) -> PlanDraft` and `advise(...) -> Advice`. The types are the prompt and the output schema; `Kind`/`Repeat` enums keep the model on known values. |
| `ModelPool` | Uses Gemini or Claude, whichever key is set, with automatic fallback. |
| `walker:protect` | Every endpoint needs login and runs on that user's own `root`. |
| jac-client | React UI written in Jac. Walkers are spawned from the browser with `root spawn WhatNow(...)`; no fetch code, no REST layer. |

### The interesting walker: deadline propagation

```jac
walker Analyze {
    can start with Root entry {            # reset, then fan out to every item
        for it in [here-->][?:Item] { it.eff_deadline = "" if it.done else it.due; }
        visit [-->][?:Item];
    }
    can propagate with Item entry {        # pull the tightest deadline from dependents
        best = to_dt(here.due);
        for d in dependents_of(here) {     # [here <-:DependsOn:<-]
            cand = to_dt(d.eff_deadline) - timedelta(minutes=d.effort_min);
            best = min(best, cand);
        }
        if changed { here.eff_deadline = fmt(best); visit [->:DependsOn:->]; }  # ripple down
    }
    can summarize with Root exit { ... status / slack / risk / unlock counts ... }
}
```

Cycles are rejected when an edge is created (`link()` checks reachability first), so propagation always terminates.

---

## Project layout

```
main.jac                 server: schema, walkers, AI functions (+ client entry)
frontend.jac             client: auth gate + tabs
components/
  NowPanel.jac           "What should I do?" + unlock toasts
  PlanPanel.jac          AI planning interview
  GraphPanel.jac         SVG dependency graph (layout computed by GetGraph walker)
  ItemsPanel.jac         quick add / edit / link prerequisites
  ItemCard.jac, AuthForm.jac, util.jac
styles.css               light + dark theme
jac.toml                 project config
```

## Run locally

```bash
# with the jac binary (Linux/macOS/WSL)
export GEMINI_API_KEY=...        # and/or ANTHROPIC_API_KEY=...
jac install
jac run                          # http://localhost:8000   (/docs = API, /graph = raw graph)
```

On Windows without WSL, use Docker:

```bash
docker run --rm -it --user root -p 8000:8000 -e GEMINI_API_KEY=... \
  -v "$PWD:/app" -v lifeflow_jac:/app/.jac -w /app --entrypoint bash jaseci/jaclang \
  -c "jac install && jac run --host 0.0.0.0 --port 8000"
```

No API key? Click **Load demo week**. Ranking, deadline propagation, unlocks and the graph all work without AI.

## Deploy on JacHammer

1. Push this repo to GitHub.
2. On [jachammer.ai](https://jachammer.ai) choose **Deploy existing code** and paste the repo URL.
3. Add `GEMINI_API_KEY` (or `ANTHROPIC_API_KEY`) as a secret / environment variable.
4. JacHammer provides HTTPS, persistence (MongoDB/Redis) and auto-deploy on push.

## Ideas next

- Calendar-aware scheduling: place start-by blocks into free slots
- Errand batching: route same-location errands into one trip
- Notifications when an item turns "behind schedule"
- Agentic MCP tools so the planner can check a course site or an order status itself
