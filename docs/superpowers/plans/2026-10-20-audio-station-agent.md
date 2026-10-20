# Audio Station Agent Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `mediateca-audio-station`, a Ruby process compiled with Spinel that plays Hub timed-playlist audio on a mini-PC via mpv for one pseudo-screen.

**Architecture:** Long-running daemon: poll Hub config + v2 package → cache media files → pure schedule → kill/spawn mpv → durable play_event queue. No ADB, no LAN HTTP media server. Hub repo is not modified by this work (Hub medium work is a separate plan).

**Tech Stack:** Ruby (CRuby for tests), [Spinel](https://github.com/matz/spinel) AOT (`spin` / `spinel`), host `mpv`, YAML config, `Net::HTTP`, `Process.spawn` / Open3 (not `IO.popen`), systemd.

**Spec:** `docs/superpowers/specs/2026-10-20-audio-station-agent-design.md` in the hub repo (`mediateca-broadcast`). Copy or submodule that file into the new repo’s `docs/` for offline reading. If a test and the spec disagree, stop and report; do not change the Hub API.

**Repository:** Create a **new** git repo. Do not add agent source trees into `mediateca-broadcast`.

```bash
mkdir -p /home/dim/Projects/MyPets/mediateca-audio-station
cd /home/dim/Projects/MyPets/mediateca-audio-station
git init
```

Every path below is relative to that directory. Prefer Spinel-safe Ruby (no `eval`, no `IO.popen`, no runtime `define_method`).

## Global Constraints

- Hub endpoints only: `GET /api/agent/v1/config`, `GET /api/agent/v2/package`, `POST /api/agent/v1/play_events`.
- Bearer token on `/api/agent/*` only; never on media downloads.
- Config file mode must not allow group/world bits (`0077`); else exit non-zero.
- Late threshold default 2s; poll default 60s.
- Play event only after successful mpv spawn; timestamp immediately before spawn.
- mpv is an external host binary (`mpv_path`).
- Target OS: Linux amd64 mini-PC.

---

## File map

| Path | Responsibility |
| --- | --- |
| `README.md` | Install Spinel build, mpv, systemd, sample config |
| `bin/mediateca-audio-station.rb` | `-config` flag, exit codes, call `Agent.run` |
| `lib/audio_station/config.rb` | YAML load + validation + mode check |
| `lib/audio_station/hub.rb` | HTTP client |
| `lib/audio_station/cache.rb` | download + prune |
| `lib/audio_station/schedule.rb` | pure timeline decisions |
| `lib/audio_station/player.rb` | mpv spawn/kill |
| `lib/audio_station/report.rb` | events queue + played set |
| `lib/audio_station/agent.rb` | wire loops |
| `test/` or `spec/` | CRuby tests (Minitest or RSpec — pick one; this plan uses Minitest for Spinel `spin test` friendliness) |
| `packaging/mediateca-audio-station.service` | systemd unit |
| `docs/design.md` | copy of Hub audio-agent design |

Disk under `cache_dir` (or sibling `state_dir` if you split; MVP: all under `cache_dir` parent `data_dir` from config):

| Path | Contents |
| --- | --- |
| `package.json` | last package body |
| `config.json` | last hub config body |
| `media/<id>` | complete file |
| `media/<id>.partial` | incomplete download |
| `events.jsonl` | queued play events |
| `played.json` | dedupe keys |

---

### Task 1: Scaffold project + Config

**Files:**
- Create: `README.md` (stub OK)
- Create: `bin/mediateca-audio-station.rb`
- Create: `lib/audio_station/config.rb`
- Create: `test/config_test.rb`
- Create: sample `testdata/config.valid.yaml`

**Interfaces:**
- Produces: `AudioStation::Config.load(path) -> Config` with readers: `hub_base_url`, `agent_token`, `cache_dir`, `screen_id`, `poll_interval`, `late_threshold`, `mpv_path`, `audio_device` (optional)

- [ ] **Step 1: Failing test — rejects world-readable config**

```ruby
# test/config_test.rb
require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../lib/audio_station/config"

class ConfigTest < Minitest::Test
  def test_rejects_world_readable_config
    Dir.mktmpdir do |dir|
      path = File.join(dir, "config.yaml")
      File.write(path, <<~YAML)
        hub_base_url: "https://hub.example"
        agent_token: "secret-token-value"
        cache_dir: "#{dir}/cache"
        screen_id: 1
      YAML
      File.chmod(0o644, path)

      assert_raises(AudioStation::Config::Error) do
        AudioStation::Config.load(path)
      end
    end
  end

  def test_loads_valid_config
    Dir.mktmpdir do |dir|
      path = File.join(dir, "config.yaml")
      File.write(path, <<~YAML)
        hub_base_url: "https://hub.example"
        agent_token: "secret-token-value"
        cache_dir: "#{dir}/cache"
        screen_id: 42
        poll_interval: 60
        late_threshold: 2
        mpv_path: "mpv"
      YAML
      File.chmod(0o600, path)

      cfg = AudioStation::Config.load(path)
      assert_equal "https://hub.example", cfg.hub_base_url
      assert_equal 42, cfg.screen_id
      assert_equal 2, cfg.late_threshold
    end
  end
end
```

- [ ] **Step 2: Run — expect FAIL**

```bash
ruby -Ilib:test test/config_test.rb
```

- [ ] **Step 3: Implement Config**

```ruby
# lib/audio_station/config.rb
require "yaml"

module AudioStation
  class Config
    class Error < StandardError; end

    ATTRS = %i[
      hub_base_url agent_token cache_dir screen_id
      poll_interval late_threshold mpv_path audio_device
    ].freeze

    attr_reader(*ATTRS)

    def self.load(path)
      raise Error, "missing config" unless File.file?(path)

      mode = File.stat(path).mode & 0o777
      raise Error, "config must not be group/world accessible" if (mode & 0o077) != 0

      raw = YAML.safe_load(File.read(path), permitted_classes: [], aliases: false)
      raise Error, "config root must be a mapping" unless raw.is_a?(Hash)

      new(raw)
    end

    def initialize(raw)
      @hub_base_url = raw.fetch("hub_base_url").to_s.sub(%r{/\z}, "")
      @agent_token = raw.fetch("agent_token").to_s
      @cache_dir = raw.fetch("cache_dir").to_s
      @screen_id = Integer(raw.fetch("screen_id"))
      @poll_interval = Integer(raw.fetch("poll_interval", 60))
      @late_threshold = Integer(raw.fetch("late_threshold", 2))
      @mpv_path = raw.fetch("mpv_path", "mpv").to_s
      @audio_device = raw["audio_device"]&.to_s

      validate!
    end

    private

    def validate!
      raise Error, "hub_base_url blank" if hub_base_url.empty?
      raise Error, "agent_token blank" if agent_token.empty?
      raise Error, "cache_dir blank" if cache_dir.empty?
      raise Error, "screen_id must be positive" unless screen_id.positive?
      raise Error, "poll_interval must be positive" unless poll_interval.positive?
      raise Error, "late_threshold must be non-negative" if late_threshold.negative?
      raise Error, "mpv_path blank" if mpv_path.empty?
    end
  end
end
```

- [ ] **Step 4: PASS + commit**

```bash
git add lib test README.md
git commit -m "$(cat <<'EOF'
feat: config load with secret file mode check

EOF
)"
```

---

### Task 2: Schedule (pure)

**Files:**
- Create: `lib/audio_station/schedule.rb`
- Create: `test/schedule_test.rb`

**Interfaces:**
- Produces: `AudioStation::Schedule.decision(entries:, screen_id:, now:, late_threshold:) -> Decision`
- `Decision` kinds: `:play` (entry), `:skip_late` (entry), `:idle`, `:skip_missing_file` handled by agent after cache check — schedule only decides which entry is due

- [ ] **Step 1: Failing tests**

```ruby
require "minitest/autorun"
require "time"
require_relative "../lib/audio_station/schedule"

class ScheduleTest < Minitest::Test
  Entry = Data.define(:screen_ids, :starts_at, :duration_seconds, :media_id)

  def test_play_when_on_time
    starts = Time.parse("2026-10-20T10:00:00Z")
    now = starts + 1
    entry = Entry.new([7], starts, 10, 19)
    d = AudioStation::Schedule.decision(
      entries: [entry], screen_id: 7, now: now, late_threshold: 2
    )
    assert_equal :play, d.action
    assert_equal entry, d.entry
  end

  def test_skip_when_late
    starts = Time.parse("2026-10-20T10:00:00Z")
    now = starts + 3
    entry = Entry.new([7], starts, 10, 19)
    d = AudioStation::Schedule.decision(
      entries: [entry], screen_id: 7, now: now, late_threshold: 2
    )
    assert_equal :skip_late, d.action
  end

  def test_idle_when_no_entry_for_screen
    starts = Time.parse("2026-10-20T10:00:00Z")
    entry = Entry.new([9], starts, 10, 19)
    d = AudioStation::Schedule.decision(
      entries: [entry], screen_id: 7, now: starts, late_threshold: 2
    )
    assert_equal :idle, d.action
  end
end
```

- [ ] **Step 2: Implement**

```ruby
module AudioStation
  module Schedule
    Decision = Data.define(:action, :entry)

    module_function

    def decision(entries:, screen_id:, now:, late_threshold:)
      mine = entries.select { |e| Array(e.screen_ids).include?(screen_id) }
      current = mine.find do |e|
        t0 = e.starts_at
        t1 = t0 + e.duration_seconds
        now >= t0 && now < t1
      end
      return Decision.new(:idle, nil) unless current

      if now - current.starts_at > late_threshold
        Decision.new(:skip_late, current)
      else
        Decision.new(:play, current)
      end
    end
  end
end
```

Map package JSON into Entry structs in Hub client (Task 3), not here.

- [ ] **Step 3: PASS + commit**

```bash
git commit -m "$(cat <<'EOF'
feat: pure schedule decisions for wall-clock clips

EOF
)"
```

---

### Task 3: Hub client

**Files:**
- Create: `lib/audio_station/hub.rb`
- Create: `test/hub_test.rb`

**Interfaces:**
- Produces: `Hub#fetch_config -> Hash`, `Hub#fetch_package -> Package`, `Hub#post_play_event(event) -> :ok|:reject|:retry`
- `Package` with `entries` (Schedule::Entry-compatible), `etag`, raw body helpers as needed

- [ ] **Step 1: Failing test with WEBrick or stub IO**

Use a local TCP server in the test that returns:

```json
{
  "version": "abc",
  "etag": "abc",
  "generated_at": "2026-10-20T12:00:00Z",
  "valid_until": "2026-10-21T12:00:00Z",
  "entries": [
    {
      "position": 1,
      "starts_at": "2026-10-20T10:00:00Z",
      "duration_seconds": 10,
      "screen_ids": [7],
      "media": { "id": 19, "url": "/rails/active_storage/blobs/redirect/x", "mime_type": "audio/mpeg" }
    }
  ]
}
```

Assert Bearer header present on package GET; assert media download helper does **not** attach Bearer when implemented in Cache.

- [ ] **Step 2: Implement with Net::HTTP**

Paths:

- `GET #{hub_base_url}/api/agent/v1/config`
- `GET #{hub_base_url}/api/agent/v2/package`
- `POST #{hub_base_url}/api/agent/v1/play_events`

Parse `starts_at` as UTC Time. Build entry objects with `screen_ids`, `starts_at`, `duration_seconds`, `media_id`, `media_url`, `mime_type`.

Mirror the video agent’s play_event JSON fields from Hub request specs in `mediateca-broadcast` (`spec/requests/api/agent/v1/play_events_spec.rb`) — copy required keys exactly (do not invent).

- [ ] **Step 3: PASS + commit**

```bash
git commit -m "$(cat <<'EOF'
feat: hub HTTP client for config, package, play events

EOF
)"
```

---

### Task 4: Cache

**Files:**
- Create: `lib/audio_station/cache.rb`
- Create: `test/cache_test.rb`

**Interfaces:**
- Produces: `Cache#path_for(media_id)`, `Cache#ensure!(media_id, url) -> path or nil`, `Cache#prune!(keep_ids)`

- [ ] **Step 1: Tests**

- Successful download writes `media/<id>` and removes `.partial`
- Failed download leaves no playable file
- `prune!` deletes ids not in `keep_ids`

- [ ] **Step 2: Implement**

Download with `Net::HTTP` **without** Authorization. Write to `.partial`, fsync, rename. Create `cache_dir/media` as needed.

- [ ] **Step 3: PASS + commit**

```bash
git commit -m "$(cat <<'EOF'
feat: media cache download and prune

EOF
)"
```

---

### Task 5: Player (mpv)

**Files:**
- Create: `lib/audio_station/player.rb`
- Create: `test/player_test.rb`
- Create: `testdata/fake_mpv` (executable script)

**Interfaces:**
- Produces: `Player#start(path) -> true|false`, `Player#stop`

- [ ] **Step 1: Fake mpv script**

```bash
#!/bin/sh
echo "$@" >> "${FAKE_MPV_LOG}"
exit 0
```

- [ ] **Step 2: Test start argv**

```ruby
def test_start_invokes_mpv_no_video
  log = File.join(Dir.tmpdir, "fake-mpv-#{Process.pid}.log")
  File.write(log, "")
  ENV["FAKE_MPV_LOG"] = log
  player = AudioStation::Player.new(mpv_path: File.expand_path("testdata/fake_mpv"), audio_device: nil)
  path = File.join(Dir.tmpdir, "clip.mp3")
  File.write(path, "x")
  assert player.start(path)
  args = File.read(log)
  assert_includes args, "--no-video"
  assert_includes args, path
ensure
  player&.stop
end
```

- [ ] **Step 3: Implement**

```ruby
module AudioStation
  class Player
    def initialize(mpv_path:, audio_device: nil)
      @mpv_path = mpv_path
      @audio_device = audio_device
      @pid = nil
    end

    def start(path)
      stop
      args = [@mpv_path, "--no-video", "--really-quiet", path]
      args.insert(1, "--audio-device=#{@audio_device}") if @audio_device && !@audio_device.empty?
      @pid = Process.spawn(*args)
      true
    rescue SystemCallError
      @pid = nil
      false
    end

    def stop
      return unless @pid

      Process.kill("TERM", @pid)
      Process.wait(@pid)
    rescue Errno::ESRCH, Errno::ECHILD
      # already gone
    ensure
      @pid = nil
    end
  end
end
```

Spinel note: use `Process.spawn` / Open3 package; do not use `IO.popen`.

- [ ] **Step 4: PASS + commit**

```bash
chmod +x testdata/fake_mpv
git commit -m "$(cat <<'EOF'
feat: mpv player start/stop via Process.spawn

EOF
)"
```

---

### Task 6: Report queue

**Files:**
- Create: `lib/audio_station/report.rb`
- Create: `test/report_test.rb`

**Interfaces:**
- Produces: `Report#enqueue(event)`, `Report#drain!(hub) -> counts`, durable `events.jsonl` + `played.json`

- [ ] **Step 1: Tests for persist across new Report instance, dedupe key `screen:media:starts_at`**
- [ ] **Step 2: Implement JSONL append + rewrite on success; map Hub POST outcomes `:ok` remove, `:reject` drop, `:retry` keep**
- [ ] **Step 3: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat: durable play event queue with dedupe

EOF
)"
```

---

### Task 7: Agent loop + CLI

**Files:**
- Create: `lib/audio_station/agent.rb`
- Create: `bin/mediateca-audio-station.rb`
- Create: `test/agent_test.rb` (stub Hub + fake mpv)

**Interfaces:**
- Produces: `AudioStation::Agent.run(config)` blocking loop; CLI exits 2 on config error

- [ ] **Step 1: Loop sketch**

```ruby
def run
  loop do
    pkg = @hub.fetch_package
    @cache.prune!(pkg.media_ids)
    pkg.each_media { |id, url| @cache.ensure!(id, absolute_url(url)) }

    decision = Schedule.decision(
      entries: pkg.entries,
      screen_id: @config.screen_id,
      now: Time.now.utc,
      late_threshold: @config.late_threshold
    )

    case decision.action
    when :play
      path = @cache.path_for(decision.entry.media_id)
      if path && File.file?(path)
        played_at = Time.now.utc
        if @player.start(path)
          @report.enqueue(build_event(decision.entry, played_at))
        end
      end
    when :skip_late
      # log once per entry key
    end

    @report.drain!(@hub)
    sleep tick_sleep # short tick (e.g. 0.5–1s), not only poll_interval; also refresh package every poll_interval
  end
