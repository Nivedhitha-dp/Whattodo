"""LifeFlow -- a dependency-aware life manager that answers "what should I do next?".

Everything the user has to accomplish lives in their personal graph:

    root --> Item("Submit HW2") -[DependsOn]-> Item("Write report") -[DependsOn]-> Item("Run experiment")

Walkers move over that graph to propagate deadlines backwards along dependency
edges, discover what is unblocked, find what a completion unlocks, and lay the
graph out for the UI. byLLM turns plain English into typed plan graphs.
"""

import os;
import re;
import from datetime { datetime, timedelta }
import from jaclang.byllm.lib { Model, ModelPool }
import from frontend { app as ClientApp }

"""Every configured model, in fallback order. Gemini 503s ("model overloaded") are
common, so several Gemini models are chained, then Claude if that key exists.
LIFEFLOW_GEMINI_MODEL / LIFEFLOW_CLAUDE_MODEL put a preferred model first."""
def pick_llm -> any {
    names: list[str] = [];
    if os.getenv("GEMINI_API_KEY") or os.getenv("GOOGLE_API_KEY") {
        preferred = os.getenv("LIFEFLOW_GEMINI_MODEL", "");
        if preferred {
            names.append(preferred);
        }
        names.extend(
            ["gemini/gemini-2.5-flash", "gemini/gemini-2.5-flash-lite", "gemini/gemini-2.0-flash"]
        );
    }
    if os.getenv("ANTHROPIC_API_KEY") {
        names.append(os.getenv("LIFEFLOW_CLAUDE_MODEL", "anthropic/claude-sonnet-4-6"));
    }
    unique: list[str] = [];
    for n in names {
        if n not in unique {
            unique.append(n);
        }
    }
    if len(unique) == 0 {
        return Model(model_name="gemini/gemini-2.5-flash");  # calls fail gracefully until a key is set
    }
    return ModelPool(
        models=[Model(model_name=n) for n in unique],
        strategy="fallback",
        num_retries=0,      # don't hammer an overloaded model; move to the next one
        timeout=25.0
    );
}

glob llm = pick_llm();

def:pub app -> JsxElement {
    return
        <ClientApp />;
}

# ---------------------------------------------------------------------------
# Graph schema
# ---------------------------------------------------------------------------

"""Anything the user has to get done: an assignment, a bill, an errand, a chore."""
node Item {
    has title: str,
        kind: str = "other",
        notes: str = "",
        due: str = "",              # hard deadline, local "YYYY-MM-DDTHH:MM" (or "")
        effort_min: int = 30,
        repeat: str = "none",       # none | daily | weekly | monthly
        location: str = "",
        is_goal: bool = False,
        done: bool = False,
        done_at: str = "",
        created_at: str = "",
        # --- derived by the Analyze walker on every read ---
        eff_deadline: str = "",     # earliest deadline inherited through dependents
        start_by: str = "",         # eff_deadline - effort
        slack_min: int = 0,         # minutes between now and start_by
        status: str = "ready",      # ready | blocked | done
        risk: str = "",             # late | at_risk | soon | ok | "" (no deadline)
        blocked_by: list[str] = [],
        unlocks: int = 0;           # how many open items are (transitively) waiting on this
}

"""(a) -[DependsOn]-> (b): `a` cannot start until `b` is done."""
edge DependsOn: Item --> Item {
    has reason: str = "";
}

# ---------------------------------------------------------------------------
# Time helpers (all times are the user's local wall-clock time)
# ---------------------------------------------------------------------------

def to_dt(s: str) -> datetime | None {
    if not s {
        return None;
    }
    try {
        return datetime.fromisoformat(s[:16]);
    } except Exception {
        return None;
    }
}

def fmt(d: datetime) -> str {
    return d.strftime("%Y-%m-%dT%H:%M");
}

def now_or(s: str) -> datetime {
    d = to_dt(s);
    return d if d else datetime.now();
}

