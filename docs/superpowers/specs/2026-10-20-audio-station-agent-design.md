# Audio station agent — design

## What this is

A **new repository**, `mediateca-audio-station`, implements an audio-only
station agent for Linux mini-PCs. It pulls the Hub’s daily timed playlist,
caches media files locally, and plays them with **mpv**
([mpv.io](https://mpv.io)) on the machine itself.

The Hub registers exactly one **pseudo-screen** on an audio station (see
`2026-10-20-station-medium-audio-video-design.md`). The agent maps that
`screen_id` to the local audio output. There is no Android TV, no ADB, and no
LAN HTTP media server for displays.

The Broadcast Hub in `mediateca-broadcast` is not modified by this repository
beyond the medium/playlist work described in the Hub design. This agent
consumes the **existing** agent API.

## Why this shape

Video stations already use a Go agent (`mediateca-station`) that drives VLC on
Android TVs over ADB. Audio stations have a different physical topology: the
mini-PC **is** the player. A second agent keeps that difference explicit and
avoids loading ADB/VLC concerns into the audio path.

Chosen runtime: **Ruby compiled with Spinel**
([matz/spinel](https://github.com/matz/spinel)) into a standalone native
binary under systemd. Rejected: extending the Go video agent with an mpv mode
(crosses the product split and conflicts with the Ruby/Spinel requirement).
Rejected: a custom audio API on the Hub (duplicates v2 timed playlist).
Rejected: bundling mpv inside the Spinel binary (use the host package).

## Decisions already made

- **Process.** One long-running binary from Spinel. systemd
  `Restart=always`. Exit non-zero only when the config file is missing,
  unreadable, invalid, or world/group-readable (`0077` bits set) so bad config
  does not crash-loop quietly. Runtime playback errors do not exit the
  process.
- **Language.** Ruby subset that Spinel accepts. Develop and unit-test under
  CRuby; `spin build` / `spinel` is the release compile gate. Prefer
  `Process.spawn` / Open3 package over `IO.popen` (refused by Spinel). Avoid
  `eval`, runtime `define_method`, and other AOT refusals from Spinel’s
  limitations doc.
- **Hub base.** Config `hub_base_url` (no trailing path). Paths appended:
  `/api/agent/v1/config`, `/api/agent/v2/package`,
  `/api/agent/v1/play_events`.
- **Auth.** `Authorization: Bearer <agent_token>` on `/api/agent/*` only. Media
  downloads do not send the token (same as video agent).
- **Clocks.** Mini-PC clock + NTP (chrony or equivalent) in UTC. Schedule uses
  absolute `starts_at` instants from the package. Location TZ is not
  reinterpreted on the agent.
- **Late threshold.** Default 2 seconds (`late_threshold`).
- **Poll.** Default 1 minute (`poll_interval`). Each poll refreshes config and
  package.
- **Screen binding.** Config names the single Hub `screen_id` to play (or a
  one-entry map). Hub screens not listed are ignored. If Hub config returns
  zero or many screens, log once per change; still play only the configured
  id when present in the package timeline.
- **Player.** Host `mpv` binary (`mpv_path`, default `mpv`). Start with
  `--no-video` (and idle/quit flags suitable for one-shot clips). Optional
  `audio_device` passed through to mpv when set. **MVP stop/start:** kill the
  previous mpv process, then spawn the next (no long-lived IPC session
  required).
- **Media.** Play the cached original file from the package URL (audio MIME).
  No local transcode.
- **Play events.** Enqueue only after mpv **start succeeds**, with the
  timestamp taken immediately before the start attempt (same reporting
  semantics as the video agent’s pre-ADB timestamp).
- **Secrets on disk.** Refuse start if config mode allows group/world access.
  Never log the token.
- **Out of MVP.** Multi-channel audio, CEC/display control, companion UI,
  Hub API changes, audio transcode, heartbeat routes, frame sync.

## Components

Entry point parses `-config` and calls `Run`. Each library has one job.

| Module | Responsibility |
| --- | --- |
| `config` | Load/validate YAML; enforce file mode; defaults |
| `hub` | HTTP client: config, package, one play-event POST |
| `cache` | Download `media.url` by `media.id`; prune unreferenced files |
| `schedule` | Pure timeline: given package, screen_id, clock → action |
| `player` | Spawn/kill mpv for a local path; no scheduling policy |
| `report` | Durable queue of play events + played-set dedupe |
| `agent` | Wire poll → cache → schedule → play → report loops |

`schedule` and `report` must not import `player` or `hub` so they test without
network or mpv.

### Config file

Path from `-config` (README example:
`/etc/mediateca-audio-station/config.yaml`).

```yaml
hub_base_url: "https://hub.example"
agent_token: "<token>"
cache_dir: "/var/lib/mediateca-audio-station/cache"
screen_id: 42
poll_interval: 60s
late_threshold: 2s
mpv_path: "mpv"
# audio_device: "alsa/hdmi:CARD=…,DEV=0"   # optional
```

Validation:

- `hub_base_url` required, absolute HTTP(S), no path suffix required beyond
  origin (strip trailing `/`).
- `agent_token` non-empty.
- `cache_dir` writable.
- `screen_id` positive integer.
- `poll_interval` / `late_threshold` positive durations.
- `mpv_path` non-empty; existence may be checked at start (warn or fail — prefer
  **fail** if missing so the unit does not run blind).

### Playback rules

Given current UTC time `now` and the package entries for `screen_id`:

1. Find the entry whose interval `[starts_at, starts_at + duration)` contains
   `now`, or the next due entry if implementing a short look-ahead tick (match
   video-agent schedule semantics: start when due and not late).
2. If `now - starts_at > late_threshold`, skip; do not play; do not report.
3. If the media file is not yet in cache, skip; log error; do not report.
4. Stop any current mpv; spawn mpv on the cached path; on spawn failure log and
   do not report; on success enqueue play_event.
5. When `duration_seconds` elapses (or mpv exits early), stop and wait for the
   next schedule decision.

No frame-accurate sync with video stations is required.

### Cache

- Key files by `media.id` (and store MIME sidecar if useful for Content-Type
  debugging; not required for mpv).
- After each successful package fetch, delete cached ids not referenced by the
  current package (and optionally the next day’s package if the poll already
  fetched a horizon — follow the video agent’s prune policy if documented;
  otherwise prune to the latest package only).
- Downloads are ordinary HTTP GET to `media.url` without the agent Bearer
  token.

### Reporting

- Persist pending play events on disk under the cache/state dir so a crash
  after successful start still retries POST.
- POST body matches existing Hub `play_events` contract (screen_id, media id,
  played_at, playlist identity fields as required by current Hub — mirror the
  video agent’s payload, do not invent fields).
- Deduplicate by a played-set so retries do not double-count.

### systemd

Example unit (ship in repo `deploy/` or `packaging/`):

```ini
[Unit]
Description=Mediateca audio station agent
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/mediateca-audio-station -config /etc/mediateca-audio-station/config.yaml
Restart=always
RestartSec=5
User=mediateca-audio
Group=mediateca-audio

[Install]
WantedBy=multi-user.target
```

Host packages: `mpv`, NTP client. Binary has no Ruby runtime dependency after
Spinel compile.

## Spinel build

- Scaffold with `spin new` / project layout per Spinel docs.
- Dependencies only from packages Spinel can compile into the binary (stdlib
  HTTP/JSON/YAML subset, Open3). No CRuby gems that need MRI extensions unless
  Spinel documents support.
- CI matrix suggestion:
  1. `bundle`/`ruby` unit tests on CRuby for pure modules.
  2. `spin build` (or `spinel`) compile gate on Linux amd64.
  3. Optional smoke: fake Hub + stub `mpv` script on PATH.

Document the Spinel release tag used for reproducible builds
(e.g. `2026.09.12` or newer).

## Error handling

| Case | Behaviour |
| --- | --- |
| Bad / loose config permissions | Exit non-zero at start |
| Hub unreachable | Keep last good package; retry next poll; log |
| Package empty / no entries for screen | Idle; no play |
| Missing cache file at start time | Skip clip; log; no play_event |
| mpv spawn/fail | Log; no play_event; continue schedule |
| mpv exits early | Log; wait for next schedule tick |
| Play_event POST fails | Remain in durable queue; retry with backoff |

## Testing

- **schedule:** table-driven cases for on-time, late, missing file, gap hours.
- **report:** queue persistence, dedupe, retry.
- **hub:** stub HTTP server (WEBrick or fixture replay) for config/package/events.
- **player:** replace `mpv_path` with a shell script that records argv and exits 0/1.
- **agent:** integration with stub Hub + stub mpv (no real network audio).
- **compile:** `spin build` must succeed on the supported Spinel version.

## Relationship to the video agent

| Concern | Video (`mediateca-station`) | Audio (`mediateca-audio-station`) |
| --- | --- | --- |
| Language | Go | Ruby → Spinel |
| Display | Android TV + VLC via ADB | Local mpv, `--no-video` |
| Media serve | LAN HTTP to TVs | Local filesystem path |
| Screens | Many, serial map | One pseudo-screen id |
| Hub API | v1 config, v2 package, play_events | Same |
| On-air file | MPEG-TS for video | Original audio upload |

## Out of scope

- Hub schema/UI (owned by Hub design).
- Changing Hub package JSON.
- Playing video on an audio station.
- Bundling mpv or ffmpeg into the Spinel binary.
- macOS/Windows as production targets (Linux mini-PC only for MVP).

## Approval

Design sections approved in brainstorming (2026-10-20): agent shape, API
reuse, mpv playback, errors/testing. Approach: separate Ruby/Spinel repo;
shared Hub agent contract; kill+spawn mpv per clip in MVP.
