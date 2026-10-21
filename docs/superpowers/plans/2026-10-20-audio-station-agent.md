# Audio Station Agent Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `mediateca-audio-station`, a Go process that plays a Hub timed playlist on one pseudo-screen by spawning host `mpv` against cached audio files.

**Architecture:** One systemd daemon on a Linux mini-PC polls the existing Broadcast Hub, stores the timed v2 package, downloads media to `data_dir/media`, and starts or stops `mpv --no-video`. Wall-clock `starts_at` uses the same timeline rules as `mediateca-station`. The hub repository is not modified. The Ruby/Spinel tree in `mediateca-audio-station-ruby` is an archive and is not extended.

**Tech Stack:** Go 1.22+, `gopkg.in/yaml.v3`, standard-library HTTP, host `mpv` (tests use a fake spawner). `CGO_ENABLED=0`.

**Spec:** `docs/superpowers/specs/2026-10-20-audio-station-agent-design.md` in the hub repo (`mediateca-broadcast`). Copy that file into this repo’s `docs/superpowers/specs/` when the README task lands. If a test and the spec disagree, stop and report it; do not change the hub.

**Repository:** `/home/dim/Projects/MyPets/mediateca-audio-station` (module `mediateca-audio-station`). Do not add Go files to `mediateca-broadcast`. Do not commit into `mediateca-audio-station-ruby`.

Every path below is relative to `mediateca-audio-station`. Run `gofmt -w` on every Go file you write before running tests.

## Global Constraints

- Hub endpoints only: `GET /api/agent/v1/config`, `GET /api/agent/v2/package`, `POST /api/agent/v1/play_events`.
- Bearer token on `/api/agent/*` only; never on media downloads; strip `Authorization` on redirects; at most five redirects.
- Config file mode must not allow group/world bits (`0077`); else exit non-zero. Also exit non-zero when `mpv_path` cannot be resolved.
- Late threshold default `2s`; poll default `1m`. Both are Go durations.
- Play event only after a successful mpv spawn; `started_at` is sampled immediately before spawn.
- Played key is `screen_id:media_id:starts_at` using the package RFC3339 string.
- mpv is an external host binary. Argument vector, not a shell.
- One configured `screen_id`. No LAN HTTP server. No ADB.
- Target OS: Linux amd64 mini-PC. Tests pass without mpv.
- Never log `agent_token` or the `Authorization` header.
- Schedule rules match `mediateca-station` `internal/schedule` (late window, conflict by smaller `position`, 1s join, missing file waits inside the window).

---

## File map

| Path | Responsibility |
| --- | --- |
| `go.mod` | Module `mediateca-audio-station`. |
| `internal/fsutil/atomic.go` | Temp-file plus rename writes. |
| `internal/config/config.go` | YAML load and validation. |
| `internal/hub/client.go` | Config, v2 package, one play event. |
| `internal/schedule/timeline.go` | Pure timeline decisions. No hub, player, or disk. |
| `internal/report/queue.go` | `events.jsonl`, `played.json`, HTTP outcome table. |
| `internal/player/mpv.go` | Spawn and signal mpv. |
| `internal/cache/cache.go` | Download `media.url`, sidecars, delete unreferenced ids. |
| `internal/agent/agent.go` | Poll, tick, drain. |
| `cmd/audio-station/main.go` | `-config` flag and process exit. |
| `.github/workflows/ci.yml` | gofmt, vet, golangci-lint, govulncheck, build, race test. |
| `.golangci.yml` | Same linter set as `mediateca-station`. |
| `packaging/mediateca-audio-station.service` | systemd unit. |
| `README.md` | Operator install for the mini-PC. |

Disk layout under `data_dir`:

| Path | Contents |
| --- | --- |
| `config.json` | Last hub config HTTP 200 body. |
| `package.json` | Last hub package HTTP 200 body. |
| `package.etagheader` | Raw `ETag` response header, sent back as `If-None-Match`. |
| `media/<id>` | Complete file. |
| `media/<id>.url` | Package `media.url` that produced the file. |
| `media/<id>.mime` | MIME type. |
| `media/<id>.partial` | Incomplete download. Never played. |
| `events.jsonl` | Queued play events. |
| `played.json` | JSON array of `screen:media:starts_at` keys. |

---

### Task 1: Module and atomic writes

**Files:**
- Create: `go.mod`
- Create: `internal/fsutil/atomic.go`
- Create: `internal/fsutil/atomic_test.go`

**Interfaces:**
- Produces: `fsutil.WriteAtomic(path string, data []byte) error`. Creates parent dirs `0700`, writes a temp file in that dir, mode `0600`, fsync, rename. Later tasks store JSON with this function.

- [ ] **Step 1: Create the module**

```bash
cd /home/dim/Projects/MyPets/mediateca-audio-station
go mod init mediateca-audio-station
```

Expected: `go.mod` contains `module mediateca-audio-station`. If the `go` line is older than `1.22`, set it to `go 1.22`.

- [ ] **Step 2: Write the failing test**

`internal/fsutil/atomic_test.go`

```go
package fsutil

import (
	"os"
	"path/filepath"
	"testing"
)

func TestWriteAtomicReplacesAndLeavesNoTemp(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "nested", "package.json")
	if err := WriteAtomic(path, []byte("one")); err != nil {
		t.Fatal(err)
	}
	if err := WriteAtomic(path, []byte("two")); err != nil {
		t.Fatal(err)
	}
	got, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if string(got) != "two" {
		t.Fatalf("got %q", got)
	}
	entries, err := os.ReadDir(filepath.Dir(path))
	if err != nil {
		t.Fatal(err)
	}
	if len(entries) != 1 || entries[0].Name() != "package.json" {
		t.Fatalf("dir entries: %v", entries)
	}
	info, err := os.Stat(path)
	if err != nil {
		t.Fatal(err)
	}
	if info.Mode().Perm()&0o077 != 0 {
		t.Fatalf("mode %o is group or world readable", info.Mode().Perm())
	}
}
```

- [ ] **Step 3: Run test to verify it fails**

```bash
go test ./internal/fsutil/
```

Expected: FAIL, `WriteAtomic` undefined.

- [ ] **Step 4: Write minimal implementation**

`internal/fsutil/atomic.go`

```go
package fsutil

import (
	"os"
	"path/filepath"
)

func WriteAtomic(path string, data []byte) error {
	dir := filepath.Dir(path)
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return err
	}
	f, err := os.CreateTemp(dir, filepath.Base(path)+".tmp-*")
	if err != nil {
		return err
	}
	tmp := f.Name()
	defer os.Remove(tmp)
	if _, err := f.Write(data); err != nil {
		f.Close()
		return err
	}
	if err := f.Sync(); err != nil {
		f.Close()
		return err
	}
	if err := f.Close(); err != nil {
		return err
	}
	if err := os.Chmod(tmp, 0o600); err != nil {
		return err
	}
	return os.Rename(tmp, path)
}
```

- [ ] **Step 5: Run test to verify it passes**

```bash
gofmt -w internal/fsutil/atomic.go internal/fsutil/atomic_test.go
go test ./internal/fsutil/
```

Expected: `ok mediateca-audio-station/internal/fsutil`.

- [ ] **Step 6: Commit**

```bash
git add go.mod internal/fsutil
git commit -m "$(cat <<'EOF'
feat: atomic file writes for station state

EOF
)"
```

---

### Task 2: Config file

**Files:**
- Create: `internal/config/config.go`
- Create: `internal/config/config_test.go`

**Interfaces:**
- Produces: `config.Load(path string) (config.File, error)`
- `config.File` fields: `HubBaseURL string`, `AgentToken string`, `DataDir string`, `ScreenID int`, `LateThreshold time.Duration`, `PollInterval time.Duration`, `MPVPath string`, `AudioDevice string`

- [ ] **Step 1: Write the failing test**

`internal/config/config_test.go`

```go
package config

import (
	"os"
	"path/filepath"
	"testing"
	"time"
)

func writeConfig(t *testing.T, body string, mode os.FileMode) string {
	t.Helper()
	dir := t.TempDir()
	path := filepath.Join(dir, "config.yaml")
	if err := os.WriteFile(path, []byte(body), mode); err != nil {
		t.Fatal(err)
	}
	return path
}

func TestRejectsGroupReadableConfig(t *testing.T) {
	mpv := filepath.Join(t.TempDir(), "mpv")
	if err := os.WriteFile(mpv, []byte("#!/bin/sh\n"), 0o700); err != nil {
		t.Fatal(err)
	}
	path := writeConfig(t, `
hub_base_url: "https://hub.example"
agent_token: "secret-token-value"
data_dir: "/var/lib/mediateca-audio-station"
screen_id: 42
mpv_path: "`+mpv+`"
`, 0o640)
	if _, err := Load(path); err == nil {
		t.Fatal("expected error")
	}
}

func TestLoadsDefaults(t *testing.T) {
	mpv := filepath.Join(t.TempDir(), "mpv")
	if err := os.WriteFile(mpv, []byte("#!/bin/sh\n"), 0o700); err != nil {
		t.Fatal(err)
	}
	path := writeConfig(t, `