def next_occurrence(due: str, repeat: str, now: str) -> str {
    base = to_dt(due) or now_or(now);
    if repeat == "daily" {
        return fmt(base + timedelta(days=1));
    }
    if repeat == "weekly" {
        return fmt(base + timedelta(days=7));
    }
    if repeat == "monthly" {
        month = base.month % 12 + 1;
        year = base.year + (1 if base.month == 12 else 0);
        day = min(base.day, 28);
        return fmt(base.replace(year=year, month=month, day=day));
    }
    return "";
}

# ---------------------------------------------------------------------------
# Graph helpers
# ---------------------------------------------------------------------------

def deps_of(it: Item) -> list[Item] {
    return [it ->:DependsOn:->][?:Item];
}

def dependents_of(it: Item) -> list[Item] {
    return [it <-:DependsOn:<-][?:Item];
}

"""True if `dst` is reachable from `src` by following DependsOn edges."""
def reaches(src: Item, dst: Item) -> bool {
    stack: list[Item] = [src];
    seen: set[str] = set();
    while stack {
        cur = stack.pop();
        if cur == dst {
            return True;
        }
        if jid(cur) in seen {
            continue;
        }
        seen.add(jid(cur));
        stack.extend(deps_of(cur));
    }
    return False;
}

"""Link a -> b (a depends on b) unless it would create a cycle."""
def link(a: Item, b: Item, reason: str = "") -> bool {
    if a == b or reaches(b, a) or b in deps_of(a) {
        return False;
    }
    a +>: DependsOn(reason=reason) :+> b;
    return True;
}

def open_dependents_count(it: Item) -> int {
    stack: list[Item] = dependents_of(it);
    seen: set[str] = set();
    while stack {
        cur = stack.pop();
        if jid(cur) in seen or cur.done {
            continue;
        }
        seen.add(jid(cur));
        stack.extend(dependents_of(cur));
    }
    return len(seen);
}

def find_item(owner: any, id: str) -> Item | None {
    for it in [owner-->][?:Item] {
        if jid(it) == id {
            return it;
        }
    }
    return None;
}

"""Ready items first by urgency (least slack), then by how much they unlock, then quickest."""
def rank_ready(items: list[Item]) -> list[Item] {
    ready = [i for i in items if i.status == "ready"];
    return sorted(
        ready,
        key=lambda (i: Item) -> tuple {
            return (0 if i.start_by else 1, i.slack_min if i.start_by else 0, -i.unlocks, i.effort_min);
        }
    );
}

def sort_for_list(items: list[Item]) -> list[Item] {
    order = {"ready": 0, "blocked": 1, "done": 2};
    return sorted(
        items,
        key=lambda (i: Item) -> tuple {
            return (order.get(i.status, 3), 0 if i.start_by else 1, i.start_by, i.title);
        }
    );
}

# ---------------------------------------------------------------------------
# The core walker: deadline propagation + readiness analysis
# ---------------------------------------------------------------------------

"""Recomputes every derived field on the user's graph.

Deadlines flow *backwards* along DependsOn edges: if "Submit HW2" is due Friday
23:59 and takes 15 minutes, then "Write report" effectively must be done by
Friday 23:44, and so on down the chain. Each Item pulls the tightest deadline
from its dependents; when its own value tightens it re-visits its prerequisites
so the change keeps flowing until the graph settles.
"""
walker Analyze {
    has now: str = "";

    can start with Root entry {
        for it in [here-->][?:Item] {
            it.eff_deadline = "" if it.done else it.due;
        }
        visit [-->][?:Item];
    }

    can propagate with Item entry {
        if not here.done {
            best = to_dt(here.due);
            for d in dependents_of(here) {
                dl = to_dt(d.eff_deadline);
                if dl and not d.done {
                    cand = dl - timedelta(minutes=d.effort_min);
                    if best is None or cand < best {
                        best = cand;
                    }
                }
            }
            new_val = fmt(best) if best else "";
            if new_val != here.eff_deadline {
                here.eff_deadline = new_val;
                visit [->:DependsOn:->][?:Item];
            }
        }
    }

    can summarize with Root exit {
        now = now_or(self.now);
        for it in [here-->][?:Item] {
            if it.done {
                it.status = "done";
                it.risk = "";
                it.start_by = "";
                it.slack_min = 0;
                it.blocked_by = [];
                it.unlocks = 0;
                continue;
            }
            open_deps = [d for d in deps_of(it) if not d.done];
            it.status = "blocked" if open_deps else "ready";
            it.blocked_by = [d.title for d in open_deps];
            it.unlocks = open_dependents_count(it);
            dl = to_dt(it.eff_deadline);
            if dl {
                sb = dl - timedelta(minutes=it.effort_min);
                it.start_by = fmt(sb);
                it.slack_min = int((sb - now).total_seconds() / 60);
                if dl < now {
                    it.risk = "late";
                } elif it.slack_min < 0 {
                    it.risk = "at_risk";
                } elif it.slack_min < 24 * 60 {
                    it.risk = "soon";
                } else {
                    it.risk = "ok";
                }
            } else {
                it.start_by = "";
                it.slack_min = 0;
                it.risk = "";
            }
        }
    }
}

