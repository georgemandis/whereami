# whereami README Design

**Status:** Approved design — ready for implementation plan.

**Goal:** Write the project README for `whereami`, a cross-platform CLI tool written in Zig that wraps native OS location services. The README is the primary entry point for people discovering the tool on GitHub, deciding whether to install it, and understanding how it works.

**Audience:** Mixed — someone scrolling GitHub deciding whether to care, someone about to install, someone interested in the "how does this actually tap into OS APIs" story.

**Tone:** Utility-tool framing at the top so casual visitors can decide in 10 seconds, with a conversational "How it works" / "Platform support" section below that tells the native-first story honestly. One Recurse Center mention at the bottom.

---

## Output location

`/Users/georgemandis/Projects/recurse/2026/zig-geocoding/README.md`

This is a net-new file — the project does not currently have a README.

---

## Section-by-section spec

### 1. Title + tagline

```markdown
# whereami

A CLI tool written in Zig that taps into system-level location services to tell you where you are — natively, on macOS, Windows, and Linux.
```

Exact tagline above. No subtitle, no badges (badges will be added in a later pass once CI exists and points to real things).

### 2. What it does

Two to three sentences covering:
- Calls native OS location APIs (no HTTP, no API keys, no third-party services).
- Prints latitude, longitude, and accuracy; optionally reverse-geocodes to a human-readable address on platforms that support it.
- Supports human-readable and JSON output.

Followed by a minimal example block showing both invocations. The implementer MUST run `zig build run` (or the mocked equivalent, e.g. `zig build run -- --mock=40.7128,-74.0060`) during the write pass and paste the real output into the README. Do not hand-write the JSON — `accuracy` is an `f64` formatted with `{d}`, so the literal output shape depends on the runtime and could differ from what a human would guess. Shape is roughly:

```
$ whereami
Location: <lat>, <lon>
Accuracy: <n>m
Address: <street>, <city>, <state>, <postal>, <country>

$ whereami --json
{"latitude":<lat>,"longitude":<lon>,"accuracy":<n>,"address":{...}}
```

The `Address:` line should reflect that it only appears on macOS.

### 3. Install

Structured so package-manager entries can be filled in as they come online. Initial content:

- **Pre-built binaries:** "Download the latest release from [GitHub Releases]." (link points to the releases page for the repo)
- **Package managers:** HTML-comment placeholders for each (Homebrew, Scoop, Chocolatey, .deb) so the structure is visible and easy to populate later. Example:

```markdown
<!-- Homebrew (macOS/Linux): filled in once the tap exists -->
<!-- Scoop (Windows): filled in once the bucket exists -->
<!-- Chocolatey (Windows): filled in once the package is approved -->
<!-- .deb (Debian/Ubuntu): attached to each GitHub Release -->
```

- **Build from source:** one-line pointer to the "Building from source" section below.

### 4. Usage

Flags, one example per flag. Copy should align with `src/main.zig`'s `printUsage` output.

- `--json` — emit JSON instead of human-readable output
- `--mock=LAT,LON` — skip the system call and use the provided coordinates (useful for testing and scripting; reverse geocoding is skipped in mock mode)
- `--help`, `-h` — show usage

One realistic example per flag.

### 5. How it works

Short intro paragraph on the native-first philosophy:

> `whereami` is a thin wrapper over whatever location API your OS already provides. No HTTP calls, no API keys, no third-party geocoding services. If your system can tell you where you are, `whereami` will ask it. If it can't, `whereami` will tell you that.

Then a table:

| Platform | Backend                                | IP fallback | Reverse geocoding |
| -------- | -------------------------------------- | ----------- | ----------------- |
| macOS    | CoreLocation (Objective-C runtime)     | Yes         | Yes (CLGeocoder)  |
| Windows  | WinRT Geolocation API (COM/WinRT)      | Yes         | No                |
| Linux    | GeoClue2 over D-Bus                    | No          | No                |

Then one short paragraph per platform explaining what the backend actually is and any nuance. Approximate content (exact wording during implementation):

- **macOS:** CoreLocation is Apple's system location framework. `whereami` links against the CoreLocation and Foundation frameworks and calls into them via the Objective-C runtime (libobjc). CoreLocation includes a built-in IP-based fallback when GPS/Wi-Fi positioning isn't available. Reverse geocoding uses `CLGeocoder`, which hits Apple's servers but is a first-class system API — no keys required.