hub_base_url: "https://hub.example/"
agent_token: "secret-token-value"
data_dir: "/var/lib/mediateca-audio-station"
screen_id: 42
mpv_path: "`+mpv+`"
audio_device: "alsa/default"
`, 0o600)
	cfg, err := Load(path)
	if err != nil {
		t.Fatal(err)
	}
	if cfg.HubBaseURL != "https://hub.example" {
		t.Fatalf("base %q", cfg.HubBaseURL)
	}
	if cfg.ScreenID != 42 || cfg.LateThreshold != 2*time.Second || cfg.PollInterval != time.Minute {
		t.Fatalf("%+v", cfg)
	}
	if cfg.MPVPath != mpv || cfg.AudioDevice != "alsa/default" {
		t.Fatalf("%+v", cfg)
	}
}

func TestRejectsMissingMPV(t *testing.T) {
	path := writeConfig(t, `
hub_base_url: "https://hub.example"
agent_token: "secret-token-value"
data_dir: "/var/lib/mediateca-audio-station"
screen_id: 42
mpv_path: "mpv-does-not-exist-audio-station"
`, 0o600)
	if _, err := Load(path); err == nil {
		t.Fatal("expected missing mpv error")
	}
}

func TestRejectsPathOnHubURL(t *testing.T) {
	mpv := filepath.Join(t.TempDir(), "mpv")
	if err := os.WriteFile(mpv, []byte("#!/bin/sh\n"), 0o700); err != nil {
		t.Fatal(err)
	}
	path := writeConfig(t, `
hub_base_url: "https://hub.example/api"
agent_token: "secret-token-value"
data_dir: "/var/lib/mediateca-audio-station"
screen_id: 42
mpv_path: "`+mpv+`"
`, 0o600)
	if _, err := Load(path); err == nil {
		t.Fatal("expected path error")
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
go test ./internal/config/
```

Expected: FAIL, package `config` does not exist.

- [ ] **Step 3: Write minimal implementation**

`internal/config/config.go`

```go
package config

import (
	"fmt"
	"os"
	"os/exec"
	"strings"
	"time"

	"gopkg.in/yaml.v3"
)

type File struct {
	HubBaseURL    string
	AgentToken    string
	DataDir       string
	ScreenID      int
	LateThreshold time.Duration
	PollInterval  time.Duration
	MPVPath       string
	AudioDevice   string
}

type fileYAML struct {
	HubBaseURL    string `yaml:"hub_base_url"`
	AgentToken    string `yaml:"agent_token"`
	DataDir       string `yaml:"data_dir"`
	ScreenID      int    `yaml:"screen_id"`
	LateThreshold string `yaml:"late_threshold"`
	PollInterval  string `yaml:"poll_interval"`
	MPVPath       string `yaml:"mpv_path"`
	AudioDevice   string `yaml:"audio_device"`
}

func Load(path string) (File, error) {
	info, err := os.Stat(path)
	if err != nil {
		return File{}, err
	}
	if info.Mode().Perm()&0o077 != 0 {
		return File{}, fmt.Errorf("config %s is group or world readable", path)
	}
	raw, err := os.ReadFile(path)
	if err != nil {
		return File{}, err
	}
	var doc fileYAML
	if err := yaml.Unmarshal(raw, &doc); err != nil {
		return File{}, err
	}
	cfg := File{
		HubBaseURL:    strings.TrimRight(doc.HubBaseURL, "/"),
		AgentToken:    doc.AgentToken,
		DataDir:       doc.DataDir,
		ScreenID:      doc.ScreenID,
		LateThreshold: 2 * time.Second,
		PollInterval:  time.Minute,
		MPVPath:       doc.MPVPath,
		AudioDevice:   doc.AudioDevice,
	}
	if cfg.MPVPath == "" {
		cfg.MPVPath = "mpv"
	}
	if doc.LateThreshold != "" {
		parsed, err := time.ParseDuration(doc.LateThreshold)
		if err != nil {
			return File{}, fmt.Errorf("late_threshold: %w", err)
		}
		cfg.LateThreshold = parsed
	}
	if doc.PollInterval != "" {
		parsed, err := time.ParseDuration(doc.PollInterval)
		if err != nil {
			return File{}, fmt.Errorf("poll_interval: %w", err)
		}
		cfg.PollInterval = parsed
	}
	if err := cfg.validate(); err != nil {
		return File{}, err
	}
	return cfg, nil
}

func (f File) validate() error {
	if f.HubBaseURL == "" || !(strings.HasPrefix(f.HubBaseURL, "http://") || strings.HasPrefix(f.HubBaseURL, "https://")) {
		return fmt.Errorf("hub_base_url is invalid")
	}
	rest := strings.TrimPrefix(strings.TrimPrefix(f.HubBaseURL, "https://"), "http://")
	if rest == "" || strings.Contains(rest, "/") {
		return fmt.Errorf("hub_base_url must not include a path")
	}
	if f.AgentToken == "" {
		return fmt.Errorf("agent_token is required")
	}
	if f.DataDir == "" {
		return fmt.Errorf("data_dir is required")
	}
	if f.ScreenID <= 0 {
		return fmt.Errorf("screen_id must be positive")
	}
	if f.PollInterval <= 0 {
		return fmt.Errorf("poll_interval must be positive")
	}
	if f.LateThreshold < 0 {
		return fmt.Errorf("late_threshold must be non-negative")
	}
	if strings.Contains(f.MPVPath, "/") {
		if _, err := os.Stat(f.MPVPath); err != nil {
			return fmt.Errorf("mpv_path: %w", err)
		}
		return nil
	}
	if _, err := exec.LookPath(f.MPVPath); err != nil {
		return fmt.Errorf("mpv_path: %w", err)
	}
	return nil
}
```

- [ ] **Step 4: Fetch the YAML module and run tests**

```bash
gofmt -w internal/config/config.go internal/config/config_test.go
go get gopkg.in/yaml.v3@v3.0.1
go test ./internal/config/
```

Expected: `ok mediateca-audio-station/internal/config`.

- [ ] **Step 5: Commit**

```bash
git add go.mod go.sum internal/config
git commit -m "$(cat <<'EOF'
feat: load audio station config and refuse loose permissions

EOF
)"
```

---

### Task 3: Hub client

**Files:**
- Create: `internal/hub/client.go`
- Create: `internal/hub/client_test.go`

**Interfaces:**
- Consumes: nothing from earlier tasks except the module path.
- Produces:
  - `hub.New(baseURL, token string) *hub.Client`
  - `(*Client).FetchConfig(ctx) (Config, error)` — `ErrUnauthorized` on 401
  - `(*Client).FetchPackage(ctx, ifNoneMatch string) (Package, notModified bool, error)` — `Package.HeaderETag` is the raw `ETag` header
  - `(*Client).PostPlayEvent(ctx, screenID, mediaID int, startedAt time.Time) (status int, body string, error)`
  - Types `Config`, `Screen`, `Package`, `Entry`, `Media` with the JSON tags in the spec

- [ ] **Step 1: Write the failing test**

`internal/hub/client_test.go`

```go
package hub

import (
	"context"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestFetchPackageSendsBearerAndStoresETag(t *testing.T) {
	var gotAuth, gotNone string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotAuth = r.Header.Get("Authorization")
		gotNone = r.Header.Get("If-None-Match")
		if r.URL.Path != "/api/agent/v2/package" {
			t.Errorf("path %s", r.URL.Path)
		}
		w.Header().Set("ETag", `"abc"`)
		w.WriteHeader(http.StatusOK)
		_, _ = io.WriteString(w, `{"version":"abc","etag":"abc","entries":[{"position":1,"starts_at":"2026-10-20T10:00:00Z","duration_seconds":10,"screen_ids":[42],"media":{"id":19,"url":"/clip.mp3","mime_type":"audio/mpeg"}}]}`)
	}))
	defer srv.Close()

	pkg, notMod, err := New(srv.URL, "tok").FetchPackage(context.Background(), `"prev"`)
	if err != nil || notMod {
		t.Fatal(err, notMod)
	}
	if gotAuth != "Bearer tok" || gotNone != `"prev"` {
		t.Fatalf("auth %q none %q", gotAuth, gotNone)
	}
	if pkg.HeaderETag != `"abc"` || len(pkg.Entries) != 1 || pkg.Entries[0].Media.ID != 19 {
		t.Fatalf("%+v", pkg)
	}
}

func TestFetchPackageNotModified(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusNotModified)
	}))
	defer srv.Close()
	_, notMod, err := New(srv.URL, "tok").FetchPackage(context.Background(), `"abc"`)
	if err != nil || !notMod {
		t.Fatal(err, notMod)
	}
}

func TestPostPlayEventBody(t *testing.T) {
	var body string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/api/agent/v1/play_events" || r.Method != http.MethodPost {
			t.Errorf("path %s method %s", r.URL.Path, r.Method)
		}
		raw, _ := io.ReadAll(r.Body)
		body = string(raw)
		w.WriteHeader(http.StatusCreated)
		_, _ = io.WriteString(w, `{"play_log_ids":[101]}`)
	}))
	defer srv.Close()
	started := time.Date(2026, 9, 2, 2, 0, 1, 0, time.UTC)
	status, resp, err := New(srv.URL, "tok").PostPlayEvent(context.Background(), 42, 19, started)
	if err != nil || status != 201 {
		t.Fatal(err, status, resp)
	}
	if !strings.Contains(body, `"screen_id":42`) || !strings.Contains(body, `"media_asset_id":19`) || !strings.Contains(body, `"started_at":"2026-09-02T02:00:01Z"`) {
		t.Fatalf("body %s", body)
	}
}

func TestUnauthorized(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusUnauthorized)
		_, _ = io.WriteString(w, `{"error":"unauthorized"}`)
	}))
	defer srv.Close()
	_, err := New(srv.URL, "tok").FetchConfig(context.Background())
	if err != ErrUnauthorized {
		t.Fatal(err)
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
go test ./internal/hub/
```