# ---------------------------------------------------------------------------
# AI layer (byLLM): types are the prompt, enums are the guard rails
# ---------------------------------------------------------------------------

enum Kind { ASSIGNMENT, BILL, ERRAND, CHORE, APPOINTMENT, WORK, HEALTH, SOCIAL, SHOPPING, OTHER }

enum Repeat { NONE, DAILY, WEEKLY, MONTHLY }

obj StepDraft {
    has key: str,
        title: str,
        kind: Kind,
        due: str,
        effort_min: int,
        repeat: Repeat,
        location: str,
        depends_on: list[str],
        reason: str;
}

sem StepDraft = "One concrete, actionable step in the user's plan.";
sem StepDraft.key = "Short id unique within this plan, like 's1', 's2'.";
sem StepDraft.title = "Short imperative title, e.g. 'Download dataset'.";
sem StepDraft.due = "Hard deadline as local time 'YYYY-MM-DDTHH:MM' resolved against `now`; empty string when the step has no deadline of its own (its deadline is inherited from what depends on it).";
sem StepDraft.effort_min = "Realistic minutes of focused effort for this step alone.";
sem StepDraft.repeat = "How often this recurs once completed (rent is MONTHLY, laundry is usually WEEKLY); NONE for one-off steps.";
sem StepDraft.location = "Physical place it must happen ('UPS Store', 'home', 'campus', 'bank'), or empty if anywhere/online.";
sem StepDraft.depends_on = "Keys of steps in this plan, or ids of the user's existing open items, that must be finished BEFORE this step can start.";
sem StepDraft.reason = "Very short why this step is needed.";

obj PlanDraft {
    has goal_key: str,
        steps: list[StepDraft],
        question: str,
        summary: str;
}

sem PlanDraft.goal_key = "Key of the final step: the thing the user actually asked about.";
sem PlanDraft.steps = "The goal plus every prerequisite needed to finish it, ordered so prerequisites come first. Include only real, distinct steps (usually 1-6).";
sem PlanDraft.question = "ONE short follow-up question about a prerequisite or detail the user did not mention that would change the plan (e.g. 'Do you need to download a dataset first?'). Empty string if the plan is already clear or the answers already cover it.";
sem PlanDraft.summary = "One friendly sentence describing the plan.";

def draft_plan(
    request: str, now: str, answers: list[str], existing_open_items: list[str]
) -> PlanDraft by llm();

sem draft_plan = "Turn something the user needs to accomplish into a dependency plan. Think about what really has to happen first (prerequisites) and resolve relative dates like 'Friday' or 'the 1st' against now. Reuse an existing open item (refer to it by its id in depends_on) instead of duplicating it.";
sem draft_plan.request = "What the user said they need to do.";
sem draft_plan.now = "Current local date-time, 'YYYY-MM-DDTHH:MM' (weekday included after a space).";
sem draft_plan.answers = "The user's answers to earlier follow-up questions, in order. Use them to refine the plan.";
sem draft_plan.existing_open_items = "The user's existing open items formatted as 'id :: title'.";

