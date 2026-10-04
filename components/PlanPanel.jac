"""AI planning interview: sentence -> proposed dependency chain -> follow-up -> save."""

import from ..main { PlanView, PlanStep, DraftPlan, CommitPlan }
import from .util { local_now, pretty, kind_icon }

def:pub PlanPanel(onSaved: Callable[[], None]) -> JsxElement {
    has request: str = "",
        answer: str = "",
        answers: list[str] = [],
        plan: PlanView | None = None,
        busy: bool = False,
        error: str = "";

    async def draft {
        if not request.strip() {
            return;
        }
        busy = True;
        error = "";
        res = root spawn DraftPlan(text=request.strip(), now=local_now(), answers=answers);
        p = res.reports[0] if res.reports else None;
        if p and p.error {
            error = p.error;
        } else {
            plan = p;
        }
        busy = False;
    }

    async def start {
        answers = [];
        plan = None;
        await draft();
    }

    async def reply {
        if plan is None or not answer.strip() {
            return;
        }
        answers = answers + [plan.question + " -> " + answer.strip()];
        answer = "";
        await draft();
    }

    def drop(key: str) {
        if plan is None {
            return;
        }
        steps = [s for s in plan.steps if s.key != key];
        for s in steps {
            s.depends_on = [d for d in s.depends_on if d != key];
        }
        plan = PlanView(
            goal_key=plan.goal_key, steps=steps, question=plan.question, summary=plan.summary
        );
    }

    async def save {
        if plan is None {
            return;
        }
        busy = True;
        root spawn CommitPlan(plan=plan, now=local_now());
        busy = False;
        plan = None;
        request = "";
        answers = [];
        onSaved();
    }

    titles = {s.key: s.title for s in plan.steps} if plan else {};
    examples = [
        "HW2 is due Friday night",
        "Return my Amazon order before Wednesday",
        "Rent is due on the 1st every month",
        "Apply to the Jaseci AI engineer role by Sunday"
    ];

    return
        <div class="plan">
            <section class="card">
                <h3>What do you need to get done?</h3>
                <div class="ask-row">
                    <input
                        class="input grow"
                        value={request}
                        placeholder="e.g. I have an assignment due Friday"
                        onChange={lambda (e: ChangeEvent) { request = e.target.value; }}
                        onKeyPress={lambda (e: KeyboardEvent) { if e.key == "Enter" { start(); } }}
                    />
                    <button class="btn primary" disabled={busy} onClick={lambda { start(); }}>
                        {("Thinking…" if busy else "Plan it")}
                    </button>
                </div>
                <div class="chips">
                    {[
                        <button key={ex} class="chip" onClick={lambda { request = ex; }}>{ex}</button>
                        for ex in examples
                    ]}
                </div>
                {(<div class="error">{error}</div>) if error else None}
            </section>

            {(
                <section class="card">
                    <div class="summary">🧠 {plan.summary}</div>
                    {(
                        <div class="answers">
                            {[<div key={a} class="answer-chip">💬 {a}</div> for a in answers]}
                        </div>
                    ) if len(answers) > 0 else None}
                    <ol class="chain">
                        {[
                            <li key={s.key} class={"step " + ("goal" if s.key == plan.goal_key else "")}>
                                <div class="step-head">
                                    <span>{kind_icon(s.kind)} <b>{s.title}</b></span>
                                    <button class="btn tiny ghost" title="Remove step" onClick={lambda { drop(s.key); }}>✕</button>
                                </div>
                                <div class="item-meta">
                                    <span>{s.effort_min} min</span>
                                    {(<span>· due {pretty(s.due)}</span>) if s.due else None}
                                    {(<span>· ↻ {s.repeat}</span>) if s.repeat != "none" else None}
                                    {(<span>· 📍 {s.location}</span>) if s.location else None}
                                </div>
                                {(
                                    <div class="item-meta waits">
                                        ⛓ after: {", ".join([titles[d] if d in titles else "existing item" for d in s.depends_on])}
                                    </div>
                                ) if len(s.depends_on) > 0 else None}
                                {(<div class="item-meta muted">{s.reason}</div>) if s.reason else None}
                            </li> for s in plan.steps
                        ]}
                    </ol>
                    {(
                        <div class="followup">
                            <div class="q">🤔 {plan.question}</div>
                            <div class="ask-row">
                                <input
                                    class="input grow"
                                    value={answer}
                                    placeholder="Answer to refine the plan…"
                                    onChange={lambda (e: ChangeEvent) { answer = e.target.value; }}
                                    onKeyPress={lambda (e: KeyboardEvent) { if e.key == "Enter" { reply(); } }}
                                />
                                <button class="btn" disabled={busy} onClick={lambda { reply(); }}>Refine</button>
                            </div>
                        </div>
                    ) if plan.question else None}
                    <div class="actions">
                        <button class="btn primary" disabled={busy or len(plan.steps) == 0} onClick={lambda { save(); }}>
                            Save {len(plan.steps)} item(s) to my graph
                        </button>
                        <button class="btn ghost" onClick={lambda { plan = None; answers = []; }}>Discard</button>
                    </div>
                </section>
            ) if plan else None}
        </div>;
}