Expected: FAIL, package `hub` does not exist.

- [ ] **Step 3: Write minimal implementation**

`internal/hub/client.go`

```go
package hub

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strings"
	"time"
)

var ErrUnauthorized = errors.New("unauthorized")

type Screen struct {
	ID          int    `json:"id"`
	Name        string `json:"name"`
	Orientation string `json:"orientation"`
}

type Config struct {
	StationID         int      `json:"station_id"`
	OfflineCacheHours int      `json:"offline_cache_hours"`
	Screens           []Screen `json:"screens"`
}

type Media struct {
	ID       int    `json:"id"`
	URL      string `json:"url"`
	MimeType string `json:"mime_type"`
}

type Entry struct {
	Position        int     `json:"position"`
	StartsAt        *string `json:"starts_at"`
	DurationSeconds int     `json:"duration_seconds"`
	ScreenIDs       []int   `json:"screen_ids"`
	Media           Media   `json:"media"`
}

type Package struct {
	Version    string  `json:"version"`
	ETag       string  `json:"etag"`
	Entries    []Entry `json:"entries"`
	HeaderETag string  `json:"-"`
}

type Client struct {
	BaseURL string
	Token   string
	HTTP    *http.Client
}

func New(baseURL, token string) *Client {
	return &Client{
		BaseURL: strings.TrimRight(baseURL, "/"),
		Token:   token,
		HTTP:    &http.Client{Timeout: 30 * time.Second},
	}
}

func (c *Client) FetchConfig(ctx context.Context) (Config, error) {
	resp, err := c.do(ctx, http.MethodGet, "/api/agent/v1/config", "", nil)
	if err != nil {
		return Config{}, err
	}
	defer resp.Body.Close()
	if resp.StatusCode == http.StatusUnauthorized {
		return Config{}, ErrUnauthorized
	}
	if resp.StatusCode != http.StatusOK {
		return Config{}, errStatus(resp.StatusCode)
	}
	var cfg Config
	if err := json.NewDecoder(resp.Body).Decode(&cfg); err != nil {
		return Config{}, err
	}
	return cfg, nil
}

func (c *Client) FetchPackage(ctx context.Context, ifNoneMatch string) (Package, bool, error) {
	resp, err := c.do(ctx, http.MethodGet, "/api/agent/v2/package", ifNoneMatch, nil)
	if err != nil {
		return Package{}, false, err
	}
	defer resp.Body.Close()
	if resp.StatusCode == http.StatusUnauthorized {
		return Package{}, false, ErrUnauthorized
	}
	if resp.StatusCode == http.StatusNotModified {
		return Package{}, true, nil
	}
	if resp.StatusCode != http.StatusOK {
		return Package{}, false, errStatus(resp.StatusCode)
	}
	var pkg Package
	if err := json.NewDecoder(resp.Body).Decode(&pkg); err != nil {
		return Package{}, false, err
	}
	pkg.HeaderETag = resp.Header.Get("ETag")
	return pkg, false, nil
}

func (c *Client) PostPlayEvent(ctx context.Context, screenID, mediaID int, startedAt time.Time) (int, string, error) {
	payload := map[string]any{
		"events": []map[string]any{{
			"screen_id":      screenID,
			"media_asset_id": mediaID,
			"started_at":     startedAt.UTC().Format(time.RFC3339),
		}},
	}
	raw, err := json.Marshal(payload)
	if err != nil {
		return 0, "", err
	}
	resp, err := c.do(ctx, http.MethodPost, "/api/agent/v1/play_events", "", raw)
	if err != nil {
		return 0, "", err
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return resp.StatusCode, "", err
	}
	return resp.StatusCode, string(body), nil
}

func (c *Client) do(ctx context.Context, method, path, ifNoneMatch string, body []byte) (*http.Response, error) {
	var reader io.Reader
	if body != nil {
		reader = bytes.NewReader(body)
	}
	req, err := http.NewRequestWithContext(ctx, method, c.BaseURL+path, reader)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Authorization", "Bearer "+c.Token)
	req.Header.Set("Accept", "application/json")
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	if ifNoneMatch != "" {
		req.Header.Set("If-None-Match", ifNoneMatch)
	}
	return c.HTTP.Do(req)
}

type statusError struct{ code int }

func (e statusError) Error() string { return "hub status" }

func errStatus(code int) error { return statusError{code: code} }
```

- [ ] **Step 4: Run test to verify it passes**

```bash
gofmt -w internal/hub/client.go internal/hub/client_test.go
go test ./internal/hub/
```

Expected: `ok mediateca-audio-station/internal/hub`.

- [ ] **Step 5: Commit**

```bash
git add internal/hub
git commit -m "$(cat <<'EOF'
feat: hub client for config, package, and play events

EOF
)"
```

---

### Task 4: Schedule

**Files:**
- Create: `internal/schedule/timeline.go`
- Create: `internal/schedule/timeline_test.go`

**Interfaces:**
- Produces the same API as `mediateca-station/internal/schedule`:
  - `ParseEntry(startsAt *string, durationSeconds int, screenIDs []int, mediaID int, rawURL, mime string, position int) (Entry, error)`
  - `Commands(now time.Time, late time.Duration, screenID int, entries []Entry, played PlayedFunc, ready ReadyFunc, onScreen *Key) []Command`
  - `WakeAt(now time.Time, late time.Duration, screenID int, entries []Entry, played PlayedFunc, ready ReadyFunc) time.Time`
  - `EntryKey(screenID int, entry Entry) Key`
  - `KindStart`, `KindStop`, `KindSkip`
- This package imports only the standard library.

Copy `timeline.go` and `timeline_test.go` from `mediateca-station` at the versions below. Do not import that module. Change the test MIME string only if you want; behavior must stay identical. The audio agent calls `Commands` for its single `screen_id`.

- [ ] **Step 1: Write the failing test**

`internal/schedule/timeline_test.go` — paste the video agent's file unchanged (`package schedule`, helpers `entry`, `nonePlayed`, `alwaysReady`, `neverReady`, `kinds`, and tests `TestParseEntryRejectsIncomplete`, `TestStartAtExactAndAtThreshold`, `TestSkipOneNanosecondPastThreshold`, `TestMissingFileWaitsInsideWindowAndSkipsAfter`, `TestOtherScreenNeverStarts`, `TestConflictPlaysSmallerPosition`, `TestTightJoinDoesNotStop`, `TestGapForceStops`, `TestEmptyPackageStops`, `TestSameCoveringKeyDoesNotRestart`, `TestDifferentCoveringKeyStops`, `TestWakeRetriesUnplayedClipInsideWindow`). Source of record: `mediateca-station/internal/schedule/timeline_test.go`.

- [ ] **Step 2: Run test to verify it fails**

```bash
go test ./internal/schedule/
```

Expected: FAIL, `Commands` undefined.

- [ ] **Step 3: Write the implementation**

`internal/schedule/timeline.go` — paste `mediateca-station/internal/schedule/timeline.go` unchanged (`Entry`, `Key`, `Kind`, `Command`, `Commands`, `WakeAt`, `startOrSkip`, `holdForJoin`, `split`, `coveringEntry`). A conflict loser is skipped. A file that is not ready inside the late window returns no command. One nanosecond past `starts_at+late` is `KindSkip` reason `late`, or `missing_file` when the file is also not ready. A gap longer than 1s between clips emits `KindStop` before the next start. A join of `end` to the next `starts_at` within 1s does not emit `KindStop`.

- [ ] **Step 4: Run test to verify it passes**

```bash
gofmt -w internal/schedule/timeline.go internal/schedule/timeline_test.go
go test ./internal/schedule/
```