obj Candidate {
    has id: str,
        title: str,
        kind: str,
        effort_min: int,
        start_by: str,
        slack_min: int,
        unlocks: int,
        location: str;
}

obj Pick {
    has id: str,
        why: str;
}

obj Advice {
    has headline: str,
        picks: list[Pick];
}

sem Advice.headline = "One short, encouraging sentence telling the user what to focus on right now.";
sem Advice.picks = "1-3 candidates to do now, best first. Only use ids from the candidates list.";
sem Pick.why = "One short sentence: why this one now (deadline pressure, unblocks other work, fits the time, same place as another errand...).";

def advise(
    now: str, minutes_available: int, situation: str, candidates: list[Candidate]
) -> Advice by llm();

sem advise = "Act as a sharp personal chief of staff. From the ready-to-start candidates, choose what the user should do right now given their available time and situation. Respect deadlines (low or negative slack_min is urgent), prefer tasks that unlock many others, prefer tasks that fit the available minutes, and batch errands at the same location.";
sem advise.minutes_available = "Minutes the user has right now; 0 means not specified.";
sem advise.situation = "Free-text context from the user, e.g. 'at home, low energy' or 'heading to campus'.";
sem Candidate.slack_min = "Minutes until this must be started to stay on schedule. Negative means already behind.";
sem Candidate.unlocks = "How many other open tasks are waiting on this one.";

"""Short, user-facing description of an LLM failure."""
def ai_error_text(e: Exception) -> str {
    msg = str(e);
    if "Missing" in msg and ("API key" in msg or "api_key" in msg) {
        return "No AI key configured on the server. Set GEMINI_API_KEY or ANTHROPIC_API_KEY and restart.";
    }
    if "API_KEY_INVALID" in msg or "API key not valid" in msg or "AuthenticationError" in msg or "invalid x-api-key" in msg {
        return "The AI provider rejected the API key. Check the key's value (no quotes/spaces) and redeploy.";
    }
    if "No deployments available" in msg or "cooldown" in msg {
        return "All AI models are briefly cooling down after errors. Try again in a few seconds.";
    }
    if "503" in msg or "overloaded" in msg or "UNAVAILABLE" in msg {
        return "The AI provider is overloaded right now (503). Try again in a moment.";
    }
    if "429" in msg or "RESOURCE_EXHAUSTED" in msg or "quota" in msg {
        return "AI rate limit / quota reached (429). Wait a minute or check your API plan.";
    }
    flat = " ".join(msg.split());
    found = re.search(r'"message":\s*"([^"]+)"', flat);
    detail = found.group(1) if found else flat;
    return f"The AI model failed ({type(e).__name__}): {detail[:220]}";
}

def enum_name(v: any) -> str {
    return str(v).split(".")[-1].lower();
}

# ---------------------------------------------------------------------------
# Wire types: what crosses to the browser (plain strings, no enums)
# ---------------------------------------------------------------------------

obj PlanStep {
    has key: str,
        title: str,
        kind: str = "other",
        due: str = "",
        effort_min: int = 30,
        repeat: str = "none",
        location: str = "",
        depends_on: list[str] = [],
        reason: str = "";
}

obj PlanView {
    has goal_key: str = "",
        steps: list[PlanStep] = [],
        question: str = "",
        summary: str = "",
        error: str = "";
}

obj NowView {
    has items: list[Item] = [],      # analyzed graph, sorted for display
    queue: list[str] = [],           # ids of ready items, best first (deterministic)
    headline: str = "",
    ai_picks: list[Pick] = [],
    ai_error: str = "";
}

obj CompletionView {
    has completed: Item | None = None,
        unlocked: list[Item] = [],
        next_instance: Item | None = None;
}

obj GNode {
    has id: str,
        title: str,
        status: str,
        risk: str,
        is_goal: bool,
        due: str,
        x: int,
        y: int;
}

obj GEdge {
    has src: str,
        dst: str;
}

