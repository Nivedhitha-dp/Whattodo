"""Manual control: quick add, edit, link prerequisites, delete."""

import from ..main {
    Item, NowView, ListItems, AddItem, UpdateItem, DeleteItem,
    AddDependency, CompleteItem, ReopenItem, ClearAll
}
import from .ItemCard { ItemCard }
import from .util { local_now }

def:pub ItemsPanel(onChange: Callable[[], None]) -> JsxElement {
    has items: list[Item] = [],
        title: str = "",
        due: str = "",
        effort: str = "30",
        repeat: str = "none",
        editing: str = "",
        e_title: str = "",
        e_due: str = "",
        e_effort: str = "",
        e_repeat: str = "none",
        e_loc: str = "",
        link_to: str = "",
        msg: str = "";

    async def refresh {
        res = root spawn ListItems(now=local_now());
        items = res.reports[0].items if res.reports else [];
    }

    async can with entry {
        await refresh();
    }

    async def add {
        if not title.strip() {
            return;
        }
        root spawn AddItem(
            title=title.strip(), due=due, effort_min=int(effort or "30"),
            repeat=repeat, now=local_now()
        );
        title = "";
        due = "";
        await refresh();
    }

    def startEdit(i: Item) {
        editing = jid(i);
        e_title = i.title;
        e_due = i.due;
        e_effort = String(i.effort_min);
        e_repeat = i.repeat;
        e_loc = i.location;
        link_to = "";
        msg = "";
    }

    async def saveEdit {
        root spawn UpdateItem(
            item_id=editing, title=e_title, due=e_due, effort_min=int(e_effort or "30"),
            repeat=e_repeat, location=e_loc
        );
        editing = "";
        await refresh();
    }

    async def addLink {
        if not link_to {
            return;
        }
        res = root spawn AddDependency(item_id=editing, needs_id=link_to);
        r = res.reports[0] if res.reports else {"ok": False, "error": "failed"};
        msg = "" if r["ok"] else str(r["error"]);
        link_to = "";
        await refresh();
    }

    async def remove(id: str) {
        root spawn DeleteItem(item_id=id);
        editing = "";
        await refresh();
    }

    async def complete(id: str) {
        root spawn CompleteItem(item_id=id, now=local_now());
        await refresh();
    }

    async def reopen(id: str) {
        root spawn ReopenItem(item_id=id);
        await refresh();
    }

    async def wipe {
        if window.confirm("Delete every item in your graph?") {
            root spawn ClearAll();
            await refresh();
            onChange();
        }
    }

    by_title = {jid(i): i.title for i in items};
    current = [i for i in items if jid(i) == editing];
    cur = current[0] if len(current) > 0 else None;

    return
        <div class="items">
            <section class="card">
                <h3>Quick add <span class="muted">· no AI needed</span></h3>
                <div class="ask-row wrap">
                    <input class="input grow" value={title} placeholder="Title"
                        onChange={lambda (e: ChangeEvent) { title = e.target.value; }}
                        onKeyPress={lambda (e: KeyboardEvent) { if e.key == "Enter" { add(); } }} />
                    <input class="input" type="datetime-local" value={due}
                        onChange={lambda (e: ChangeEvent) { due = e.target.value; }} />
                    <input class="input small" value={effort} title="effort (min)"
                        onChange={lambda (e: ChangeEvent) { effort = e.target.value; }} />
                    <select class="input" value={repeat} onChange={lambda (e: ChangeEvent) { repeat = e.target.value; }}>
                        <option value="none">once</option>
                        <option value="daily">daily</option>
                        <option value="weekly">weekly</option>
                        <option value="monthly">monthly</option>
                    </select>
                    <button class="btn primary" onClick={lambda { add(); }}>Add</button>
                </div>
            </section>

            {(
                <section class="card edit">
                    <h3>Edit “{cur.title}”</h3>
                    <div class="ask-row wrap">
                        <input class="input grow" value={e_title} onChange={lambda (e: ChangeEvent) { e_title = e.target.value; }} />
                        <input class="input" type="datetime-local" value={e_due} onChange={lambda (e: ChangeEvent) { e_due = e.target.value; }} />
                        <input class="input small" value={e_effort} onChange={lambda (e: ChangeEvent) { e_effort = e.target.value; }} />
                        <select class="input" value={e_repeat} onChange={lambda (e: ChangeEvent) { e_repeat = e.target.value; }}>
                            <option value="none">once</option>
                            <option value="daily">daily</option>
                            <option value="weekly">weekly</option>
                            <option value="monthly">monthly</option>
                        </select>
                        <input class="input" value={e_loc} placeholder="location" onChange={lambda (e: ChangeEvent) { e_loc = e.target.value; }} />
                    </div>
                    <div class="ask-row wrap">
                        <span class="muted">Needs first:</span>
                        {[
                            <span key={b} class="pill dep">{b}</span> for b in cur.blocked_by
                        ]}
                        <select class="input" value={link_to} onChange={lambda (e: ChangeEvent) { link_to = e.target.value; }}>
                            <option value="">+ add prerequisite…</option>
                            {[
                                <option key={jid(i)} value={jid(i)}>{i.title}</option>
                                for i in items if jid(i) != editing
                            ]}
                        </select>
                        <button class="btn" onClick={lambda { addLink(); }}>Link</button>
                    </div>
                    {(<div class="error">{msg}</div>) if msg else None}
                    <div class="actions">
                        <button class="btn primary" onClick={lambda { saveEdit(); }}>Save</button>
                        <button class="btn ghost" onClick={lambda { editing = ""; }}>Cancel</button>
                        <button class="btn danger" onClick={lambda { remove(editing); }}>Delete</button>
                    </div>
                </section>
            ) if cur else None}

            <section>
                {[
                    <div key={jid(i)} class="row-with-actions">
                        <ItemCard
                            item={i}
                            highlight=""
                            onDone={lambda { complete(jid(i)); }}
                            onReopen={lambda { reopen(jid(i)); }}
                        />
                        <button class="btn tiny ghost" onClick={lambda { startEdit(i); }}>Edit</button>
                    </div> for i in items
                ]}
            </section>
            {(<button class="btn danger ghost" onClick={lambda { wipe(); }}>Clear everything</button>) if len(items) > 0 else None}
        </div>;
}