Expected: `ok mediateca-audio-station/internal/schedule`.

- [ ] **Step 5: Commit**

```bash
git add internal/schedule
git commit -m "$(cat <<'EOF'
feat: wall-clock timeline shared with the video agent

EOF
)"
```

---

### Task 5: Play-event queue

**Files:**
- Create: `internal/report/queue.go`
- Create: `internal/report/queue_test.go`

**Interfaces:**
- Consumes: `fsutil.WriteAtomic`
- Produces:
  - `report.Open(dir string) (*Queue, error)`
  - `(*Queue).Played(key string) bool`
  - `(*Queue).Enqueue(ev Event, playedKey string) error`
  - `(*Queue).Peek() (Event, bool, error)`
  - `(*Queue).RemoveFirst() error`
  - `report.OutcomeFor(status int, netErr bool) Outcome` with `OutcomeRetry`, `OutcomeRemove` (201), `OutcomeDrop` (404, 422), `OutcomePause` (401)
  - `Event{ScreenID int, MediaAssetID int, StartedAt time.Time}`

- [ ] **Step 1: Write the failing test**

`internal/report/queue_test.go`

```go
package report

import (
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestEnqueueSurvivesReopen(t *testing.T) {
	dir := t.TempDir()
	q, err := Open(dir)
	if err != nil {
		t.Fatal(err)
	}
	started := time.Date(2026, 9, 2, 2, 0, 1, 0, time.UTC)
	if err := q.Enqueue(Event{ScreenID: 42, MediaAssetID: 19, StartedAt: started}, "42:19:2026-09-02T02:00:00Z"); err != nil {
		t.Fatal(err)
	}
	q2, err := Open(dir)
	if err != nil {
		t.Fatal(err)
	}
	if !q2.Played("42:19:2026-09-02T02:00:00Z") {
		t.Fatal("played key missing")
	}
	ev, ok, err := q2.Peek()
	if err != nil || !ok || ev.MediaAssetID != 19 || !ev.StartedAt.Equal(started) {
		t.Fatalf("%+v ok=%v err=%v", ev, ok, err)
	}
	if err := q2.RemoveFirst(); err != nil {
		t.Fatal(err)
	}
	_, ok, err = q2.Peek()
	if err != nil || ok {
		t.Fatal(err, ok)
	}
	if _, err := os.Stat(filepath.Join(dir, "played.json")); err != nil {
		t.Fatal(err)
	}
}

func TestOutcomeTable(t *testing.T) {
	if OutcomeFor(201, false) != OutcomeRemove || OutcomeFor(401, false) != OutcomePause {
		t.Fatal("201/401")
	}
	if OutcomeFor(404, false) != OutcomeDrop || OutcomeFor(422, false) != OutcomeDrop {
		t.Fatal("drop")
	}
	if OutcomeFor(500, false) != OutcomeRetry || OutcomeFor(0, true) != OutcomeRetry {
		t.Fatal("retry")
	}
}

```

- [ ] **Step 2: Run test to verify it fails**

```bash
go test ./internal/report/
```

Expected: FAIL, `Open` undefined.

- [ ] **Step 3: Write minimal implementation**

`internal/report/queue.go`

```go
package report

import (
	"bufio"
	"encoding/json"
	"os"
	"path/filepath"
	"sync"
	"time"

	"mediateca-audio-station/internal/fsutil"
)

type Outcome int

const (
	OutcomeRetry Outcome = iota
	OutcomeRemove
	OutcomeDrop
	OutcomePause
)

func OutcomeFor(status int, netErr bool) Outcome {
	if netErr {
		return OutcomeRetry
	}
	switch status {
	case 201:
		return OutcomeRemove
	case 401:
		return OutcomePause
	case 404, 422:
		return OutcomeDrop
	default:
		return OutcomeRetry
	}
}

type Event struct {
	ScreenID     int
	MediaAssetID int
	StartedAt    time.Time
}

type stored struct {
	ScreenID     int    `json:"screen_id"`
	MediaAssetID int    `json:"media_asset_id"`
	StartedAt    string `json:"started_at"`
	PlayedKey    string `json:"played_key"`
}

type Queue struct {
	mu      sync.Mutex
	dir     string
	played  map[string]struct{}
	events  string
	playedP string
}

func Open(dir string) (*Queue, error) {
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return nil, err
	}
	q := &Queue{
		dir:     dir,
		played:  map[string]struct{}{},
		events:  filepath.Join(dir, "events.jsonl"),
		playedP: filepath.Join(dir, "played.json"),
	}
	if raw, err := os.ReadFile(q.playedP); err == nil && len(raw) > 0 {
		var keys []string
		if err := json.Unmarshal(raw, &keys); err != nil {
			return nil, err
		}
		for _, key := range keys {
			q.played[key] = struct{}{}
		}
	}
	lines, err := q.readLines()
	if err != nil {
		return nil, err
	}
	for _, line := range lines {
		if line.PlayedKey != "" {
			q.played[line.PlayedKey] = struct{}{}
		}
	}
	return q, nil
}

func (q *Queue) Played(key string) bool {
	q.mu.Lock()
	defer q.mu.Unlock()
	_, ok := q.played[key]
	return ok
}

func (q *Queue) Enqueue(ev Event, playedKey string) error {
	q.mu.Lock()
	defer q.mu.Unlock()
	line, err := json.Marshal(stored{
		ScreenID:     ev.ScreenID,
		MediaAssetID: ev.MediaAssetID,
		StartedAt:    ev.StartedAt.UTC().Format(time.RFC3339),
		PlayedKey:    playedKey,
	})
	if err != nil {
		return err
	}
	f, err := os.OpenFile(q.events, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o600)
	if err != nil {
		return err
	}
	if _, err := f.Write(append(line, '\n')); err != nil {
		f.Close()
		return err
	}
	if err := f.Sync(); err != nil {
		f.Close()
		return err
	}
	if err := f.Close(); err != nil {
		return err
	}
	q.played[playedKey] = struct{}{}
	return q.writePlayed()
}

func (q *Queue) Peek() (Event, bool, error) {
	q.mu.Lock()
	defer q.mu.Unlock()
	lines, err := q.readLines()
	if err != nil || len(lines) == 0 {
		return Event{}, false, err
	}
	started, err := time.Parse(time.RFC3339, lines[0].StartedAt)
	if err != nil {
		return Event{}, false, err
	}
	return Event{ScreenID: lines[0].ScreenID, MediaAssetID: lines[0].MediaAssetID, StartedAt: started}, true, nil
}

func (q *Queue) RemoveFirst() error {
	q.mu.Lock()
	defer q.mu.Unlock()
	lines, err := q.readLines()
	if err != nil || len(lines) == 0 {
		return err
	}
	var buf []byte
	for _, line := range lines[1:] {
		raw, err := json.Marshal(line)
		if err != nil {
			return err
		}
		buf = append(buf, raw...)
		buf = append(buf, '\n')
	}
	return fsutil.WriteAtomic(q.events, buf)
}

func (q *Queue) writePlayed() error {
	keys := make([]string, 0, len(q.played))
	for key := range q.played {
		keys = append(keys, key)
	}
	raw, err := json.Marshal(keys)
	if err != nil {
		return err
	}
	return fsutil.WriteAtomic(q.playedP, raw)
}

func (q *Queue) readLines() ([]stored, error) {
	f, err := os.Open(q.events)
	if os.IsNotExist(err) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	defer f.Close()
	var lines []stored
	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		text := scanner.Bytes()
		if len(text) == 0 {
			continue
		}
		var line stored
		if err := json.Unmarshal(text, &line); err != nil {
			return nil, err
		}
		lines = append(lines, line)
	}
	return lines, scanner.Err()
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
gofmt -w internal/report/queue.go internal/report/queue_test.go
go test ./internal/report/
```

Expected: `ok mediateca-audio-station/internal/report`.

- [ ] **Step 5: Commit**

```bash
git add internal/report
git commit -m "$(cat <<'EOF'
feat: durable play-event queue with dedupe

EOF
)"
```

---

### Task 6: mpv player

**Files:**
- Create: `internal/player/mpv.go`
- Create: `internal/player/mpv_test.go`

**Interfaces:**
- Produces:
  - `player.New(mpvPath, audioDevice string) *Player`
  - `(*Player).Start(ctx context.Context, path string) error` — stops any current child, then spawns
  - `(*Player).Stop(ctx context.Context) error`
  - `(*Player).SetSpawner(Spawner)` for tests
  - `Spawner.Spawn(argv ...string) (Proc, error)`
  - `Proc.Signal(os.Signal) error`, `Proc.Wait() error`, `Proc.Pid() int` is not required
- Argv: `mpvPath`, `--no-video`, `--no-terminal`, `--really-quiet`, optional `--audio-device=<device>`, `--`, `path`

- [ ] **Step 1: Write the failing test**

`internal/player/mpv_test.go`