obj GraphView {
    has nodes: list[GNode] = [],
        edges: list[GEdge] = [],
        width: int = 0,
        height: int = 0;
}

def weekday_now(now: str) -> str {
    d = now_or(now);
    return f"{fmt(d)} {d.strftime('%A')}";
}

# ---------------------------------------------------------------------------
# Public (authenticated) walkers -- each runs on the caller's own root
# ---------------------------------------------------------------------------

"""Return the whole analyzed graph plus a ranked 'do next' queue (no AI)."""
walker:protect ListItems {
    has now: str = "",
        reports: list[NowView] = [];

    can collect with Root entry {
        here spawn Analyze(now=self.now);
        items = [here-->][?:Item];
        report NowView(
            items=sort_for_list(items), queue=[jid(i) for i in rank_ready(items)]
        );
    }
}

"""What should I do right now? Graph analysis ranks; the LLM picks and explains."""
walker:protect WhatNow {
    has now: str = "",
        minutes: int = 0,
        situation: str = "",
        reports: list[NowView] = [];

    can decide with Root entry {
        here spawn Analyze(now=self.now);
        items = [here-->][?:Item];
        ranked = rank_ready(items);
        view = NowView(items=sort_for_list(items), queue=[jid(i) for i in ranked]);
        pool = [i for i in ranked if self.minutes <= 0 or i.effort_min <= self.minutes] or ranked;
        if pool {
            cands = [
                Candidate(
                    id=jid(i), title=i.title, kind=i.kind, effort_min=i.effort_min,
                    start_by=i.start_by, slack_min=i.slack_min, unlocks=i.unlocks,
                    location=i.location
                ) for i in pool[:12]
            ];
            valid = {c.id for c in cands};
            try {
                adv = advise(weekday_now(self.now), self.minutes, self.situation, cands);
                view.headline = adv.headline;
                view.ai_picks = [p for p in adv.picks if p.id in valid];
            } except Exception as e {
                view.ai_error = ai_error_text(e) + " Showing graph ranking.";
                top = pool[0];
                why = (
                    f"it unblocks {top.unlocks} other task(s)" if top.unlocks > 0
                    else ("it's the most time-critical" if top.start_by else "it's quick and ready")
                );
                view.headline = f"Start with “{top.title}” ({top.effort_min} min): {why}.";
            }
        } else {
            view.headline = "Nothing is ready right now. Add something or enjoy the free time!";
        }
        report view;
    }
}

"""Ask the LLM to turn a sentence into a dependency plan (not saved yet)."""
walker:protect DraftPlan {
    has text: str,
        now: str = "",
        answers: list[str] = [],
        reports: list[PlanView] = [];

    can draft with Root entry {
        existing = [f"{jid(i)} :: {i.title}" for i in [here-->][?:Item] if not i.done];
        try {
            d = draft_plan(self.text, weekday_now(self.now), self.answers, existing);
            steps = [
                PlanStep(
                    key=s.key, title=s.title, kind=enum_name(s.kind), due=s.due or "",
                    effort_min=max(5, s.effort_min), repeat=enum_name(s.repeat),
                    location=s.location or "", depends_on=s.depends_on, reason=s.reason
                ) for s in d.steps
            ];
            report PlanView(
                goal_key=d.goal_key, steps=steps, question=d.question, summary=d.summary
            );
        } except Exception as e {
            report PlanView(error=ai_error_text(e));
        }
    }
}

"""Persist a (possibly user-edited) plan as nodes + DependsOn edges."""
walker:protect CommitPlan {
    has plan: PlanView,
        now: str = "",
        reports: list[list[Item]] = [];

    can commit with Root entry {
        by_key: dict[str, Item] = {};
        for s in self.plan.steps {
            by_key[s.key] = here ++> Item(
                title=s.title, kind=s.kind, due=s.due, effort_min=s.effort_min,
                repeat=s.repeat, location=s.location, notes=s.reason,
                is_goal=(s.key == self.plan.goal_key), created_at=self.now
            );
        }
        for s in self.plan.steps {
            for k in s.depends_on {
                target = by_key.get(k) or find_item(here, k);
                if target {
                    link(by_key[s.key], target, s.reason);
                }
            }
        }
        report list(by_key.values());
    }
}

