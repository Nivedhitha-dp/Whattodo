"""'What should I do now?' -- graph ranking + AI pick, plus completion unlock toasts."""

import from ..main { Item, NowView, ListItems, WhatNow, CompleteItem, ReopenItem, LoadDemo }
import from .ItemCard { ItemCard }
import from .util { local_now }

def:pub NowPanel(onChange: Callable[[], None]) -> JsxElement {
    has view: NowView | None = None,
        loading: bool = True,
        thinking: bool = False,
        minutes: str = "",
        situation: str = "",
        toast: str = "";

    async def refresh {
        res = root spawn ListItems(now=local_now());
        view = res.reports[0] if res.reports else None;
        loading = False;
    }

    async can with entry {
        await refresh();
    }

    async def ask {
        thinking = True;
        mins = int(minutes) if minutes else 0;
        res = root spawn WhatNow(now=local_now(), minutes=mins, situation=situation);
        view = res.reports[0] if res.reports else view;
        thinking = False;
    }

    async def complete(id: str) {
        res = root spawn CompleteItem(item_id=id, now=local_now());
        if res.reports {
            c = res.reports[0];
            parts: list[str] = [];
            if c.completed {
                parts.append("✓ " + c.completed.title);
            }
            if len(c.unlocked) > 0 {
                parts.append("🔓 unlocked: " + ", ".join([u.title for u in c.unlocked]));
            }
            if c.next_instance {
                parts.append("↻ next one scheduled");
            }
            toast = "   ".join(parts);
        }
        await refresh();
    }

    async def reopen(id: str) {
        root spawn ReopenItem(item_id=id);
        await refresh();
    }

    async def demo {
        root spawn LoadDemo(now=local_now());
        await refresh();
        onChange();
    }

    if loading {
        return <div class="muted center">Analyzing your graph…</div>;
    }

    items: list[Item] = view.items if view else [];
    by_id = {jid(i): i for i in items};
    picks = view.ai_picks if view else [];
    pick_ids = [p.id for p in picks];
    why = {p.id: p.why for p in picks};
    queue = [by_id[q] for q in (view.queue if view else []) if q in by_id and q not in pick_ids];
    blocked = [i for i in items if i.status == "blocked"];
    at_risk = [i for i in items if i.risk in ["late", "at_risk"] and not i.done];

    if len(items) == 0 {
        return
            <div class="empty">
                <h2>Your life graph is empty</h2>
                <p class="muted">Use the 🧠 Plan tab to tell LifeFlow what you need to get done, or load a sample week.</p>
                <button class="btn primary" onClick={lambda { demo(); }}>Load demo week</button>
            </div>;
    }

    return
        <div class="now">
            {(<div class="toast" onClick={lambda { toast = ""; }}>{toast}</div>) if toast else None}
            <section class="ask card">
                <div class="ask-row">
                    <span>I have</span>
                    <input
                        class="input small"
                        value={minutes}
                        placeholder="30"
                        onChange={lambda (e: ChangeEvent) { minutes = e.target.value; }}
                    />
                    <span>minutes,</span>
                    <input
                        class="input grow"
                        value={situation}
                        placeholder="situation (e.g. at home, low energy, heading to campus)"
                        onChange={lambda (e: ChangeEvent) { situation = e.target.value; }}
                        onKeyPress={lambda (e: KeyboardEvent) { if e.key == "Enter" { ask(); } }}
                    />
                    <button class="btn primary" disabled={thinking} onClick={lambda { ask(); }}>
                        {("Thinking…" if thinking else "What should I do?")}
                    </button>
                </div>
                {(<div class="headline">{view.headline}</div>) if view and view.headline else None}
                {(<div class="muted small-text">{view.ai_error}</div>) if view and view.ai_error else None}
            </section>

            {(
                <div class="banner danger">
                    ⚠ {len(at_risk)} item(s) are behind schedule: {", ".join([i.title for i in at_risk])}
                </div>
            ) if len(at_risk) > 0 else None}

            {(
                <section>
                    <h3>✨ Do this now</h3>
                    {[
                        <ItemCard
                            key={p}
                            item={by_id[p]}
                            highlight={why[p]}
                            onDone={lambda { complete(p); }}
                            onReopen={lambda { reopen(p); }}
                        /> for p in pick_ids if p in by_id
                    ]}
                </section>
            ) if len(pick_ids) > 0 else None}

            <section>
                <h3>{("Then" if len(pick_ids) > 0 else "Ready to start")} <span class="muted">· ranked by deadline pressure and what it unlocks</span></h3>
                {[
                    <ItemCard
                        key={jid(i)}
                        item={i}
                        highlight=""
                        onDone={lambda { complete(jid(i)); }}
                        onReopen={lambda { reopen(jid(i)); }}
                    /> for i in queue
                ]}
                {(<div class="muted">Nothing else is unblocked.</div>) if len(queue) == 0 else None}
            </section>

            {(
                <section>
                    <h3>⛓ Blocked <span class="muted">· waiting on prerequisites</span></h3>
                    {[
                        <ItemCard
                            key={jid(i)}
                            item={i}
                            highlight=""
                            onDone={lambda { complete(jid(i)); }}
                            onReopen={lambda { reopen(jid(i)); }}
                        /> for i in blocked
                    ]}
                </section>
            ) if len(blocked) > 0 else None}
        </div>;
}
