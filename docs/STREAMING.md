# Live Streaming — architecture, limits, and how many churches can stream at once

> Last updated: 2026-10-01. Applies to the Cloudflare Stream backend, which is
> the **only** streaming backend in the app (MediaMTX was removed 2026-09-14).

---

## 1. The one fact that determines everything

**A phone-camera broadcast and an OBS broadcast are not two ways of doing the
same thing. They are two different products.**

Cloudflare's own WebRTC documentation states that WHIP and WHEP must be used
together and that:

> Recording and live HLS playback are not yet supported. Simulcasting is not
> supported. Live viewer counts are not supported.

That is verified against the vendor docs, not inferred. So:

| | **RTMPS / OBS / encoder** (`ingest_mode='rtmps'`) | **WHIP / phone camera** (`ingest_mode='whip'`) |
|---|---|---|
| What viewers get | Adaptive **HLS** (CDN-scalable) | **WHEP** WebRTC only |
| Audience size | Congregation-sized (thousands) | A handful |
| Auto-recording | Yes | **Never** |
| Replay / sermon | Yes | **No** |
| Archive to R2 | Yes | **No** |
| Live viewer count | Yes | Cloudflare does not support it |

**Consequence for the product:** RTMPS is the production path for a real
service. WHIP is a phone-camera convenience for impromptu/short broadcasts, and
the app now says so explicitly rather than pretending a phone stream is
equivalent — the studio records `ingest_mode`, the archive sweep stops chasing a
recording that cannot exist, and the UI can explain a missing replay.

The earlier HLS-URL-on-a-WHIP-input behaviour is the source of the `204` /
`409` errors in the logs: Cloudflare's live-input manifest answers **HTTP 204**
for the whole duration of a WebRTC broadcast, and WHEP against an input with no
active session answers **409**. Both are correct HTTP for "there is no media
here", and the viewer now treats them that way instead of looping.

---

## 2. End-to-end flow (what actually happens)

### Starting (studio → congregation)

1. Leader taps **Start** → `UnifiedStreamService.createLiveStream(tenantId, title)`.
2. `checkStreamGate` — expiry of abandoned rows, weekly minutes, one active
   stream per church (partial unique index), storage.
3. `cloudflare-stream` Edge Function `create_live_input` → Cloudflare returns
   **both** `rtmps` credentials **and** `webRTC`/`webRTCPlayback`, so either
   ingest path is available from the same input.
4. Row inserted into `live_streams` with `status='live'`. **This does not
   announce anything yet** — see §3.
5. Studio tries WHIP first. If the WebRTC peer connects → `ingest_mode='whip'`
   and `broadcast_started_at = now()`.
6. If WHIP does not connect, the leader gets the OBS/RTMPS credentials. The
   15s heartbeat polls Cloudflare's live-input status; the **first time it
   reports `connected`**, `ingest_mode='rtmps'` and `broadcast_started_at` are
   stamped and `church_live_status.is_live` is flipped.
7. The DB trigger queues a `started` event; the 30s cron dispatches it.

### Watching

- Member's own church: home LIVE pill, the `/live-streaming` hub, or a shared
  `/church/<id>/live` link — all resolve through `getActiveStreamForChurch`,
  scoped by `church_id`.
- Viewer opens `/live-player?id=<stream_id>` → `stream_start_session` →
  `stream_viewer_heartbeat` every 45s → `stream_end_session` on close.
- Playback ladder: `recording_hls_url` (ended) → `hls_url` → WHEP
  (`preview_url`) → `recording_hls_url` → R2 `archive_url`. On failure it
  escalates to WHEP **once** per cycle (`_whepAttempted`), which is what
  prevents the old unbounded HLS→WHEP→HLS loop.

### Ending

`endStream` → record minutes → `status='ended'` → best-effort archive →
disable the live input (archived *before* disabling, or the recording is lost)
→ `stream_ended` notification queued and dispatched with copy that mentions the
recording when one exists.

---

## 3. Why announcements key off "media is flowing"

`createLiveStream` inserts the row with `status='live'` the instant the input is
**created** — before any encoder has published a frame. Announcing on `status`
meant a leader could arm OBS, walk away, and the entire congregation would still
be told the service was live.

`broadcast_started_at` is the honest signal:

- **WHIP** — the WebRTC peer connected, so media is demonstrably flowing.
- **RTMPS** — Cloudflare reported the live input `connected`.

The congregation is told "service is live now" only after that. The home LIVE
pill flips at the same instant, so the push and the UI cannot disagree.

---

## 4. Notification pipeline (why an outbox)

`stream_notification_outbox` is unique on `(stream_id, kind)`. A trigger appends
one cheap row; a 30-second cron drains **all** pending events for **all**
churches, set-based:

- one `INSERT ... SELECT` for the in-app rows (never a per-user loop),
- device push chunked 500 recipients per call,
- cap via `platform_settings.stream_notify_member_cap` (default 2000),
- broadcaster excluded,
- re-dispatch is idempotent, so a cron tick can overlap safely.

A synchronous trigger fan-out would block the very write that starts the
broadcast and would time out on a large congregation. The outbox decouples
"the service started" from "tell 5000 people", which is also what makes many
simultaneous churches safe.

**Verified:** 12/12 assertions in
`supabase/tests/stream_notification_pipeline_test.sql` (runs the real triggers +
dispatcher inside a rolled-back transaction — writes nothing, sends nothing).
The first real dispatch created 13 `stream_started` notifications.

---

## 5. How many churches can stream at once?

### The short answer

