# whereami README Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Write a single `README.md` at the repo root that introduces `whereami`, documents how it works per platform, and documents usage and building from source.

**Architecture:** One net-new Markdown file (`README.md`). No code changes. Package-manager install commands are intentionally left as HTML-comment placeholders so they can be filled in later as each distribution channel comes online.

**Tech Stack:** Markdown. The README documents a Zig 0.15.2 project whose source is already in place and whose platform implementations are already complete.

**Source of truth:** `docs/superpowers/specs/2026-04-16-whereami-readme-design.md`. Every section below maps to a section in that spec. If something in this plan disagrees with the spec, the spec wins — surface the conflict and ask.

---

## Notes to the implementer

- This is a documentation task. Do not invent TDD for prose. The verification step is "read it back, run the commands in it, make sure it's accurate."
- **Do not hand-write sample output.** The spec is explicit about this: run `zig build run -- --mock=40.7128,-74.0060` (and the `--json` variant) and paste the actual output into the README. `accuracy` is an `f64` rendered via `{d}`, and the real output shape is not necessarily what you'd guess.
- Per-platform backend claims (CoreLocation, WinRT Geolocation, GeoClue2 via D-Bus) are already verified in the spec against `src/platform/*.zig` and `build.zig`. You don't need to re-verify them — just transcribe faithfully.
- Keep tone utility-first at the top, more conversational and honest about limits in the "How it works" and "Platform support" sections. The one Recurse Center mention goes in the "Why / background" section at the bottom.
- Do NOT add badges, screenshots, GIFs, a contributing guide, or a roadmap section. These are explicitly out of scope.
- Commit per section so a reviewer can step through the history if needed.

---

## File to create

- `README.md` (at repo root — `/Users/georgemandis/Projects/recurse/2026/zig-geocoding/README.md`)

---

### Task 1: Title, tagline, and "What it does" section (with captured real output)

**Files:**
- Create: `README.md`

- [ ] **Step 1: Capture real output for the example block**

Run these two commands from the repo root and save the output verbatim somewhere you can paste from:

```bash
zig build run -- --mock=40.7128,-74.0060
zig build run -- --mock=40.7128,-74.0060 --json
```

Expected: two blocks of text, the first human-readable, the second one-line JSON. Because `--mock` skips reverse geocoding, the `Address:` line will NOT appear and the JSON will include `"address":null`. That's fine — we'll note that the address line is macOS-only in the surrounding prose.

- [ ] **Step 2: Create `README.md` with the title, tagline, and "What it does" section**

Use exactly this tagline (verbatim):

> A CLI tool written in Zig that taps into system-level location services to tell you where you are — natively, on macOS, Windows, and Linux.

Then a 2–3 sentence "What it does" paragraph covering:
- Calls native OS location APIs. No HTTP, no API keys, no third-party services.
- Returns latitude, longitude, and accuracy. Reverse-geocodes to a human-readable address on platforms that support it (macOS today).
- Supports human-readable and JSON output.

Then the example block. Use the **real captured output from Step 1** inside fenced code blocks. Prefix each invocation with `$` for clarity. Add a one-line note directly under the example that an `Address:` line is included on macOS when not using `--mock`.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: add README title, tagline, and intro"
```

---

### Task 2: Install section (placeholders only, real build-from-source pointer)

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Determine the correct repo URL**

Run:

```bash
git remote -v
```

Note the `origin` URL and convert it into the browser form (e.g., `git@github.com:user/repo.git` → `https://github.com/user/repo`). The Releases URL is that base + `/releases`.

- [ ] **Step 2: Append the Install section**

Structure:

- Heading: `## Install`
- Subsection `### Pre-built binaries` — one line: "Download the latest release from [GitHub Releases](<URL from Step 1>)."
- Subsection `### Package managers` — HTML-comment placeholders, verbatim:

```markdown
<!-- Homebrew (macOS/Linux): filled in once the tap exists -->
<!-- Scoop (Windows): filled in once the bucket exists -->
<!-- Chocolatey (Windows): filled in once the package is approved -->
<!-- .deb (Debian/Ubuntu): attached to each GitHub Release -->
```

