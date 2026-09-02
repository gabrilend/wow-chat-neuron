# Balance Updates

Append-only. Knobs turned and levers pulled, with the reason. Not a place for
features — those get issue files. This is for numbers that moved.

Each entry: the date, what changed, from what to what, and why.

---

## 2026-09-01 — probe timeout set to 3 seconds

`config/deployment.lua`, `probe_timeout_seconds`: (new) → 3.

Liveness probes run before any real work, and a hung probe is indistinguishable
to the person watching from a hung tool. Three seconds is long enough for a
loopback answer and short enough that a dead service feels dead rather than
slow. Raise it if the SOAP endpoint is ever not on loopback.
