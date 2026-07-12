---
name: dev-login
description: Log in to the local dev app (browser or curl) without digging the magic link out of server logs.
---

# Logging in on dev

In development the backend returns the magic login link directly in the
`POST /api/auth/login-link` response (`loginLink` field, dev only) — no need
to grep server logs. Dev servers must be running (`mise run dev`: backend
:9292, frontend :5173).

## Browser (human or Playwright)

Enter an existing user's email on `http://localhost:5173/login` and submit.
The success box shows an **"Open login link (dev)"** link — click it (or
`browser_navigate` to its href) and you're in.

Skipping the form entirely is one curl + one navigation:

```sh
curl -s -X POST http://localhost:9292/api/auth/login-link \
  -H 'Content-Type: application/json' -H 'X-CSRF-Protection: 1' \
  -d '{"email":"test@example.com"}' | jq -r .loginLink
```

Navigate the browser to the returned URL
(`http://localhost:5173/auth/verify?token=…`), then click the **"Log in"**
confirmation button (`data-testid="confirm-login"`) — the verify page doesn't
auto-submit, so email scanners can't consume the single-use token.

## API-only session (curl)

```sh
link=$(curl -s -X POST http://localhost:9292/api/auth/login-link \
  -H 'Content-Type: application/json' -H 'X-CSRF-Protection: 1' \
  -d '{"email":"test@example.com"}' | jq -r .loginLink)
curl -s -c /tmp/tayaway-cookies.txt -X POST http://localhost:9292/api/auth/verify \
  -H 'Content-Type: application/json' -H 'X-CSRF-Protection: 1' \
  -d "{\"token\":\"${link#*token=}\"}"
# subsequent requests: curl -b /tmp/tayaway-cookies.txt http://localhost:9292/api/auth/me
```

## Notes

- The user must already exist. `mise run db:reset` seeds `test@example.com`,
  `alice@example.com`, `bob@example.com`, `charlie@example.com`,
  `diana@example.com` (see `backend/db/seed_dev.rb`).
- Links are single-use and expire; requesting a new one invalidates earlier
  unused links for that user, so always use the freshest one.
- All mutating requests need the `X-CSRF-Protection: 1` header.
- E2E servers (:9293/:5174) are different: use `POST /api/test/session`
  there (see `e2e/helpers.ts`), which is disabled in development.
