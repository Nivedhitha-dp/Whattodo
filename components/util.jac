"""Small client helpers shared by the panels."""

"""Browser-local wall clock as 'YYYY-MM-DDTHH:MM' (the server stores user-local times)."""
def:pub local_now -> str {
    d = new(Date);
    shifted = new(Date, d.getTime() - d.getTimezoneOffset() * 60000);
    return shifted.toISOString()[:16];
}

"""'2026-10-09T23:59' -> 'Fri Oct 9, 11:59 PM'."""
def:pub pretty(ts: str) -> str {
    if not ts {
        return "";
    }
    d = new(Date, ts);
    return d.toLocaleString(
        "en-US",
        {"weekday": "short", "month": "short", "day": "numeric", "hour": "numeric", "minute": "2-digit"}
    );
}

"""Slack minutes -> '3h 20m left' / '45m behind'."""
def:pub slack_text(mins: int) -> str {
    a = Math.abs(mins);
    txt = "";
    if a >= 1440 {
        txt = String(Math.floor(a / 1440)) + "d " + String(Math.floor((a % 1440) / 60)) + "h";
    } elif a >= 60 {
        txt = String(Math.floor(a / 60)) + "h " + String(a % 60) + "m";
    } else {
        txt = String(a) + "m";
    }
    return txt + (" behind" if mins < 0 else " to spare");
}

def:pub kind_icon(kind: str) -> str {
    icons = {
        "assignment": "📚", "bill": "💸", "errand": "📦", "chore": "🧺",
        "appointment": "📅", "work": "💼", "health": "🩺", "social": "💬",
        "shopping": "🛒"
    };
    return icons[kind] if kind in icons else "•";
}