```go
package player

import (
	"context"
	"errors"
	"os"
	"syscall"
	"testing"
	"time"
)

type fakeProc struct {
	sig   os.Signal
	wait  chan struct{}
	kill  chan struct{}
}

func newFakeProc() *fakeProc {
	return &fakeProc{wait: make(chan struct{}), kill: make(chan struct{})}
}

func (p *fakeProc) Signal(s os.Signal) error {
	p.sig = s
	select {
	case <-p.kill:
	default:
		close(p.kill)
	}
	return nil
}

func (p *fakeProc) Wait() error {
	<-p.kill
	close(p.wait)
	return nil
}

type fakeSpawn struct {
	argv [][]string
	proc *fakeProc
	err  error
}

func (f *fakeSpawn) Spawn(argv ...string) (Proc, error) {
	cp := append([]string(nil), argv...)
	f.argv = append(f.argv, cp)
	if f.err != nil {
		return nil, f.err
	}
	f.proc = newFakeProc()
	return f.proc, nil
}

func TestStartArgvIncludesNoVideoAndDevice(t *testing.T) {
	sp := &fakeSpawn{}
	p := New("/usr/bin/mpv", "alsa/hdmi:CARD=PCH,DEV=0")
	p.SetSpawner(sp)
	if err := p.Start(context.Background(), "/var/lib/media/19"); err != nil {
		t.Fatal(err)
	}
	got := sp.argv[0]
	want := []string{"/usr/bin/mpv", "--no-video", "--no-terminal", "--really-quiet", "--audio-device=alsa/hdmi:CARD=PCH,DEV=0", "--", "/var/lib/media/19"}
	if len(got) != len(want) {
		t.Fatalf("%q", got)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("argv %q", got)
		}
	}
	if err := p.Stop(context.Background()); err != nil {
		t.Fatal(err)
	}
	if sp.proc.sig != syscall.SIGTERM {
		t.Fatalf("signal %v", sp.proc.sig)
	}
}

func TestStartOmitsEmptyDevice(t *testing.T) {
	sp := &fakeSpawn{}
	p := New("mpv", "")
	p.SetSpawner(sp)
	if err := p.Start(context.Background(), "/clip.mp3"); err != nil {
		t.Fatal(err)
	}
	for _, arg := range sp.argv[0] {
		if len(arg) >= 14 && arg[:14] == "--audio-device" {
			t.Fatalf("device leaked: %q", sp.argv[0])
		}
	}
	_ = p.Stop(context.Background())
}

func TestSpawnError(t *testing.T) {
	sp := &fakeSpawn{err: errors.New("missing")}
	p := New("mpv", "")
	p.SetSpawner(sp)
	if err := p.Start(context.Background(), "/clip.mp3"); err == nil {
		t.Fatal("expected error")
	}
}

func TestStopWithoutStart(t *testing.T) {
	p := New("mpv", "")
	p.SetSpawner(&fakeSpawn{})
	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()
	if err := p.Stop(ctx); err != nil {
		t.Fatal(err)
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
go test ./internal/player/
```

Expected: FAIL, `New` undefined.

- [ ] **Step 3: Write minimal implementation**

`internal/player/mpv.go`

```go
package player

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"sync"
	"syscall"
	"time"
)

type Proc interface {
	Signal(os.Signal) error
	Wait() error
}

type Spawner interface {
	Spawn(argv ...string) (Proc, error)
}

type execProc struct{ cmd *exec.Cmd }

func (p *execProc) Signal(s os.Signal) error {
	if p.cmd.Process == nil {
		return nil
	}
	return p.cmd.Process.Signal(s)
}

func (p *execProc) Wait() error { return p.cmd.Wait() }

type execSpawner struct{}

func (execSpawner) Spawn(argv ...string) (Proc, error) {
	cmd := exec.Command(argv[0], argv[1:]...)
	if err := cmd.Start(); err != nil {
		return nil, err
	}
	return &execProc{cmd: cmd}, nil
}

type running struct {
	proc Proc
	done chan struct{}
}

type Player struct {
	MPVPath     string
	AudioDevice string
	spawn       Spawner
	mu          sync.Mutex
	run         *running
}

func New(mpvPath, audioDevice string) *Player {
	return &Player{MPVPath: mpvPath, AudioDevice: audioDevice, spawn: execSpawner{}}
}

func (p *Player) SetSpawner(s Spawner) { p.spawn = s }

func (p *Player) Start(ctx context.Context, path string) error {
	p.mu.Lock()
	defer p.mu.Unlock()
	if err := p.stopLocked(ctx); err != nil {
		return err
	}
	argv := []string{p.MPVPath, "--no-video", "--no-terminal", "--really-quiet"}
	if p.AudioDevice != "" {
		argv = append(argv, "--audio-device="+p.AudioDevice)
	}
	argv = append(argv, "--", path)
	proc, err := p.spawn.Spawn(argv...)
	if err != nil {
		return err
	}
	done := make(chan struct{})
	go func() {
		_ = proc.Wait()
		close(done)
	}()
	p.run = &running{proc: proc, done: done}
	return nil
}

func (p *Player) Stop(ctx context.Context) error {
	p.mu.Lock()
	defer p.mu.Unlock()
	return p.stopLocked(ctx)
}

func (p *Player) stopLocked(ctx context.Context) error {
	if p.run == nil {
		return nil
	}
	_ = p.run.proc.Signal(syscall.SIGTERM)
	timer := time.NewTimer(2 * time.Second)
	defer timer.Stop()
	select {
	case <-p.run.done:
	case <-timer.C:
		_ = p.run.proc.Signal(syscall.SIGKILL)
		<-p.run.done
	case <-ctx.Done():
		_ = p.run.proc.Signal(syscall.SIGKILL)
		return fmt.Errorf("stop mpv: %w", ctx.Err())
	}
	p.run = nil
	return nil
}
```

`Start` must not hold the lock while a previous `Wait` needs the same lock. `stopLocked` waits on `done`, which is closed by the goroutine that calls `Wait`. That goroutine does not take `p.mu`. Holding `p.mu` in `stopLocked` is safe.

- [ ] **Step 4: Run test to verify it passes**

```bash
gofmt -w internal/player/mpv.go internal/player/mpv_test.go
go test ./internal/player/
```

Expected: `ok mediateca-audio-station/internal/player`.

- [ ] **Step 5: Commit**

```bash
git add internal/player
git commit -m "$(cat <<'EOF'
feat: spawn and stop host mpv without a shell

EOF
)"
```

---

### Task 7: Media cache

**Files:**
- Create: `internal/cache/cache.go`
- Create: `internal/cache/cache_test.go`

**Interfaces:**
- Produces:
  - `cache.New(dir string) *Cache` — `Dir` is `data_dir/media`
  - `cache.Resolve(base, raw string) (string, error)`
  - `(*Cache).Ready(id int, rawURL string) bool` — regular file plus `.url` sidecar equal to `rawURL`
  - `(*Cache).Path(id int) string`
  - `(*Cache).Reconcile(ctx, base string, items []Item) error` — at most 2 downloads; delete ids not in `items` only as part of this call
- Downloads use `http.Client` with `CheckRedirect` that deletes `Authorization` and errors after 5 hops. No bearer token is set on the request.

- [ ] **Step 1: Write the failing test**

`internal/cache/cache_test.go`

```go
package cache

import (
	"context"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"
)

func TestResolveJoinsRelativeURL(t *testing.T) {
	got, err := Resolve("https://hub.example", "/rails/active_storage/blobs/redirect/x")
	if err != nil || got != "https://hub.example/rails/active_storage/blobs/redirect/x" {
		t.Fatal(got, err)
	}
}

func TestDownloadFollowsRedirectWithoutBearer(t *testing.T) {
	var sawAuth bool
	fileSrv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Authorization") != "" {
			sawAuth = true
		}
		_, _ = w.Write([]byte("audio-bytes"))
	}))
	defer fileSrv.Close()
	hub := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Authorization") != "" {
			sawAuth = true
		}
		http.Redirect(w, r, fileSrv.URL+"/file", http.StatusFound)
	}))
	defer hub.Close()

	dir := t.TempDir()
	c := New(dir)
	err := c.Reconcile(context.Background(), hub.URL, []Item{{ID: 19, URL: "/clip.mp3", Mime: "audio/mpeg"}})
	if err != nil {
		t.Fatal(err)
	}
	if sawAuth {
		t.Fatal("bearer sent on media download")
	}
	if !c.Ready(19, "/clip.mp3") {
		t.Fatal("not ready")
	}
	body, err := os.ReadFile(c.Path(19))
	if err != nil || string(body) != "audio-bytes" {
		t.Fatalf("%q %v", body, err)
	}
}

func TestPartialIsNotReadyAndPruneKeepsUnknownOnSkippedReconcile(t *testing.T) {
	dir := t.TempDir()
	c := New(dir)
	if err := os.MkdirAll(dir, 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(c.Path(7)+".partial", []byte("x"), 0o600); err != nil {
		t.Fatal(err)
	}
	if c.Ready(7, "/old") {
		t.Fatal("partial must not be ready")
	}
}

func TestReconcileDeletesUnreferenced(t *testing.T) {
	dir := t.TempDir()
	c := New(dir)
	if err := os.MkdirAll(dir, 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(c.Path(7), []byte("old"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(c.Path(7)+".url", []byte("/old"), 0o600); err != nil {
		t.Fatal(err)
	}
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte("new"))
	}))
	defer srv.Close()
	if err := c.Reconcile(context.Background(), srv.URL, []Item{{ID: 19, URL: "/new.mp3", Mime: "audio/mpeg"}}); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(c.Path(7)); !os.IsNotExist(err) {
		t.Fatal("old id kept", err)
	}
	if !c.Ready(19, "/new.mp3") {
		t.Fatal("new id missing")
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
go test ./internal/cache/
```