"""Quick add without AI."""
walker:protect AddItem {
    has title: str,
        due: str = "",
        effort_min: int = 30,
        repeat: str = "none",
        kind: str = "other",
        location: str = "",
        depends_on: list[str] = [],
        now: str = "",
        reports: list[Item] = [];

    can add with Root entry {
        it = here ++> Item(
            title=self.title, due=self.due, effort_min=self.effort_min,
            repeat=self.repeat, kind=self.kind, location=self.location,
            created_at=self.now
        );
        for d in self.depends_on {
            target = find_item(here, d);
            if target {
                link(it, target);
            }
        }
        report it;
    }
}

"""Complete an item, then walk *backwards* up DependsOn edges to see what it unlocked."""
walker:protect CompleteItem {
    has item_id: str,
        now: str = "",
        target_done: bool = False,
        result: CompletionView = CompletionView(),
        reports: list[CompletionView] = [];

    can find with Root entry {
        visit [i for i in [-->][?:Item] if jid(i) == self.item_id];
    }

    can on_item with Item entry {
        if not self.target_done {
            # First stop: the item being completed.
            self.target_done = True;
            here.done = True;
            here.done_at = self.now;
            self.result.completed = here;
            if here.repeat != "none" {
                nxt = root ++> Item(
                    title=here.title, kind=here.kind, notes=here.notes,
                    due=next_occurrence(here.due, here.repeat, self.now),
                    effort_min=here.effort_min, repeat=here.repeat,
                    location=here.location, created_at=self.now
                );
                self.result.next_instance = nxt;
            }
            visit [<-:DependsOn:<-][?:Item];
        } elif not here.done and all([d.done for d in deps_of(here)]) {
            # A dependent whose last blocker just disappeared.
            self.result.unlocked.append(here);
        }
    }

    can finish with Root exit {
        report self.result;
    }
}

walker:protect ReopenItem {
    has item_id: str;

    can reopen with Root entry {
        it = find_item(here, self.item_id);
        if it {
            it.done = False;
            it.done_at = "";
        }
        report {"ok": it is not None};
    }
}

walker:protect UpdateItem {
    has item_id: str,
        title: str,
        due: str,
        effort_min: int,
        repeat: str,
        location: str,
        reports: list[Item] = [];

    can update with Root entry {
        it = find_item(here, self.item_id);
        if it {
            it.title = self.title;
            it.due = self.due;
            it.effort_min = max(1, self.effort_min);
            it.repeat = self.repeat;
            it.location = self.location;
            report it;
        }
    }
}

walker:protect DeleteItem {
    has item_id: str;

    can remove with Root entry {
        it = find_item(here, self.item_id);
        if it {
            del it;
        }
        report {"deleted": self.item_id};
    }
}

"""Make `item_id` depend on `needs_id` (refuses cycles)."""
walker:protect AddDependency {
    has item_id: str,
        needs_id: str;

    can add with Root entry {
        a = find_item(here, self.item_id);
        b = find_item(here, self.needs_id);
        ok = bool(a and b and link(a, b));
        report {"ok": ok, "error": "" if ok else "That link would create a cycle or already exists."};
    }
}

walker:protect RemoveDependency {
    has item_id: str,
        needs_id: str;

    can remove with Root entry {
        a = find_item(here, self.item_id);
        b = find_item(here, self.needs_id);
        if a and b {
            del [edge a ->:DependsOn:-> b];
        }
        report {"ok": True};
    }
}

