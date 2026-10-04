"""Dependency graph view. Layout is computed server-side by the GetGraph walker."""

import from ..main { GraphView, GNode, GetGraph }
import from .util { local_now, pretty }

def:pub GraphPanel -> JsxElement {
    has gv: GraphView | None = None,
        showDone: bool = True,
        loading: bool = True;

    async def load {
        res = root spawn GetGraph(now=local_now(), show_done=showDone);
        gv = res.reports[0] if res.reports else None;
        loading = False;
    }

    async can with entry {
        await load();
    }

    async def toggleDone {
        showDone = not showDone;
        await load();
    }

    if loading {
        return <div class="muted center">Walking the graph…</div>;
    }
    if not gv or len(gv.nodes) == 0 {
        return <div class="empty"><h2>No graph yet</h2><p class="muted">Plan something first.</p></div>;
    }

    W = 190;
    H = 52;
    pos = {n.id: n for n in gv.nodes};

    def node_class(n: GNode) -> str {
        if n.status == "done" {
            return "g-done";
        }
        if n.risk == "late" or n.risk == "at_risk" {
            return "g-risk";
        }
        return "g-" + n.status;
    }

    def clip(t: str) -> str {
        return t if len(t) <= 24 else t[:23] + "…";
    }

    return
        <div class="graph">
            <div class="graph-bar">
                <div class="legend">
                    <span class="lg g-ready">ready</span>
                    <span class="lg g-blocked">blocked</span>
                    <span class="lg g-risk">behind schedule</span>
                    <span class="lg g-done">done</span>
                    <span class="muted">arrows point from prerequisite → what it unblocks</span>
                </div>
                <label class="muted">
                    <input type="checkbox" checked={showDone} onChange={lambda { toggleDone(); }} /> show done
                </label>
            </div>
            <div class="graph-scroll card">
                <svg width={gv.width} height={gv.height}>
                    <defs>
                        <marker id="arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse">
                            <path d="M 0 0 L 10 5 L 0 10 z" className="arrowhead" />
                        </marker>
                    </defs>
                    {[
                        <path
                            key={e.src + e.dst}
                            className="g-edge"
                            markerEnd="url(#arrow)"
                            d={
                                "M " + String(pos[e.dst].x + W) + " " + String(pos[e.dst].y + H / 2)
                                + " C " + String(pos[e.dst].x + W + 40) + " " + String(pos[e.dst].y + H / 2)
                                + ", " + String(pos[e.src].x - 40) + " " + String(pos[e.src].y + H / 2)
                                + ", " + String(pos[e.src].x) + " " + String(pos[e.src].y + H / 2)
                            }
                        /> for e in gv.edges if e.src in pos and e.dst in pos
                    ]}
                    {[
                        <g key={n.id} transform={"translate(" + String(n.x) + "," + String(n.y) + ")"}>
                            <rect width={W} height={H} rx="10" className={"g-node " + node_class(n) + (" g-goal" if n.is_goal else "")} />
                            <text x="12" y="21" className="g-title">{("★ " if n.is_goal else "") + clip(n.title)}</text>
                            <text x="12" y="39" className="g-sub">
                                {("✓ done" if n.status == "done" else (("by " + pretty(n.due)) if n.due else n.status))}
                            </text>
                        </g> for n in gv.nodes
                    ]}
                </svg>
            </div>
        </div>;
}