Expected: FAIL, `New` undefined.

- [ ] **Step 3: Write minimal implementation**

Copy `mediateca-station/internal/cache/cache.go` into `internal/cache/cache.go` unchanged (`Item`, `New`, `Resolve`, `Ready`, `Path`, `Reconcile`, `ensure`, `download`, `deleteMissing`). The `CheckRedirect` hook deletes `Authorization`. Rename of `.partial` happens only after the body is fully read and synced. `.url` stores the package-relative `media.url`, not the resolved absolute URL. `Ready` compares that sidecar.

- [ ] **Step 4: Run test to verify it passes**

```bash
gofmt -w internal/cache/cache.go internal/cache/cache_test.go
go test ./internal/cache/
```

Expected: `ok mediateca-audio-station/internal/cache`.

- [ ] **Step 5: Commit**

```bash
git add internal/cache
git commit -m "$(cat <<'EOF'
feat: cache package media without the agent token

EOF
)"
```

---

### Task 8: Agent loop

**Files:**
- Create: `internal/agent/agent.go`
- Create: `internal/agent/agent_test.go`

**Interfaces:**
- Consumes: `config.File`, `hub.Client` methods, `cache.Cache`, `schedule.Commands` / `ParseEntry` / `EntryKey`, `report.Queue` / `OutcomeFor`, `player.Player.Start` / `Stop`
- Produces: `agent.Run(ctx context.Context, cfg config.File) error` and unexported `newAgent` used by tests

Behavior:

- `poll` writes `config.json` only after a 200 body decodes. A 401 writes nothing and sets the reporter pause. A 200 or 304 clears the pause.
- `poll` writes `package.json` and `package.etagheader` only after a 200 body decodes, then swaps the in-memory package, then `cache.Reconcile`. HTTP 304 does not reconcile and does not delete media.
- Startup loads those three files when present and can `tick` before any live poll.
- `tick` builds `[]schedule.Entry` via `ParseEntry`. A parse error is logged (`ignored_entry`) and the entry is dropped.
- If a stored hub config exists and `cfg.ScreenID` is absent from its `screens`, `tick` calls `player.Stop` and does not start. Log the mismatch once per distinct id list.
- `started_at` is `a.now()` sampled immediately before `Start`. Enqueue only when `Start` returns nil. On error, `Stop` and do not mark played.
- mpv path is `cache.Path(mediaID)`, and `cache.Ready(id, media.URL)` is the `ready` func passed to `Commands`.
- Remember the last successful `schedule.Key` in memory. A `KindStop` clears it after `Stop`.
- `drain` posts `Peek`, then `OutcomeRemove` calls `RemoveFirst`, `OutcomeDrop` calls `RemoveFirst` and logs the body, `OutcomePause` sets the pause and returns, `OutcomeRetry` returns. While paused, `drain` returns immediately.
- Logs passed a `*slog.Logger` must not contain `cfg.AgentToken`.

- [ ] **Step 1: Write the failing test**

`internal/agent/agent_test.go` must include these cases. Use a fake hub and a fake player. Seed `media/19` plus `19.url` containing `/clip.mp3` and `19.mime` containing `audio/mpeg`.

```go
func TestTickStartsOnceAndHidesToken(t *testing.T) {
	dir := t.TempDir()
	start := time.Date(2026, 9, 2, 2, 0, 0, 0, time.UTC)
	seedReady(t, dir, 19, "/clip.mp3")
	p := &fakePlayer{}
	a, buf := newTestAgent(t, testCfg(dir), &fakeHub{}, p)
	a.now = func() time.Time { return start }
	a.pkg = ptrPkg(pkgAt(start, 19, []int{42}))
	a.tick(context.Background())
	if p.starts != 1 || p.paths[0] != filepath.Join(dir, "media", "19") {
		t.Fatalf("starts %d paths %v", p.starts, p.paths)
	}
	if !a.queue.Played("42:19:2026-09-02T02:00:00Z") {
		t.Fatal("played key missing")
	}
	a.tick(context.Background())
	if p.starts != 1 {
		t.Fatalf("repeated start %d", p.starts)
	}
	if bytes.Contains(buf.Bytes(), []byte("super-secret-token")) {
		t.Fatal("token logged")
	}
}

func TestFailedStartRetriesInsideWindow(t *testing.T) {
	dir := t.TempDir()
	start := time.Date(2026, 9, 2, 2, 0, 0, 0, time.UTC)
	seedReady(t, dir, 19, "/clip.mp3")
	p := &fakePlayer{err: errors.New("spawn")}
	a, _ := newTestAgent(t, testCfg(dir), &fakeHub{}, p)
	a.now = func() time.Time { return start }
	a.pkg = ptrPkg(pkgAt(start, 19, []int{42}))
	a.tick(context.Background())
	if p.starts != 1 || a.queue.Played("42:19:2026-09-02T02:00:00Z") {
		t.Fatalf("starts %d played %v", p.starts, a.queue.Played("42:19:2026-09-02T02:00:00Z"))
	}
	p.err = nil
	a.tick(context.Background())
	if p.starts != 2 {
		t.Fatalf("starts %d", p.starts)
	}
}

func TestRestartMidClipDoesNotResume(t *testing.T) {
	dir := t.TempDir()
	start := time.Date(2026, 9, 2, 2, 0, 0, 0, time.UTC)
	seedReady(t, dir, 19, "/clip.mp3")
	p := &fakePlayer{}
	a, _ := newTestAgent(t, testCfg(dir), &fakeHub{}, p)
	a.now = func() time.Time { return start.Add(5 * time.Second) }
	a.pkg = ptrPkg(pkgAt(start, 19, []int{42}))
	a.tick(context.Background())
	if p.starts != 0 {
		t.Fatalf("resumed starts=%d", p.starts)
	}
}

func TestStoredConfigOmittingScreenDoesNotPlay(t *testing.T) {
	dir := t.TempDir()
	start := time.Date(2026, 9, 2, 2, 0, 0, 0, time.UTC)
	seedReady(t, dir, 19, "/clip.mp3")
	raw := `{"station_id":3,"screens":[{"id":7,"name":"Other","orientation":"landscape"}]}`
	if err := os.WriteFile(filepath.Join(dir, "config.json"), []byte(raw), 0o600); err != nil {
		t.Fatal(err)
	}
	p := &fakePlayer{}
	a, _ := newTestAgent(t, testCfg(dir), &fakeHub{}, p)
	a.now = func() time.Time { return start }
	a.pkg = ptrPkg(pkgAt(start, 19, []int{42}))
	a.tick(context.Background())
	if p.starts != 0 {
		t.Fatalf("played against hub config starts=%d", p.starts)
	}
}

func TestPoll401DoesNotReplacePackage(t *testing.T) {
	dir := t.TempDir()
	start := time.Date(2026, 9, 2, 2, 0, 0, 0, time.UTC)
	seedReady(t, dir, 19, "/clip.mp3")
	h := &fakeHub{cfgErr: hub.ErrUnauthorized}
	p := &fakePlayer{}
	a, _ := newTestAgent(t, testCfg(dir), h, p)
	a.pkg = ptrPkg(pkgAt(start, 19, []int{42}))
	a.poll(context.Background())
	if a.pkg.Entries[0].Media.ID != 19 {
		t.Fatal("package replaced")
	}
	if !a.paused {
		t.Fatal("reporter not paused")
	}
}
```

`testCfg` sets `ScreenID: 42`, `AgentToken: "super-secret-token"`, `DataDir: dir`, `LateThreshold: 2 * time.Second`, `HubBaseURL: "https://hub.example"`, `MPVPath: "mpv"`. `pkgAt` sets `DurationSeconds: 30`, `Media.URL: "/clip.mp3"`, `MimeType: "audio/mpeg"`, `StartsAt` RFC3339. `fakePlayer.Start` appends the path and returns `err`. `newTestAgent` builds a `slog` text handler over `bytes.Buffer` and calls `newAgent`, which must load `config.json` when the file exists.

