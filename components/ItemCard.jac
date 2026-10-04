"""One item row: status, deadline pressure, what it unlocks / waits on."""

import from ..main { Item }
import from .util { pretty, slack_text, kind_icon }

def:pub ItemCard(
    item: Item,
    highlight: str,
    onDone: Callable[[], None],
    onReopen: Callable[[], None]
) -> JsxElement {
    risk_label = {
        "late": "overdue", "at_risk": "behind schedule", "soon": "due soon", "ok": "on track"
    };
    return
        <div class={"card item " + item.status + " risk-" + (item.risk or "none")}>
            <button
                class={"check " + ("checked" if item.done else "")}
                title={("Mark not done" if item.done else "Mark done")}
                disabled={item.status == "blocked"}
                onClick={lambda { onReopen() if item.done else onDone(); }}
            >
                {("✓" if item.done else "")}
            </button>
            <div class="item-body">
                <div class="item-title">
                    <span class="kind">{kind_icon(item.kind)}</span>
                    {item.title}
                    {(<span class="pill goal">goal</span>) if item.is_goal else None}
                    {(<span class="pill repeat">↻ {item.repeat}</span>) if item.repeat != "none" else None}
                    {(<span class="pill loc">📍 {item.location}</span>) if item.location else None}
                </div>
                <div class="item-meta">
                    <span>{item.effort_min} min</span>
                    {(<span>· start by {pretty(item.start_by)}</span>) if item.start_by and not item.done else None}
                    {(<span>· due {pretty(item.due)}</span>) if item.due else None}
                    {(
                        <span class={"pill risk " + item.risk}>
                            {risk_label[item.risk]} · {slack_text(item.slack_min)}
                        </span>
                    ) if item.risk and not item.done else None}
                </div>
                {(
                    <div class="item-meta waits">⛓ waiting on: {", ".join(item.blocked_by)}</div>
                ) if item.status == "blocked" else None}
                {(
                    <div class="item-meta unlocks">🔓 unlocks {item.unlocks} more</div>
                ) if item.unlocks > 0 and not item.done else None}
                {(<div class="why">✨ {highlight}</div>) if highlight else None}
            </div>
        </div>;
}