"""Lay the dependency graph out in columns: prerequisites left, goals right."""
walker:protect GetGraph {
    has now: str = "",
        show_done: bool = True,
        reports: list[GraphView] = [];

    can layout with Root entry {
        here spawn Analyze(now=self.now);
        items = [i for i in [here-->][?:Item] if self.show_done or not i.done];
        ids = {jid(i) for i in items};
        # depth = longest chain of prerequisites beneath an item
        depth: dict[str, int] = {};
        def depth_of(it: Item, guard: int) -> int {
            k = jid(it);
            if k in depth {
                return depth[k];
            }
            ds = [d for d in deps_of(it) if jid(d) in ids];
            v = 0 if not ds or guard > 50 else 1 + max([depth_of(d, guard + 1) for d in ds]);
            depth[k] = v;
            return v;
        }
        # connected components so separate goals get separate bands
        comp: dict[str, int] = {};
        comps: list[list[Item]] = [];
        for it in items {
            if jid(it) in comp {
                continue;
            }
            group: list[Item] = [];
            stack = [it];
            while stack {
                cur = stack.pop();
                if jid(cur) in comp or jid(cur) not in ids {
                    continue;
                }
                comp[jid(cur)] = len(comps);
                group.append(cur);
                stack.extend(deps_of(cur) + dependents_of(cur));
            }
            comps.append(group);
        }
        comps = sorted(comps, key=lambda (g: list[Item]) -> int { return -len(g); });
        col_w = 230;
        row_h = 74;
        nodes: list[GNode] = [];
        top = 0;
        max_x = 0;
        for group in comps {
            cols: dict[int, list[Item]] = {};
            for it in group {
                cols.setdefault(depth_of(it, 0), []).append(it);
            }
            band = max([len(v) for v in cols.values()]);
            for (c, members) in cols.items() {
                for (r, it) in enumerate(sorted(members, key=lambda (m: Item) -> str { return m.title; })) {
                    x = 20 + c * col_w;
                    y = top + 20 + r * row_h + int((band - len(members)) * row_h / 2);
                    max_x = max(max_x, x);
                    nodes.append(
                        GNode(
                            id=jid(it), title=it.title, status=it.status, risk=it.risk,
                            is_goal=it.is_goal, due=it.eff_deadline, x=x, y=y
                        )
                    );
                }
            }
            top = top + band * row_h + 30;
        }
        edges = [
            GEdge(src=jid(i), dst=jid(d))
            for i in items
            for d in deps_of(i)
            if jid(d) in ids
        ];
        report GraphView(nodes=nodes, edges=edges, width=max_x + 220, height=top + 10);
    }
}

"""Seed a realistic student life graph so the demo works without typing."""
walker:protect LoadDemo {
    has now: str = "";

    can seed with Root entry {
        n = now_or(self.now);
        def at(days: int, hour: int, minute: int = 0) -> str {
            return fmt((n + timedelta(days=days)).replace(hour=hour, minute=minute));
        }
        hw2 = here ++> Item(title="Submit HW2", kind="assignment", due=at(3, 23, 59), effort_min=15, is_goal=True, location="online");
        report_ = here ++> Item(title="Write HW2 report", kind="assignment", effort_min=150);
        exp = here ++> Item(title="Run experiment", kind="assignment", effort_min=120);
        data = here ++> Item(title="Download dataset", kind="assignment", effort_min=20);
        link(hw2, report_, "report is the submission");
        link(report_, exp, "report needs results");
        link(exp, data, "experiment needs data");

        ret = here ++> Item(title="Return Amazon order", kind="errand", due=at(2, 18), effort_min=20, is_goal=True, location="UPS Store");
        label = here ++> Item(title="Print return label", kind="errand", effort_min=10, location="library");
        pack = here ++> Item(title="Pack the box", kind="chore", effort_min=10, location="home");
        link(ret, pack, "box must be packed");
        link(pack, label, "label goes on the box");

        here ++> Item(title="Pay rent", kind="bill", due=at(5, 9), effort_min=5, repeat="monthly", is_goal=True);
        here ++> Item(title="Laundry", kind="chore", due=at(1, 21), effort_min=60, repeat="weekly", location="home");
        here ++> Item(title="Buy groceries", kind="shopping", due=at(1, 19), effort_min=40, location="Kroger");
        report {"ok": True};
    }
}

walker:protect ClearAll {
    can clear with Root entry {
        for it in [here-->][?:Item] {
            del it;
        }
        report {"ok": True};
    }
}