- [ ] **Step 2: Run test to verify it fails**

```bash
go test ./internal/agent/
```

Expected: FAIL, `newAgent` undefined.

- [ ] **Step 3: Write minimal implementation**

`internal/agent/agent.go`

```go
package agent

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"os"
	"path/filepath"
	"sync"
	"time"

	"mediateca-audio-station/internal/cache"
	"mediateca-audio-station/internal/config"
	"mediateca-audio-station/internal/fsutil"
	"mediateca-audio-station/internal/hub"
	"mediateca-audio-station/internal/player"
	"mediateca-audio-station/internal/report"
	"mediateca-audio-station/internal/schedule"
)

type hubAPI interface {
	FetchConfig(ctx context.Context) (hub.Config, error)
	FetchPackage(ctx context.Context, ifNoneMatch string) (hub.Package, bool, error)
	PostPlayEvent(ctx context.Context, screenID, mediaID int, startedAt time.Time) (int, string, error)
}

type audioPlayer interface {
	Start(ctx context.Context, path string) error
	Stop(ctx context.Context) error
}

type Agent struct {
	cfg     config.File
	hub     hubAPI
	player  audioPlayer
	cache   *cache.Cache
	queue   *report.Queue
	log     *slog.Logger
	now     func() time.Time
	mu      sync.Mutex
	pkg     *hub.Package
	etag    string
	screens map[int]struct{}
	hasCfg  bool
	on      *schedule.Key
	paused  bool
	logged  string
	wake    chan struct{}
}

func Run(ctx context.Context, cfg config.File) error {
	a, err := newAgent(cfg, hub.New(cfg.HubBaseURL, cfg.AgentToken), player.New(cfg.MPVPath, cfg.AudioDevice), slog.Default())
	if err != nil {
		return err
	}
	var wg sync.WaitGroup
	wg.Add(3)
	go func() { defer wg.Done(); a.pollLoop(ctx) }()
	go func() { defer wg.Done(); a.scheduleLoop(ctx) }()
	go func() { defer wg.Done(); a.drainLoop(ctx) }()
	wg.Wait()
	return nil
}

func newAgent(cfg config.File, h hubAPI, p audioPlayer, log *slog.Logger) (*Agent, error) {
	if err := os.MkdirAll(cfg.DataDir, 0o700); err != nil {
		return nil, err
	}
	q, err := report.Open(cfg.DataDir)
	if err != nil {
		return nil, err
	}
	a := &Agent{
		cfg: cfg, hub: h, player: p, log: log, queue: q,
		cache:   cache.New(filepath.Join(cfg.DataDir, "media")),
		now:     time.Now,
		screens: map[int]struct{}{},
		wake:    make(chan struct{}, 1),
	}
	a.load()
	return a, nil
}

func (a *Agent) load() {
	if raw, err := os.ReadFile(filepath.Join(a.cfg.DataDir, "config.json")); err == nil {
		var cfg hub.Config
		if json.Unmarshal(raw, &cfg) == nil {
			a.setScreens(cfg)
		}
	}
	if raw, err := os.ReadFile(filepath.Join(a.cfg.DataDir, "package.json")); err == nil {
		var pkg hub.Package
		if json.Unmarshal(raw, &pkg) == nil {
			a.pkg = &pkg
		}
	}
	if raw, err := os.ReadFile(filepath.Join(a.cfg.DataDir, "package.etagheader")); err == nil {
		a.etag = string(raw)
	}
}

func (a *Agent) pollLoop(ctx context.Context) {
	a.poll(ctx)
	tick := time.NewTicker(a.cfg.PollInterval)
	defer tick.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-tick.C:
			a.poll(ctx)
		}
	}
}

func (a *Agent) poll(ctx context.Context) {
	cfg, err := a.hub.FetchConfig(ctx)
	if err != nil {
		if errors.Is(err, hub.ErrUnauthorized) {
			a.mu.Lock()
			a.paused = true
			a.mu.Unlock()
			a.log.Error("hub token rejected")
		} else {
			a.log.Error("hub config", "err", err.Error())
		}
		return
	}
	body, err := json.Marshal(cfg)
	if err != nil {
		return
	}
	if err := fsutil.WriteAtomic(filepath.Join(a.cfg.DataDir, "config.json"), body); err != nil {
		a.log.Error("store config", "err", err.Error())
		return
	}
	a.mu.Lock()
	a.paused = false
	a.setScreens(cfg)
	etag := a.etag
	a.mu.Unlock()
	a.log.Info("hub config", "offline_cache_hours", cfg.OfflineCacheHours, "screens", len(cfg.Screens))

	pkg, notMod, err := a.hub.FetchPackage(ctx, etag)
	if err != nil {
		if errors.Is(err, hub.ErrUnauthorized) {
			a.mu.Lock()
			a.paused = true
			a.mu.Unlock()
			a.log.Error("hub token rejected")
		} else {
			a.log.Error("hub package", "err", err.Error())
		}
		return
	}
	a.mu.Lock()
	a.paused = false
	a.mu.Unlock()
	if notMod {
		a.log.Info("hub package", "status", 304)
		return
	}
	raw, err := json.Marshal(pkg)
	if err != nil {
		return
	}
	if err := fsutil.WriteAtomic(filepath.Join(a.cfg.DataDir, "package.json"), raw); err != nil {
		a.log.Error("store package", "err", err.Error())
		return
	}
	if err := fsutil.WriteAtomic(filepath.Join(a.cfg.DataDir, "package.etagheader"), []byte(pkg.HeaderETag)); err != nil {
		a.log.Error("store etag", "err", err.Error())
		return
	}
	a.mu.Lock()
	a.pkg = &pkg
	a.etag = pkg.HeaderETag
	a.mu.Unlock()
	if err := a.cache.Reconcile(ctx, a.cfg.HubBaseURL, itemsOf(pkg)); err != nil {
		a.log.Error("cache", "err", err.Error())
	}
	a.log.Info("hub package", "status", 200, "entries", len(pkg.Entries))
	select {
	case a.wake <- struct{}{}:
	default:
	}
}

func itemsOf(pkg hub.Package) []cache.Item {
	seen := map[int]struct{}{}
	var items []cache.Item
	for _, entry := range pkg.Entries {
		if _, ok := seen[entry.Media.ID]; ok || entry.Media.ID == 0 {
			continue
		}
		seen[entry.Media.ID] = struct{}{}
		items = append(items, cache.Item{ID: entry.Media.ID, URL: entry.Media.URL, Mime: entry.Media.MimeType})
	}
	return items
}

func (a *Agent) setScreens(cfg hub.Config) {
	a.screens = map[int]struct{}{}
	ids := make([]int, 0, len(cfg.Screens))
	for _, screen := range cfg.Screens {
		a.screens[screen.ID] = struct{}{}
		ids = append(ids, screen.ID)
	}
	a.hasCfg = true
	key := fmt.Sprint(ids)
	if key == a.logged {
		return
	}
	a.logged = key
	if len(cfg.Screens) != 1 || (len(cfg.Screens) == 1 && cfg.Screens[0].ID != a.cfg.ScreenID) {
		a.log.Error("hub screen list does not match configured screen_id", "configured", a.cfg.ScreenID, "hub_ids", ids)
	}
}

func (a *Agent) allowed() bool {
	_, ok := a.screens[a.cfg.ScreenID]
	return ok
}

func (a *Agent) scheduleLoop(ctx context.Context) {
	for {
		a.tick(ctx)
		wait := a.cfg.PollInterval
		a.mu.Lock()
		if a.pkg != nil {
			wake := schedule.WakeAt(a.now(), a.cfg.LateThreshold, a.cfg.ScreenID, a.timeline(), a.queue.Played, a.cache.Ready)
			if d := wake.Sub(a.now()); d > 0 && d < wait {
				wait = d
			}
		}
		a.mu.Unlock()
		timer := time.NewTimer(wait)
		select {
		case <-ctx.Done():
			timer.Stop()
			_ = a.player.Stop(context.Background())
			return
		case <-a.wake:
			timer.Stop()
		case <-timer.C:
		}
	}
}

func (a *Agent) tick(ctx context.Context) {
	a.mu.Lock()
	defer a.mu.Unlock()
	if a.pkg == nil {
		return
	}
	if a.hasCfg && !a.allowed() {
		_ = a.player.Stop(ctx)
		a.on = nil
		return
	}
	var on *schedule.Key
	if a.on != nil {
		key := *a.on
		on = &key
	}
	cmds := schedule.Commands(a.now(), a.cfg.LateThreshold, a.cfg.ScreenID, a.timeline(), a.queue.Played, a.cache.Ready, on)
	for _, cmd := range cmds {
		switch cmd.Kind {
		case schedule.KindStop:
			if err := a.player.Stop(ctx); err != nil {
				a.log.Error("mpv stop", "err", err.Error())
			}
			a.on = nil
			a.log.Info("clip stop")
		case schedule.KindSkip:
			a.log.Info("clip skip", "reason", cmd.Reason, "media_id", cmd.Entry.Media.ID)
		case schedule.KindStart:
			path := a.cache.Path(cmd.Entry.Media.ID)
			started := a.now().UTC()
			if err := a.player.Start(ctx, path); err != nil {
				a.log.Error("mpv spawn", "err", err.Error())
				_ = a.player.Stop(ctx)
				continue
			}
			key := schedule.EntryKey(a.cfg.ScreenID, cmd.Entry)
			if err := a.queue.Enqueue(report.Event{
				ScreenID: a.cfg.ScreenID, MediaAssetID: cmd.Entry.Media.ID, StartedAt: started,
			}, key.String()); err != nil {
				a.log.Error("enqueue play event", "err", err.Error())
				continue
			}
			a.on = &key
			a.log.Info("clip start", "media_id", cmd.Entry.Media.ID)
		}
	}
}

func (a *Agent) timeline() []schedule.Entry {
	if a.pkg == nil {
		return nil
	}
	var out []schedule.Entry
	for _, entry := range a.pkg.Entries {
		parsed, err := schedule.ParseEntry(entry.StartsAt, entry.DurationSeconds, entry.ScreenIDs, entry.Media.ID, entry.Media.URL, entry.Media.MimeType, entry.Position)
		if err != nil {
			a.log.Error("ignored_entry")
			continue
		}
		out = append(out, parsed)
	}
	return out
}

func (a *Agent) drainLoop(ctx context.Context) {
	a.drain(ctx)
	tick := time.NewTicker(a.cfg.PollInterval)
	defer tick.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-tick.C:
			a.drain(ctx)
		}
	}
}

func (a *Agent) drain(ctx context.Context) {
	a.mu.Lock()
	paused := a.paused
	a.mu.Unlock()
	if paused {
		return
	}
	ev, ok, err := a.queue.Peek()
	if err != nil || !ok {
		return
	}
	status, body, postErr := a.hub.PostPlayEvent(ctx, ev.ScreenID, ev.MediaAssetID, ev.StartedAt)
	switch report.OutcomeFor(status, postErr != nil) {
	case report.OutcomeRemove:
		_ = a.queue.RemoveFirst()
	case report.OutcomeDrop:
		a.log.Error("drop play event", "status", status, "body", body)
		_ = a.queue.RemoveFirst()
	case report.OutcomePause:
		a.mu.Lock()
		a.paused = true
		a.mu.Unlock()
		a.log.Error("hub token rejected")
	default:
		a.log.Error("play event retry", "status", status)
	}
}
```