**Cloudflare publishes no hard cap on concurrent live inputs.** There is no
"max N simultaneous streams" limit in the Stream documentation. The binding
constraints are **billing (minutes delivered)**, **storage (minutes stored)**,
and your own operational gates — not a concurrency ceiling.

So the honest answer is: **all of them, if you have the budget.** 1000 churches
streaming simultaneously is not blocked by Cloudflare.

### What actually limits each church

| Limit | Where | Value |
|---|---|---|
| Concurrent streams **per church** | partial unique index + `stop_other_streams` | **1** (by design — a church broadcasts one service) |
| Weekly minutes per church | `checkStreamGate` | `church_stream_config.max_minutes_per_week` (480) |
| Max viewers per church | model, **not yet enforced at start** | 1000 |
| Max duration | passed to Cloudflare `meta.max_duration` | 14,400s (4h) |
| Retention | `deleteRecordingAfterDays` | 90 days |
| Notify fan-out per event | `stream_notify_member_cap` | 2000 members |

**1000 churches × 1 concurrent stream each = 1000 concurrent inputs.** Each is
an independent Cloudflare live input with its own credentials, and our database
scales to it because every operation is keyed by `church_id` and bounded:

- one outbox row per event (not per recipient),
- the dispatcher processes 100 pending events per 30s tick,
- the viewer rollup is O(live streams) per minute, not O(viewers),
- the archive sweep is `LIMIT 5` rows per 10-minute run with backoff.

### The number that will actually bite you first: money, not concurrency

Cloudflare Stream bills **$1 per 1,000 minutes of video delivered** and
**$5 per 1,000 minutes stored**. A Sunday where all 1000 churches broadcast for
60 minutes to an average of 200 viewers:

```
1000 churches x 60 min x 200 viewers = 12,000,000 minutes delivered
                               = 12,000 x $1        = $12,000
storage: 1000 x 60 min = 60,000 min stored = 60 x $5 = $300
```

~**$12,300 per all-churches Sunday** (60 min × 200 viewers each). Two such
Sundays a month is ~$25k/month. A typical Sunday where 30 churches broadcast
instead is ~**$369**.

Practical guidance:

| Scenario | Concurrent inputs | Delivered minutes | Delivered | Stored | Total |
|---|---|---|---|---|---|
| 30 churches, 60 min, 200 viewers | 30 | 360,000 | $360 | $9 | **~$369** |
| 100 churches, 60 min, 200 viewers | 100 | 1,200,000 | $1,200 | $30 | **~$1,230** |
| 1000 churches, 60 min, 200 viewers | 1000 | 12,000,000 | $12,000 | $300 | **~$12,300** |

(Arithmetic verified: `delivered_min / 1000 * $1` + `stored_min / 1000 * $5`.)

**Recommendation:** keep 1 concurrent stream per church (already enforced), and
introduce a platform-level concurrent-input budget plus per-church weekly-minute
caps as the levers — both of which you control in `platform_settings`. The
`stream_notify_member_cap` and `max_minutes_per_week` keys already exist for
exactly this.

### Viewing 1000 concurrent HLS streams is the easy part

HLS output is CDN-served segments, so a congregation-sized audience costs
nothing extra in engineering — only in delivered minutes. This is the whole
reason RTMPS is the production path and WHIP is not: a WHEP stream needs a
live WebRTC session per viewer, which is simultaneously more expensive and
cannot be recorded.

---

## 6. Verification status — be honest about what is and isn't proven

| Verified | How |
|---|---|
| Notification pipeline end-to-end | 12/12 SQL assertions on the real code path, rolled back |
| Real notifications delivered | 13 `stream_started` rows created live |
| `weather-alerts` Edge Function | `?action=health` OK; `preview` dry run OK; live Open-Meteo forecast |
| Column allowlist | 0 SELECT grants on credential columns for `anon` + `authenticated` |
| Cron wiring | 5 stream crons active, incl. `stream-notify-dispatch` (30s), `stream-viewer-rollup` (1m) |
| `dart analyze lib` | 0 errors, 0 warnings |
| Test suite | 524 pass / 1 pre-existing harness failure |

**Not yet proven — needs a real encoder, which this environment cannot drive:**

- That an OBS encoder publishing to a real live input flips
  `broadcast_started_at` and fires the congregation push. The code path is
  wired and the signal source is Cloudflare's `connected` field, but it has not
  been observed with a live RTMPS encoder in this session.
- End-to-end HLS playback in a browser/mobile player for a real broadcast.
- WHIP phone→WHEP viewer playback with a real congregation-size audience.

**The blocker that is not ours:** the logs in the previous session show HLS
`204` and WHEP `409` for the same input. That is Cloudflare reporting that **no
encoder was publishing** — the input was armed but nothing was connected. No
amount of app code can make media appear; an encoder (OBS, or a phone actually
running the studio's WHIP publish) must connect to the input first. That is the
single thing to verify with a real OBS session.

---

## 7. Quick reference

| Concern | Where |
|---|---|
| Broadcast limits | `church_stream_config`, `checkStreamGate` (`unified_stream_service.dart`) |
| Notifications | `stream_notification_outbox`, `dispatch_stream_notifications()` |
| Ingest reality | `live_streams.ingest_mode`, `markIngestMode()` |
| "Media is flowing" | `live_streams.broadcast_started_at`, `markBroadcastStarted()` |
| Push channel | `coa_live_stream_v2` (push-notifications + client) |
| Share links | `lib/core/services/deep_links.dart` |
| Per-church link | `/church/:churchId/live`, `/live-streaming?tenant=` |
| Archive/replay | `auto_archive_stream_recordings()` cron, `sync_recorded_service` |
| Pipeline test | `supabase/tests/stream_notification_pipeline_test.sql` |