end
```

Separate **poll timer** (config/package refresh) from **schedule tick** (playback decisions). Match video-agent behaviour: poll every `poll_interval`, schedule on a faster tick.

- [ ] **Step 2: CLI**

```ruby
#!/usr/bin/env ruby
require_relative "../lib/audio_station/agent"
require_relative "../lib/audio_station/config"

config_path = nil
ARGV.each_cons(2) { |a, b| config_path = b if a == "-config" }
abort "usage: mediateca-audio-station -config PATH" unless config_path

begin
  cfg = AudioStation::Config.load(config_path)
rescue AudioStation::Config::Error => e
  warn e.message
  exit 2
end

AudioStation::Agent.run(cfg)
```

- [ ] **Step 3: Integration test with stub Hub returning one entry + fake mpv — assert play_event enqueued**
- [ ] **Step 4: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat: agent loop wiring poll, cache, schedule, mpv, report

EOF
)"
```

---

### Task 8: Spinel build + systemd + README

**Files:**
- Create: `spin` project files per Spinel docs (`spin new` then move sources, or hand-write `Spin.toml` / project layout for the installed Spinel tag)
- Create: `packaging/mediateca-audio-station.service`
- Modify: `README.md`
- Create: `docs/design.md` (copy from Hub spec)

- [ ] **Step 1: Document Spinel version**