`schedule` and `report` still do not import `player` or `hub`. `cache.Reconcile` runs only after a package 200 is stored. A 401 returns before any write. `setScreens` is called with `a.mu` held from `poll` after the config file is stored, and from `load` before `Run` starts other goroutines.

There is a lock bug to avoid: `tick` holds `a.mu` and calls `a.player.Start`. That is fine. `poll` must not call `setScreens` while also expecting `tick` to take `a.mu` inside `setScreens`. `setScreens` does not lock; callers that race with `tick` hold `a.mu`. `load` runs before goroutines start.

`TestPoll401DoesNotReplacePackage` sets `a.pkg` then calls `poll`. `FetchConfig` returns `hub.ErrUnauthorized`, so `poll` returns before `FetchPackage` and before replacing `a.pkg`, and sets `a.paused`. The test reads `a.paused` without the mutex; that is acceptable in the test.

- [ ] **Step 4: Run test to verify it passes**

```bash
gofmt -w internal/agent/agent.go internal/agent/agent_test.go
go test ./internal/agent/
```

Expected: `ok mediateca-audio-station/internal/agent`.

- [ ] **Step 5: Commit**

```bash
git add internal/agent
git commit -m "$(cat <<'EOF'
feat: poll, schedule, and report loop for one audio screen

EOF
)"
```

---

### Task 9: Process entry, CI, systemd, README

**Files:**
- Create: `cmd/audio-station/main.go`
- Create: `.github/workflows/ci.yml`
- Create: `.golangci.yml`
- Create: `packaging/mediateca-audio-station.service`
- Create: `README.md`
- Create: `docs/superpowers/specs/2026-10-20-audio-station-agent-design.md` (copy of the hub spec)
- Create: `.gitignore` with `config.yaml` and the binary name `mediateca-audio-station`

**Interfaces:**
- Consumes: `config.Load`, `agent.Run`

- [ ] **Step 1: Process entry**

`cmd/audio-station/main.go`

```go
package main

import (
	"context"
	"flag"
	"log/slog"
	"os"
	"os/signal"
	"syscall"

	"mediateca-audio-station/internal/agent"
	"mediateca-audio-station/internal/config"
)

func main() {
	path := flag.String("config", "", "path to config.yaml")
	flag.Parse()
	if *path == "" {
		slog.Error("missing -config")
		os.Exit(1)
	}
	cfg, err := config.Load(*path)
	if err != nil {
		slog.Error("config", "err", err.Error())
		os.Exit(1)
	}
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()
	if err := agent.Run(ctx, cfg); err != nil && ctx.Err() == nil {
		slog.Error("audio-station", "err", err.Error())
		os.Exit(1)
	}
}
```

`agent.Run` returns nil when `ctx` is cancelled. A missing `-config` or a `config.Load` error exits 1. Playback errors stay inside `Run` and must not be returned as a process-ending error.

- [ ] **Step 2: CI**

`.golangci.yml` — copy `mediateca-station/.golangci.yml` (version 2; enable `bodyclose`, `errcheck`, `ineffassign`, `staticcheck`, `unused`; exclude `errcheck` on `_test.go`).

`.github/workflows/ci.yml` — four jobs on `ubuntu-latest`, `contents: read`, trigger `push` and `pull_request`:

- `gofmt -l .` fails when output is non-empty; `go vet ./...`; `golangci/golangci-lint-action` `v2.13.2` with `--timeout=5m`
- `go install golang.org/x/vuln/cmd/govulncheck@v1.9.0` then `govulncheck ./...`
- `go build -o /dev/null ./cmd/audio-station`
- `go test -race -count=1 ./...`

`actions/setup-go` uses `go-version-file: go.mod`.

- [ ] **Step 3: systemd unit**

`packaging/mediateca-audio-station.service` — the unit from the spec (`User=mediateca-audio`, `Restart=always`, `RestartSec=2`, `NoNewPrivileges=true`, `After=network-online.target chronyd.service`).

- [ ] **Step 4: README**

Operator page, not a hub guide. Include:

1. This binary is a client of an existing hub. It does not create playlists.
2. Build: `CGO_ENABLED=0 go build -o mediateca-audio-station ./cmd/audio-station`
3. Install `mpv` and an NTP client. Point `After=` / `Wants=` at the NTP unit the image ships (`chronyd.service`, `chrony.service`, or `systemd-timesyncd.service`). Do not start the agent before the clock has stepped.
4. User `mediateca-audio` owns `/var/lib/mediateca-audio-station` (`0700`) and `/etc/mediateca-audio-station/config.yaml` (`0600`).
5. Sample YAML from the spec (`screen_id` is the Hub pseudo-screen).
6. `journalctl -u mediateca-audio-station` and what `late`, `missing_file`, and token rejection look like.
7. Tests: `go test ./...` needs no mpv binary.

- [ ] **Step 5: Run the full suite**

```bash
gofmt -w cmd/audio-station/main.go
CGO_ENABLED=0 go build -o /tmp/mediateca-audio-station ./cmd/audio-station
go test -race -count=1 ./...
/tmp/mediateca-audio-station
```

Expected: tests pass. The binary with no flags exits 1 and logs `missing -config`.

- [ ] **Step 6: Commit**

```bash
git add cmd .github .golangci.yml packaging README.md docs .gitignore
git commit -m "$(cat <<'EOF'
chore: audio station binary, CI, and operator README

EOF
)"
```

---

## Spec coverage

| Spec requirement | Task |
| --- | --- |
| Go module, atomic state files | 1 |
| YAML config, mode `0077`, Go durations, `mpv_path` lookup, single `screen_id` | 2 |
| v1 config, v2 package ETag, play_events body, 401 | 3 |
| Late window, conflict, 1s join, missing file, empty package | 4 |
| Durable queue, 201/401/404/422 | 5 |
| mpv argv, no shell, SIGTERM, optional audio device | 6 |
| Cache, redirect without bearer, prune only on successful reconcile | 7 |
| Poll/tick/drain, no resume mid-clip, hub screen allow-list, token not logged | 8 |
| systemd, CI, README, exit on bad config | 9 |

## Out of scope

- Hub schema, cabinet, or admin changes
- Editing `mediateca-station` or `mediateca-audio-station-ruby`
- Multiple `screen_id` values, ADB, LAN HTTP, bundling mpv
- Audio transcode
