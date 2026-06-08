# Handoff → Hermes: deploy Antigravity Studio

**From:** Claude · **For:** Hermes · **Reviewer:** Wayne
**Artifact:** `studio/antigravity-studio.html` (single self-contained file, no build, no deps)
**Goal:** fill `CONFIG.endpoints`, serve it under `dashboard.wayneautomates.com/studio/`, link it from the AgenOS sidebar, confirm it flips to **live**. Then hand back to Wayne for review.

---

## 0 · TL;DR for Hermes

1. Pull the file from branch `claude/agenos-hermes-gQ8IL` (PR #1) or copy the attachment.
2. Edit the `CONFIG.endpoints` block (one place, top of `<script>`).
3. `scp` to the VPS web root, link it in the sidebar.
4. Build/confirm the 4 `/api/*` routes return the shapes in §3.
5. Open it, check the footer says `live · HH:MM:SS` and **Probe** is green.

It works **before** any of this (runs on a local snapshot), so deploy first, wire endpoints second — nothing will look broken at any step.

---

## 1 · Get the file

```bash
# on the VPS (5.78.133.56)
cd /tmp
git clone -b claude/agenos-hermes-gQ8IL https://github.com/waynestuckart/hermes-local-patches
cp hermes-local-patches/studio/antigravity-studio.html ./studio.html
```

(or just use the .html Wayne was sent — they're identical.)

---

## 2 · Fill the config

Open `studio.html`, find `const CONFIG` near the top of `<script>`, set the URLs.
**Leave any endpoint as `""` to keep that panel on the local snapshot** — partial wiring is fine.

```js
const CONFIG = {
  endpoints: {
    agents:   "https://dashboard.wayneautomates.com/api/agents",
    health:   "https://dashboard.wayneautomates.com/api/health",
    providers:"",   // reserved — not consumed yet, leave blank (heatmap comes from /api/health)
    savings:  "https://dashboard.wayneautomates.com/api/savings",
    dispatch: "https://dashboard.wayneautomates.com/api/dispatch",
  },
  refreshMs: 30000,   // poll interval; bump if you want lighter load
};
```

> CORS: if the API is served from the **same** origin (`dashboard.wayneautomates.com`) no CORS headers are needed. If it's a different host/port, add `Access-Control-Allow-Origin: https://dashboard.wayneautomates.com` to the API responses.

---

## 3 · API contract (what each endpoint must return)

All are **GET** returning JSON, except `dispatch` (POST). A failed/missing fetch falls back to the snapshot silently — so you can ship routes one at a time.

### `GET /api/agents`  → live fleet state (optional, partial)
Merged **by `id`** into the roster. Send only the fields that change.
```json
{ "fleet": [
  { "id": "dax",    "status": "online", "model": "Dynamic",     "load": 81 },
  { "id": "anti",   "status": "online", "model": "antigravity-2","load": 88 },
  { "id": "aiq",    "status": "idle",   "load": 0 }
] }
```
**Valid `id`s** (must match exactly):
`dax, claude, hermes, gpt, gemini, anti, aiq, camo, ha`
`status` ∈ `online | idle | paused | offline`. `load` is 0–100.

### `GET /api/health`  → node health + provider heatmap
```json
{
  "reachable": true,
  "nodes": 4,
  "latencyMs": 34,
  "providers": ["ok","ok","ok","ok","ok","warn","ok","ok","ok","ok"]
}
```
`providers` is a 10-element array, **in this exact order**, each `ok | warn | down`:
`[Hermes, Anthropic, OpenAI, Google, NousResearch, OpenRouter, AI-Q, HA, Camoufox, Local]`
Drives the **Probe** button result and the **Provider Heatmap**.

### `GET /api/savings`  → top stat numbers
```json
{ "spend": 4.12, "tokens": 1.84 }
```
`spend` = USD today (number). `tokens` = millions in last 24h (the UI appends `M`).

### `POST /api/dispatch`  → run a mission (fire-and-forget)
Body the UI sends:
```json
{ "agent": "anti", "prompt": "scaffold the Emotiva landing page" }
```
The UI doesn't wait on the response — it optimistically animates the task and emits an artifact. Wire this to whatever actually kicks a job (Dax router / cron / agent runner). Returning `200 {}` is enough.

---

## 4 · Deploy

```bash
# pick the path your nginx already serves; example:
sudo mkdir -p /var/www/wayneautomates/studio
sudo cp studio.html /var/www/wayneautomates/studio/index.html
sudo chown -R www-data:www-data /var/www/wayneautomates/studio
```

If nginx isn't already routing `/studio/`, add inside the `server { }` for `dashboard.wayneautomates.com`:
```nginx
location /studio/ {
    alias /var/www/wayneautomates/studio/;
    index index.html;
}
```
then `sudo nginx -t && sudo systemctl reload nginx`.

**Link it from the AgenOS sidebar** — add an entry next to "Antigravity":
```
🚀  Antigravity Studio  →  https://dashboard.wayneautomates.com/studio/
```

---

## 5 · Verify (acceptance checklist)

- [ ] `https://dashboard.wayneautomates.com/studio/` loads, dark neon UI, fleet cards visible.
- [ ] Footer (bottom right) reads **`live · HH:MM:SS`** — not `offline · using local fleet snapshot`. (If it says offline, at least one `/api/*` route isn't returning JSON / is CORS-blocked.)
- [ ] **Probe** (Node Health card) turns green and shows `N nodes reachable · <ms>`.
- [ ] Provider Heatmap matches reality (any `down` provider shows red).
- [ ] Top stats (Spend / Tokens) reflect `/api/savings`.
- [ ] Type a mission in the command bar + Enter → task animates Queued→Running→Review and an artifact appears (this is client-side; `/api/dispatch` just needs to 200).
- [ ] `⌘K` / `Ctrl+K` opens the command palette; mic button prompts for permission (HTTPS required for voice).

---

## 6 · Notes / gotchas

- **Voice** (Web Speech API) only works over **HTTPS** and in Chromium-based browsers; it self-disables with a toast elsewhere — expected.
- **No build step.** It's one static file; edits are live on next reload. Keep the canonical copy in the repo so changes survive.
- **Snapshot is the floor, not the ceiling** — every panel degrades to believable mock data, so a half-wired deploy still looks finished.
- The `providers` endpoint in CONFIG is **reserved** (heatmap is driven by `/api/health.providers`); leave it blank for now.

---

## 6b · The chat page — `hermes-chat.html`  ← Wayne's priority

This is the **"Talk to Hermes"** page: Wayne types, you reply, and (if the speaker
is on) your reply is read aloud. It also takes voice input. Deploy it the same way
(e.g. `/var/www/wayneautomates/studio/chat.html` → linked as **Hermes** in the
sidebar). It runs in a friendly **demo mode** until you wire one endpoint:

```js
// top of <script> in hermes-chat.html
const CONFIG = {
  chat: "https://dashboard.wayneautomates.com/api/chat",
  stream: false,        // true if you stream Server-Sent Events
  voiceOut: true,
  voiceHint: "female",
};
```

### `POST /api/chat`  → Hermes's reply
Request body the page sends:
```json
{ "message": "turn the office lamp on", "history": [
  { "role": "user", "content": "hi" },
  { "role": "assistant", "content": "hey Wayne" }
] }
```
**Option A — plain JSON (simplest):** return any one of these keys —
```json
{ "reply": "Done — office lamp is on." }
```
(`reply` / `text` / `content` / OpenAI-style `choices[0].message.content` all work.)

**Option B — streaming:** set `stream:true` and return `text/event-stream`; the page
appends tokens live. Each line may be a raw token or `data: {"token":"..."}`; end with `[DONE]`.

Wire this to the Hermes gateway (the same brain behind Dax). When it returns 200 with a
reply, the header badge flips from **demo mode** to **connected · online**. That's the
whole job — one route and Wayne can actually talk to you.

> HTTPS is required for the mic and for spoken replies to work in the browser.

---

## 7 · Hand back to Wayne

Once it's live and the checklist passes, ping Wayne with the URL. Round 2 ideas already on the table: per-agent control rooms, real Home Assistant quick-controls, an artifact detail view with inline feedback, and a synchronous Editor view.

— Claude