In README: exact Spinel release tag used (e.g. `2026.09.12` or newer). Install steps: `make deps && make && sudo make install` from Spinel source.

- [ ] **Step 2: Compile gate**

```bash
spin build
# or: spinel bin/mediateca-audio-station.rb -o build/mediateca-audio-station
./build/bin/mediateca-audio-station -config /path/to/config.yaml
```

Fix any Spinel refusals (replace unsupported constructs). Keep CRuby tests green.

- [ ] **Step 3: systemd unit**

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

[Install]
WantedBy=multi-user.target
```

- [ ] **Step 4: README operator sections**

1. Install mpv + chrony  
2. Create user, directories, `chmod 600` config  
3. Install binary  
4. Enable systemd  
5. Map `screen_id` to Hub audio pseudo-screen  

- [ ] **Step 5: Commit**

```bash
git commit -m "$(cat <<'EOF'
chore: Spinel build, systemd unit, operator README

EOF
)"
```

---

## Spec coverage checklist

| Spec requirement | Task |
| --- | --- |
| Config YAML + 0077 refuse | 1 |
| Pure schedule late/on-time | 2 |
| v1 config / v2 package / play_events | 3 |
| Cache + prune, no Bearer on media | 4 |
| mpv `--no-video`, kill+spawn | 5 |
| Durable play events | 6 |
| Agent wire-up | 7 |
| Spinel binary + systemd | 8 |

## Hub coupling

- Implement against a running Hub (or recorded fixtures) from `mediateca-broadcast` after Hub medium Task 7 so packages contain audio URLs.
- Do not open Hub PRs from this repo except documentation cross-links.

## Out of scope

- Hub schema/UI  
- Multiple screen_ids / multi mpv  
- Bundling mpv into the binary  
- Audio transcode on Hub  
