# whereami

A CLI tool written in Zig that taps into system-level location services to tell you where you are — natively, on macOS, Windows, and Linux.

## What it does

`whereami` calls your operating system's native location APIs directly — no HTTP requests, no API keys, no third-party services. It returns your latitude, longitude, and accuracy, and on platforms that support reverse geocoding (macOS today) it also resolves those coordinates to a human-readable address.

Output is human-readable by default, with a `--json` flag for scripting and piping into other tools.

```
$ whereami --mock=40.7128,-74.0060
Location: 40.7128, -74.0060
Accuracy: 0m

$ whereami --mock=40.7128,-74.0060 --json
{"latitude":40.7128,"longitude":-74.006,"accuracy":0,"address":null}
```

On macOS, real (non-`--mock`) runs also include an `Address:` line with the reverse-geocoded street, city, state, postal code, and country.

## Install

### Pre-built binaries

Download the latest release from [GitHub Releases](https://github.com/georgemandis/whereami/releases).

### Package managers

<!-- Homebrew (macOS/Linux): filled in once the tap exists -->
<!-- Scoop (Windows): filled in once the bucket exists -->
<!-- Chocolatey (Windows): filled in once the package is approved -->
<!-- .deb (Debian/Ubuntu): attached to each GitHub Release -->

### Build from source

See [Building from source](#building-from-source) below for instructions on compiling `whereami` yourself with the Zig toolchain.

## Usage

- `--json` — output as JSON instead of human-readable text.
- `--mock=LAT,LON` — use provided coordinates instead of location services. Useful for testing and scripting. Reverse geocoding is skipped in mock mode.
- `--help`, `-h` — show this help message.

```bash
whereami
whereami --json
whereami --mock=40.7128,-74.0060
whereami --help
```

## How it works

`whereami` is a thin wrapper over whatever location API your OS already provides. No HTTP calls, no API keys, no third-party geocoding services. If your system can tell you where you are, `whereami` will ask it. If it can't, `whereami` will tell you that.

| Platform | Backend                                | IP fallback | Reverse geocoding |
| -------- | -------------------------------------- | ----------- | ----------------- |
| macOS    | CoreLocation (Objective-C runtime)     | Yes         | Yes (CLGeocoder)  |
| Windows  | WinRT Geolocation API (COM/WinRT)      | Yes         | No                |
| Linux    | GeoClue2 over D-Bus                    | No          | No                |

**macOS:** CoreLocation is Apple's system location framework. `whereami` links against CoreLocation and Foundation, and calls into them via the Objective-C runtime (libobjc). CoreLocation has a built-in IP-based fallback when GPS/Wi-Fi positioning isn't available. Reverse geocoding uses `CLGeocoder`, which hits Apple's servers but is a first-class system API — no keys required.

**Windows:** uses the WinRT `Windows.Devices.Geolocation.Geolocator` class, activated through the WinRT runtime. Has an IP-based fallback built in — if no GPS or Wi-Fi positioning is available, it still returns a coarse location. (An earlier iteration of this project used the legacy `ILocation` COM API, but that one is sensor-only and fails on desktops and VMs without GPS hardware.)

**Linux:** GeoClue2 is a D-Bus broker — it doesn't source location itself. It delegates to whichever location provider your distro ships (historically Mozilla Location Service, though that was sunset in 2024; current providers vary by distro). `whereami` talks to GeoClue2 over libdbus-1. On a minimal or headless system with no provider configured, location will be unavailable — this is working as intended under the native-first rule. The `.desktop` file installed alongside the binary is what makes GeoClue2 recognize the application and grant it access.
