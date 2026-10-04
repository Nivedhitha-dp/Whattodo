"""AI planning interview: sentence -> proposed dependency chain -> follow-up -> save."""

import from ..main { PlanView, PlanStep, DraftPlan, CommitPlan }
import from .util {
    local_now, pretty, kind_icon, speech_supported, listen, speak, stop_voice
}

def:pub PlanPanel(onSaved: Callable[[], None]) -> JsxElement {
    has request: str = "",
        answer: str = "",
        answers: list[str] = [],
        plan: PlanView | None = None,
        busy: bool = False,
        error: str = "",
        listening: str = "",        # "" | "request" | "answer"
        speaking: bool = False,
        voiceMode: bool = False,    # hands-free: read questions aloud, then listen
        canVoice: bool = False;

    can with entry {
        canVoice = speech_supported();
    }

    # Everything is passed explicitly (text, prior answers) because voice callbacks
    # fire later, when component state captured in a closure may be stale.
    async def draft(text: str, prior: list[str], voice: bool) {
        if not text.strip() {
            return;
        }
        busy = True;
        error = "";
        fresh: PlanView | None = None;   # local copy: `plan` state won't update until re-render
        try {
            res = root spawn DraftPlan(text=text.strip(), now=local_now(), answers=prior);
            p = res.reports[0] if res.reports else None;
            if p and p.error {
                error = p.error;
            } elif p {
                plan = p;
                fresh = p;
            } else {
                error = "The planner returned nothing. Please try again.";
            }
        } except Exception as e {
            error = "The server took too long or failed to respond. Please try again.";
        }
        busy = False;
        if voice and fresh {
            converse(fresh, text, prior);
        }
    }

    async def start(text: str, voice: bool) {
        request = text;
        answers = [];
        plan = None;
        await draft(text, [], voice);
    }

    async def submit_answer(text: str, prior: list[str], question: str, ans: str, voice: bool) {
        if not ans.strip() {
            return;
        }
        nxt = prior + [question + " -> " + ans.strip()];
        answers = nxt;
        answer = "";
        await draft(text, nxt, voice);
    }

    """Hands-free loop: read the plan + follow-up aloud, then listen for the answer."""
    def converse(p: PlanView, text: str, prior: list[str]) {
        steps = len(p.steps);
        intro = p.summary + " That's " + String(steps) + (" step." if steps == 1 else " steps.");
        speaking = True;
        if p.question {
            speak(intro + " " + p.question, lambda {
                speaking = False;
                hear("answer", lambda (heard: str) {
                    submit_answer(text, prior, p.question, heard, True);
                });
            });
        } else {
            speak(intro + " Tap save to add it to your graph.", lambda { speaking = False; });
        }
    }

    def hear(target: str, on_final: any) {
        stop_voice();
        speaking = False;
        error = "";
        listening = target;
        listen(
            lambda (t: str) {
                if target == "request" {
                    request = t;
                } else {
                    answer = t;
                }
            },
            lambda (t: str, err: str) {
                listening = "";
                if err == "not-allowed" or err == "service-not-allowed" {
                    error = "Microphone access was blocked. Allow the mic in your browser's address bar.";
                } elif t.strip() {
                    on_final.call(None, t);
                } elif err and err != "aborted" {
                    error = "Didn't catch that (" + err + "). Tap the mic and try again.";
                }
            }
        );
    }

    def stop_all {
        stop_voice();
        listening = "";
        speaking = False;
        voiceMode = False;
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
        try {
            root spawn CommitPlan(plan_json=JSON.stringify(plan), now=local_now());
        } except Exception as e {
            busy = False;
            error = "Saving failed. Please try again.";
            return;
        }
        busy = False;
        stop_all();
        plan = None;
        request = "";
        answers = [];
        onSaved();
    }

    titles = {s.key: s.title for s in plan.steps} if plan else {};
    q = plan.question if plan else "";
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
                        placeholder={("Type, or tap 🎤 and just say it…" if canVoice else "e.g. I have an assignment due Friday")}
                        onChange={lambda (e: ChangeEvent) { request = e.target.value; }}
                        onKeyPress={lambda (e: KeyboardEvent) { if e.key == "Enter" { start(request, False); } }}
                    />
                    {(
                        <button
                            class={"btn mic " + ("on" if listening == "request" else "")}
                            title="Speak your task (hands-free planning)"
                            disabled={busy}
                            onClick={lambda {
                                if listening {
                                    stop_all();
                                } else {
                                    voiceMode = True;
                                    hear("request", lambda (t: str) { start(t, True); });
                                }
                            }}
                        >
                            {("■" if listening == "request" else "🎤")}
                        </button>
                    ) if canVoice else None}
                    <button class="btn primary" disabled={busy} onClick={lambda { start(request, False); }}>
                        {("Thinking…" if busy else "Plan it")}
                    </button>
                </div>
                {(
                    <div class="voice-bar">
                        <span class="pulse"></span>
                        {("Listening… speak now" if listening else "Speaking…")}
                        <button class="btn tiny ghost" onClick={lambda { stop_all(); }}>Stop voice</button>
                    </div>
                ) if listening or speaking else None}
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
                                    onKeyPress={lambda (e: KeyboardEvent) {
                                        if e.key == "Enter" { submit_answer(request, answers, q, answer, voiceMode); }
                                    }}
                                />
                                {(
                                    <button
                                        class={"btn mic " + ("on" if listening == "answer" else "")}
                                        title="Answer by voice"
                                        disabled={busy}
                                        onClick={lambda {
                                            if listening {
                                                stop_all();
                                            } else {
                                                hear("answer", lambda (t: str) {
                                                    submit_answer(request, answers, q, t, voiceMode);
                                                });
                                            }
                                        }}
                                    >
                                        {("■" if listening == "answer" else "🎤")}
                                    </button>
                                ) if canVoice else None}
                                <button
                                    class="btn"
                                    disabled={busy}
                                    onClick={lambda { submit_answer(request, answers, q, answer, voiceMode); }}
                                >
                                    Refine
                                </button>
                            </div>
                        </div>
                    ) if plan.question else None}
                    <div class="actions">
                        <button class="btn primary" disabled={busy or len(plan.steps) == 0} onClick={lambda { save(); }}>
                            Save {len(plan.steps)} item(s) to my graph
                        </button>
                        <button class="btn ghost" onClick={lambda { stop_all(); plan = None; answers = []; }}>Discard</button>
                    </div>
                </section>
            ) if plan else None}
        </div>;
}
