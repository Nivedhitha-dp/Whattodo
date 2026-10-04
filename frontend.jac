"""Client orchestrator: auth gate + tab shell."""

import "./styles.css";
import from "@jac/runtime" { jacIsLoggedIn, jacLogout }
import from .components.AuthForm { AuthForm }
import from .components.NowPanel { NowPanel }
import from .components.PlanPanel { PlanPanel }
import from .components.GraphPanel { GraphPanel }
import from .components.ItemsPanel { ItemsPanel }

def:pub app -> JsxElement {
    has isLoggedIn: bool = False,
        checked: bool = False,
        tab: str = "now",
        version: int = 0;

    can with entry {
        isLoggedIn = jacIsLoggedIn();
        checked = True;
    }

    def logout {
        jacLogout();
        isLoggedIn = False;
    }

    def changed {
        version = version + 1;
    }

    if not checked {
        return <div class="center muted">Loading…</div>;
    }
    if not isLoggedIn {
        return <AuthForm onAuth={lambda { isLoggedIn = True; }} />;
    }

    tabs = [
        ["now", "⚡ What now"],
        ["plan", "🧠 Plan"],
        ["graph", "🕸 Graph"],
        ["items", "📋 All items"]
    ];

    return
        <div class="shell">
            <header class="topbar">
                <div class="brand">
                    <span class="logo">◆</span> LifeFlow
                    <span class="tagline">what should I do next?</span>
                </div>
                <nav class="tabs">
                    {[
                        <button
                            key={t[0]}
                            class={"tab " + ("active" if tab == t[0] else "")}
                            onClick={lambda { tab = t[0]; }}
                        >
                            {t[1]}
                        </button> for t in tabs
                    ]}
                </nav>
                <button class="btn ghost" onClick={lambda { logout(); }}>Sign out</button>
            </header>
            <main class="content">
                {(<NowPanel key={"now" + String(version)} onChange={changed} />) if tab == "now" else None}
                {(<PlanPanel onSaved={lambda { changed(); tab = "graph"; }} />) if tab == "plan" else None}
                {(<GraphPanel key={"graph" + String(version)} />) if tab == "graph" else None}
                {(<ItemsPanel key={"items" + String(version)} onChange={changed} />) if tab == "items" else None}
            </main>
        </div>;
}
