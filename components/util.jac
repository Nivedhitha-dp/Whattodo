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

# ---------------------------------------------------------------------------
# Voice (Web Speech API -- runs entirely in the browser, Chrome/Edge/Safari)
# ---------------------------------------------------------------------------

glob voice_state: dict[str, any] = {"rec": None};

def:pub speech_supported -> bool {
    w: any = window;   # speech APIs are missing from the DOM typings
    return Boolean(w.SpeechRecognition or w.webkitSpeechRecognition);
}

"""Listen once. `on_interim(text)` streams partial text; `on_done(text, error)` fires when speech ends."""
def:pub listen(on_interim: any, on_done: any) {
    w: any = window;
    Ctor = w.SpeechRecognition or w.webkitSpeechRecognition;
    if not Ctor {
        on_done.call(None, "", "unsupported");
        return;
    }
    rec = new(Ctor);
    rec.lang = "en-US";
    rec.interimResults = True;
    rec.continuous = False;
    heard = {"text": "", "error": ""};
    rec.onresult = lambda (e: any) {
        t = "";
        for r in Array.from(e.results) {
            t = t + String(r[0].transcript);
        }
        heard["text"] = t;
        on_interim.call(None, t);
    };
    rec.onerror = lambda (e: any) { heard["error"] = String(e.error); };
    rec.onend = lambda {
        voice_state["rec"] = None;
        on_done.call(None, heard["text"], heard["error"]);
    };
    voice_state["rec"] = rec;
    rec.start();
}

"""Read `text` aloud, then call `on_done()` exactly once -- even if the browser
never fires `onend` (a known Chrome quirk) or speech synthesis fails entirely."""
def:pub speak(text: str, on_done: any) {
    w: any = window;
    state = {"done": False};
    def finish {
        if not state["done"] {
            state["done"] = True;
            on_done.call(None);
        }
    }
    synth = w.speechSynthesis;
    if not synth or not w.SpeechSynthesisUtterance {
        finish();
        return;
    }
    try {
        synth.cancel();
        u = new(w.SpeechSynthesisUtterance, text);
        u.lang = "en-US";
        u.rate = 1.05;
        u.onend = lambda { finish(); };
        u.onerror = lambda { finish(); };
        synth.speak(u);
        # safety net: ~0.45s per word + 3s
        setTimeout(lambda { finish(); }, len(text.split(" ")) * 450 + 3000);
    } except Exception as e {
        finish();
    }
}

def:pub stop_voice {
    if voice_state["rec"] {
        voice_state["rec"].stop();
    }
    w: any = window;
    if w.speechSynthesis {
        w.speechSynthesis.cancel();
    }
}
