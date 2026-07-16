"use strict";

// Vanilla ceremony on purpose: PublicKeyCredential.parseRequestOptionsFromJSON
// and credential.toJSON() are baseline in every modern browser, and this page
// only ever needs to work in the operator's browser. No bundler, no deps.

async function postJson(path, body) {
  const res = await fetch(path, {
    method: "POST",
    headers: { "X-CSRF-Protection": "1", "Content-Type": "application/json" },
    body: body === undefined ? undefined : JSON.stringify(body),
    credentials: "same-origin",
  });
  if (!res.ok) {
    let message = `Request failed (${res.status})`;
    try {
      message = (await res.json()).error || message;
    } catch {
      // non-JSON error body — keep the status-based message
    }
    throw new Error(message);
  }
  return res.json();
}

const signin = document.getElementById("signin");
if (signin) {
  const errorEl = document.getElementById("error");
  signin.addEventListener("click", async () => {
    errorEl.hidden = true;
    try {
      const begin = await postJson("/login/begin");
      const publicKey = PublicKeyCredential.parseRequestOptionsFromJSON(begin.options);
      const credential = await navigator.credentials.get({ publicKey });
      await postJson("/login/complete", {
        challengeToken: begin.challengeToken,
        credential: credential.toJSON(),
      });
      window.location.href = "/";
    } catch (err) {
      errorEl.textContent = err.message;
      errorEl.hidden = false;
    }
  });
}

const logout = document.getElementById("logout");
if (logout) {
  logout.addEventListener("click", async () => {
    // Redirect even if the request fails (e.g. the session already expired,
    // making /logout a 401) — /login is the right place either way, and it
    // bounces straight back to the dashboard if we somehow are still signed in.
    try {
      await postJson("/logout");
    } finally {
      window.location.href = "/login";
    }
  });
}