- Subsection `### Build from source` — one sentence pointing to the "Building from source" section lower in the README.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: add install section with package manager placeholders"
```

---

### Task 3: Usage section

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Append the Usage section**

Heading: `## Usage`

One subsection per flag. Copy aligns with `src/main.zig`'s `printUsage` function. Each flag gets one short bullet of explanation and one example line in a fenced code block.

- `--json` — emit JSON instead of human-readable output.
- `--mock=LAT,LON` — skip the system call and use the provided coordinates. Useful for testing and scripting. Reverse geocoding is skipped in mock mode.
- `--help`, `-h` — show usage.

Examples (command lines only, don't re-paste full output — that's already shown in Task 1):

```bash
whereami
whereami --json
whereami --mock=40.7128,-74.0060
whereami --help
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: add usage section"
```

---

### Task 4: "How it works" section (philosophy + table + per-platform paragraphs)

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Append the "How it works" section**

Heading: `## How it works`

Open with this philosophy paragraph (paraphrase the spec; don't rewrite from scratch):

> `whereami` is a thin wrapper over whatever location API your OS already provides. No HTTP calls, no API keys, no third-party geocoding services. If your system can tell you where you are, `whereami` will ask it. If it can't, `whereami` will tell you that.

Then this exact table:

```markdown
| Platform | Backend                                | IP fallback | Reverse geocoding |
| -------- | -------------------------------------- | ----------- | ----------------- |
| macOS    | CoreLocation (Objective-C runtime)     | Yes         | Yes (CLGeocoder)  |
| Windows  | WinRT Geolocation API (COM/WinRT)      | Yes         | No                |
| Linux    | GeoClue2 over D-Bus                    | No          | No                |
```

Then three paragraphs, one per platform. Keep them short (2–4 sentences each). Content per the spec:

- **macOS:** CoreLocation is Apple's system location framework. `whereami` links against CoreLocation and Foundation, and calls into them via the Objective-C runtime (libobjc). CoreLocation has a built-in IP-based fallback when GPS/Wi-Fi positioning isn't available. Reverse geocoding uses `CLGeocoder`, which hits Apple's servers but is a first-class system API — no keys required.

- **Windows:** uses the WinRT `Windows.Devices.Geolocation.Geolocator` class, activated through the WinRT runtime. Has an IP-based fallback built in — if no GPS or Wi-Fi positioning is available, it still returns a coarse location. (An earlier iteration of this project used the legacy `ILocation` COM API, but that one is sensor-only and fails on desktops and VMs without GPS hardware.)

- **Linux:** GeoClue2 is a D-Bus broker — it doesn't source location itself. It delegates to whichever location provider your distro ships (historically Mozilla Location Service, though that was sunset in 2024; current providers vary by distro). `whereami` talks to GeoClue2 over libdbus-1. On a minimal or headless system with no provider configured, location will be unavailable — this is working as intended under the native-first rule. The `.desktop` file installed alongside the binary is what makes GeoClue2 recognize the application and grant it access.

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: add how it works section"
```

---

### Task 5: Platform support and known limitations

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Append the limitations section**

Heading: `## Platform support and known limitations`

Four bullets (the Windows/Linux differentiation is important — it's a specific request from the brainstorm):

- **macOS:** fully featured — lat/lon, accuracy, reverse geocoding, IP fallback.
- **Windows:** lat/lon and accuracy only. Reverse geocoding is technically possible via `Windows.Services.Maps.MapLocationFinder.FindLocationsAtAsync`, but that API requires a per-application Bing Maps API key (`MapService.ServiceToken`) that each installation would need to register. That requirement breaks the zero-config install story, so reverse geocoding is not implemented on Windows today. The door is open if Microsoft ever relaxes the API key requirement.
- **Linux:** lat/lon and accuracy only. Reverse geocoding has no system-level equivalent on Linux — every available option requires a third-party HTTP service (Nominatim and similar), which would violate the native-first philosophy. Not planned.
- **VM / headless environments:** Linux in a minimal or headless VM often has no GeoClue2 provider and will return "location unavailable." macOS VMs typically do not expose CoreLocation at all. `--mock=LAT,LON` is provided for these environments.

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: add platform support and known limitations"
```

---

### Task 6: Building from source

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Append the build section**

Heading: `## Building from source`

Short, practical. Reads like instructions, not backstory. Content:

- Zig 0.15.2 required.
- `zig build` produces `zig-out/bin/whereami`.
- **macOS:** `zig build bundle` produces `zig-out/whereami.app`, an ad-hoc-signed `.app` bundle. Required because CoreLocation only grants permission to signed bundled apps, not raw binaries. `zig build run` automatically uses the bundled binary.
- **Linux:** requires `libdbus-1-dev` (or your distro's equivalent) at build time. The `assets/whereami.desktop` file is installed to `share/applications/` so GeoClue2 can identify the application.
- **Windows:** no extra build-time steps. WinRT is available on Windows 8 and later.

Use a small bash code block for the base command:

```bash
zig build
```

And a second for the macOS bundle:

```bash
zig build bundle
```

- [ ] **Step 2: Verify the commands actually work on this machine**

You're on macOS. Run:

```bash
rm -rf zig-out .zig-cache
zig build bundle
ls zig-out/whereami.app/Contents/MacOS/whereami
```

Expected: the last `ls` shows the binary. If the build fails, stop and surface the failure — something has regressed since the last commit and we don't want a README promising commands that don't work.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: add building from source section"
```

---

### Task 7: Why / background and License

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Append the Why/background section**

Heading: `## Why`

One short paragraph. Keep it grounded — this is the one place the Recurse Center context lives. Approximate text (rephrase lightly but keep the spirit):

> Built as a [Recurse Center](https://www.recurse.com/) project to explore native OS APIs in Zig. I wanted to see what it actually looks like to call CoreLocation from Zig, then do the same thing through COM/WinRT on Windows, then again through D-Bus on Linux — three totally different native idioms for the same concept. A blog post walking through the implementation is coming soon: `<!-- link to post once published -->`.

- [ ] **Step 2: Append the License section**

Heading: `## License`

One line:

> MIT — see [LICENSE](LICENSE).

- [ ] **Step 3: Confirm the LICENSE file actually exists**

Run:

```bash
ls LICENSE
```

Expected: the file exists. (User said they added it.) If it doesn't, stop and surface that.

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "docs: add why/background and license sections"
```

---

### Task 8: End-to-end verification of the whole README

**Files:**
- (Read-only verification of `README.md`)

- [ ] **Step 1: Re-read the README top to bottom**

Check against the spec's section list (title/tagline → what it does → install → usage → how it works → platform support → building from source → why → license). All present, in order, no duplicate headings, no placeholder artifacts from intermediate drafts.

- [ ] **Step 2: Verify every runnable command in the README actually works**

From the repo root, run each of these in order. All should succeed (or produce the expected mock output):

```bash
zig build
zig build bundle
./zig-out/bin/whereami --help
./zig-out/bin/whereami --mock=40.7128,-74.0060
./zig-out/bin/whereami --mock=40.7128,-74.0060 --json
```

Expected: `--help` prints the usage message. The two `--mock` invocations print the same shape used in the README's example block. If any command fails or produces different output than what's in the README, fix the README.

- [ ] **Step 3: Verify the intentional HTML-comment placeholders are still present**

Run:

```bash
grep -n "<!--" README.md
```

Expected: at least five comments — one per package manager placeholder in the Install section (Homebrew, Scoop, Chocolatey, .deb) plus the blog-post-link placeholder in the Why section. If any are missing, restore them so they're easy to find later.

- [ ] **Step 4: Verify no accidental bullets or sections that shouldn't be there**

Run:

```bash
grep -nE "badge|screenshot|\.gif|contributing|roadmap" -i README.md
```

Expected: no matches. These are all explicitly out of scope. If there are matches, remove them.

- [ ] **Step 5: No commit needed if nothing changed**

If Step 2 or Step 3 required a fix, commit:

```bash
git add README.md
git commit -m "docs: fix README verification issues"
```

Otherwise this task is purely a review checkpoint.

---

## Done criteria

- `README.md` exists at the repo root and covers every section in the spec, in order.
- All example output in the README is real captured output, not hand-written.
- All runnable commands in the README work on the local machine.
- All intentional placeholders (package managers, blog post) are present as HTML comments.
- No badges, screenshots, contributing guide, or roadmap.
- History shows one commit per section for easy review.
