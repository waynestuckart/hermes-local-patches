# Antigravity Studio

A single-file **Manager Surface** for the Wayne OS / AgenOS fleet — inspired by
Google Antigravity's agent-first model (spawn parallel agents, watch them work,
verify everything through **artifacts**). No build step, no dependencies, no
framework. One `.html` file you drop on the VPS.

## What's in it

- **Manager Surface** — the full fleet (Dax orchestrator, Claude, Hermes,
  ChatGPT, Gemini, Antigravity, AI-Q, Camofox, Home Assistant) as live cards
  with status, model, provider, load sparkline, and `Dispatch / Logs / Pause`.
- **Mission Queue** — a `Queued → Running → Review → Done` board. Dispatching a
  mission animates it across the lanes and drops an **artifact** when it lands.
- **Artifacts gallery** — task lists, plans, screenshots, browser recordings,
  diffs — Antigravity's "verify the logic at a glance" loop.
- **Command bar + voice** — type a mission (auto-routed to the right agent) or
  hit the mic (Web Speech API, feature-detected).
- **Command palette** — `⌘K` / `Ctrl+K` for quick actions.
- **Fixed panels** — `Node Health` (working **Probe** button with reachable /
  unreachable states), `Provider Heatmap` (per-provider ok/warn/down), `Cost
  Savings`, and a live **Activity** feed. These render proper loading / healthy
  / error states instead of the dead `unreachable` / `0/0 healthy` from the old
  build.

## Going live

The Studio runs fully on a local snapshot, so it never looks dead. To wire it to
your real data, set the endpoints near the top of the `<script>`:

```js
const CONFIG = {
  endpoints: {
    agents:   "https://dashboard.wayneautomates.com/api/agents",   // {fleet:[{id,status,model,load,...}]}
    health:   "https://dashboard.wayneautomates.com/api/health",   // {reachable,nodes,latencyMs,providers:[...]}
    providers:"https://dashboard.wayneautomates.com/api/providers",
    savings:  "https://dashboard.wayneautomates.com/api/savings",  // {spend,tokens}
    dispatch: "https://dashboard.wayneautomates.com/api/dispatch",  // POST {agent,prompt}
  },
  refreshMs: 30000,
};
```

Any endpoint left as `""` is skipped and the local snapshot is used. A failed
fetch falls back silently — the footer flips between `live` and `offline`.

## Deploy

```bash
# from the VPS (5.78.133.56)
scp antigravity-studio.html  /var/www/wayneautomates/studio/index.html
# then link it from the AgenOS sidebar → https://dashboard.wayneautomates.com/studio/
```

That's it — it's one static file.
