"""Login / signup card."""

import from "@jac/runtime" { jacLogin, jacSignup }

def:pub AuthForm(onAuth: Callable[[], None]) -> JsxElement {
    has isSignup: bool = False,
        username: str = "",
        password: str = "",
        error: str = "",
        loading: bool = False;

    async def submit(e: FormEvent) {
        e.preventDefault();
        error = "";
        if not username.strip() or not password {
            error = "Please fill in both fields";
            return;
        }
        loading = True;
        if isSignup {
            result = await jacSignup(username, password);
            if not result["success"] {
                loading = False;
                error = str(result["error"]) if result["error"] else "Signup failed";
                return;
            }
        }
        ok = await jacLogin(username, password);
        loading = False;
        if ok {
            onAuth();
        } else {
            error = "Invalid username or password";
        }
    }

    return
        <div class="auth-wrap">
            <div class="auth-card">
                <div class="auth-logo">◆</div>
                <h1>LifeFlow</h1>
                <p class="muted">
                    Not a reminder list. A graph of everything you need to get done,
                    what depends on what, and what to do next.
                </p>
                {(<div class="error">{error}</div>) if error else None}
                <form onSubmit={submit}>
                    <input
                        class="input"
                        value={username}
                        placeholder="Username"
                        onChange={lambda (e: ChangeEvent) { username = e.target.value; }}
                    />
                    <input
                        class="input"
                        type="password"
                        value={password}
                        placeholder="Password"
                        onChange={lambda (e: ChangeEvent) { password = e.target.value; }}
                    />
                    <button class="btn primary wide" type="submit" disabled={loading}>
                        {("…" if loading else ("Create account" if isSignup else "Sign in"))}
                    </button>
                </form>
                <button
                    class="btn link"
                    type="button"
                    onClick={lambda { isSignup = not isSignup; error = ""; }}
                >
                    {("Have an account? Sign in" if isSignup else "New here? Create an account")}
                </button>
            </div>
        </div>;
}