- **Windows:** `whereami` uses the WinRT `Windows.Devices.Geolocation.Geolocator` class, activated through the WinRT runtime (via `api-ms-win-core-winrt-l1-1-0`). The Windows implementation has an IP-based fallback built in — if no GPS or Wi-Fi positioning is available, it still returns a coarse location. (An earlier iteration of this project used the legacy `ILocation` COM API, but that one is sensor-only and fails on desktops and VMs without GPS hardware.)

- **Linux:** GeoClue2 is a D-Bus broker — it doesn't source location itself. It delegates to whichever location provider your distro ships (historically Mozilla Location Service, though that was sunset in 2024; current providers vary by distro). `whereami` talks to GeoClue2 over libdbus-1. On a minimal or headless system with no provider configured, location will be unavailable — this is working as intended under the native-first rule. The `.desktop` file installed alongside the binary is what makes GeoClue2 recognize the application and grant it access.

### 6. Platform support and known limitations

Bulleted notes, differentiating Windows from Linux per George's request:

- **macOS:** fully featured — lat/lon, accuracy, reverse geocoding, IP fallback.
- **Windows:** lat/lon and accuracy only. Reverse geocoding is technically possible via `Windows.Services.Maps.MapLocationFinder.FindLocationsAtAsync`, but that API requires a per-application Bing Maps API key (`MapService.ServiceToken`) that each installation would need to register. That requirement breaks the zero-config install story, so reverse geocoding is not implemented on Windows today. The door stays open if Microsoft ever relaxes the API key requirement.
- **Linux:** lat/lon and accuracy only. Reverse geocoding has no system-level equivalent on Linux — every available option requires a third-party HTTP service (Nominatim and similar), which would violate the native-first philosophy. Not planned.
- **VM / headless environments:** Linux in a minimal or headless VM often has no GeoClue2 provider and will return "location unavailable." macOS VMs typically do not expose CoreLocation at all. `--mock=LAT,LON` is provided for these environments.

### 7. Building from source

Prerequisites and build commands. Keep it short — details of why things work the way they do live in "How it works," not here.

- Zig 0.15.2 required.
- `zig build` — produces `zig-out/bin/whereami`.
- **macOS:** `zig build bundle` — produces `zig-out/whereami.app`, an ad-hoc-signed `.app` bundle. Required because CoreLocation only grants permission to signed bundled apps, not raw binaries. `zig build run` automatically uses the bundled binary.
- **Linux:** requires `libdbus-1-dev` (or your distro's equivalent) at build time. The `assets/whereami.desktop` file is installed to `share/applications/` so GeoClue2 can identify the application.
- **Windows:** no extra steps. WinRT is available on Windows 8 and later.

### 8. Why / background

Short paragraph, one Recurse Center mention, placeholder for the blog post link:

> Built as a [Recurse Center](https://www.recurse.com/) project to explore native OS APIs in Zig. I wanted to see what it actually looks like to call CoreLocation from Zig, then do the same thing through COM/WinRT on Windows, then again through D-Bus on Linux — three totally different native idioms for the same concept. A blog post walking through the implementation is coming soon: `<!-- link to post once published -->`.

### 9. License

One line:

> MIT — see [LICENSE](LICENSE).

---

## Explicitly out of scope for this README pass

- Badges (build status, latest release, license) — added in a later pass after CI exists.
- Screenshots or terminal recordings — the output is two lines of text; not worth a GIF.
- Package-manager install instructions with real commands — placeholders only for now; filled in as each channel comes online.
- Contributing guide / code of conduct — separate files, separate effort.
- Roadmap section — no future promises beyond what's already stated in "Platform support and known limitations."

---

## Open placeholders that will be filled in later

The README intentionally leaves these as HTML comments so they're easy to find and fill in:

- Homebrew install command (after the `homebrew-tap` repo exists)
- Scoop install command (after the Scoop bucket repo exists)
- Chocolatey install command (after community.chocolatey.org approval)
- `.deb` install instructions (after the first release includes a `.deb` artifact)
- Blog post link (after the Recurse Center writeup goes live)

---

## Success criteria

- A stranger hitting the repo on GitHub can, within 30 seconds, understand what the tool does and whether they want it.
- Someone who wants to install has a clear path (even if, for v1, that path is "download from Releases" or "build from source").
- Someone curious about the native-first claim can read "How it works" and come away understanding that macOS uses CoreLocation via Objective-C, Windows uses WinRT, and Linux uses GeoClue2 over D-Bus — and why Linux's capabilities are narrower.
- The honest limitations (Windows Bing-key tradeoff, Linux reverse-geocoding ruled out, VM caveats) are stated plainly rather than hidden.
- No promises the code doesn't keep.
