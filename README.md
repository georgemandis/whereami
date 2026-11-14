# whereami

[![Build](https://github.com/georgemandis/whereami/actions/workflows/release.yml/badge.svg)](https://github.com/georgemandis/whereami/actions/workflows/release.yml)

A CLI tool written in Zig that taps into system-level location services to tell you where you are — natively, on macOS, Windows, and Linux.

## What it does

`whereami` calls your operating system's native location APIs directly — no HTTP requests, no API keys, no third-party services. It returns your latitude, longitude, and accuracy, and on platforms that support geocoding (macOS today) it also resolves those coordinates to a human-readable address.

On macOS it works in both directions for places other than where you are, too: give it coordinates and get an address, or give it an address and get coordinates.

Output is human-readable by default, with a `--json` flag for scripting and piping into other tools.

```
$ whereami --mock=40.7128,-74.0060
Location: 40.7128, -74.0060
Accuracy: 0m

$ whereami --mock=40.7128,-74.0060 --json
{"latitude":40.7128,"longitude":-74.006,"accuracy":0,"address":null}
```

On macOS, real (non-`--mock`) runs also include an `Address:` line with the reverse-geocoded street, city, state, postal code, and country.

```
$ whereami --at=40.6892,-73.9857
Location: 40.6892, -73.9857
Address: 45 Hoyt St, New York, NY, 11201, US

$ whereami "1600 Pennsylvania Ave NW, Washington, DC"
Location: 38.8977, -77.0366
Address: 1600 Pennsylvania Ave NW, Washington, DC, 20500, US

$ whereami "1600 Pennsylvania Ave NW, Washington, DC" --json
{"latitude":38.8976635,"longitude":-77.036574,"accuracy":0,"address":{"street":"1600 Pennsylvania Ave NW","city":"Washington","state":"DC","postal_code":"20500","country":"US"}}
```

## Install

### Homebrew (macOS / Linux)

```bash
brew install georgemandis/tap/whereami
```

Or tap first, then install:

```bash
brew tap georgemandis/tap
brew install whereami
```

### Scoop (Windows)

```powershell
scoop bucket add georgemandis https://github.com/georgemandis/scoop-bucket
scoop install georgemandis/whereami
```

### Debian / Ubuntu

```bash
# Download the .deb for your architecture (amd64 or arm64)
curl -LO https://github.com/georgemandis/whereami/releases/download/v0.4.0/whereami_0.4.0_amd64.deb
sudo dpkg -i whereami_0.4.0_amd64.deb
```

### Pre-built binaries

Download the latest release from [GitHub Releases](https://github.com/georgemandis/whereami/releases). Archives are available for macOS (aarch64, x86_64), Linux (aarch64, x86_64), and Windows (x86_64).

### Build from source

See [Building from source](#building-from-source) below for instructions on compiling `whereami` yourself with the Zig toolchain.

## Usage

- `--json` — output as JSON instead of human-readable text.
- `--at=LAT,LON` — look up the address at the given coordinates (macOS). On other platforms it prints the coordinates back with no address.
- `[address]` — any non-flag arguments are treated as an address to look up the coordinates of (macOS). Quoting is optional; the words are joined with spaces. Can't be combined with `--at` or `--mock`.
- `--mock=LAT,LON` — use provided coordinates instead of location services. Useful for testing and scripting. Reverse geocoding is skipped in mock mode, so it never touches the network.
- `--version`, `-v` — show version and author info.
- `--help`, `-h` — show this help message.

```bash
whereami
whereami --json
whereami --at=40.6892,-73.9857
whereami "350 5th Ave, New York"
whereami --mock=40.7128,-74.0060
whereami --help
```

The JSON shape is the same in every mode, so an address lookup pipes into anything that already reads `whereami --json` — for example [nearme](https://github.com/georgemandis/nearme):

```bash
whereami "350 5th Ave, New York" --json | nearme coffee
```

`accuracy` is `0` for `--at` and address lookups, since nothing was measured. If an address can't be found, `whereami` exits with status 1 (and prints `{"error":"address_not_found"}` with `--json`). If `--at` coordinates have no address (open ocean, say), `address` is `null` and a warning goes to stderr.

## How it works

`whereami` is a thin wrapper over whatever location API your OS already provides. No HTTP calls, no API keys, no third-party geocoding services. If your system can tell you where you are, `whereami` will ask it. If it can't, `whereami` will tell you that.

| Platform | Backend                                | IP fallback | Geocoding (address ⇄ coordinates) |
| -------- | -------------------------------------- | ----------- | --------------------------------- |
| macOS    | CoreLocation (Objective-C runtime)     | Yes         | Yes, both directions (CLGeocoder) |
| Windows  | WinRT Geolocation API (COM/WinRT)      | Yes         | No                                |
| Linux    | GeoClue2 over D-Bus                    | No          | No                                |

**macOS:** CoreLocation is Apple's system location framework. `whereami` links against CoreLocation and Foundation, and calls into them via the Objective-C runtime (libobjc). CoreLocation has a built-in IP-based fallback when GPS/Wi-Fi positioning isn't available. Geocoding in both directions uses `CLGeocoder`, which hits Apple's servers but is a first-class system API — no keys required. Address and `--at` lookups don't need location permission, since they never ask where you are.

Apple deprecated `CLGeocoder` in macOS 26 in favor of MapKit's `MKGeocodingRequest` and `MKReverseGeocodingRequest`. `whereami` stays on `CLGeocoder` for now because it still works, it supports older macOS versions, and the MapKit replacements only return formatted address strings — they have no non-deprecated way to get the street, state, and postal code as separate fields.

**Windows:** uses the WinRT `Windows.Devices.Geolocation.Geolocator` class, activated through the WinRT runtime. Has an IP-based fallback built in — if no GPS or Wi-Fi positioning is available, it still returns a coarse location. (An earlier iteration of this project used the legacy `ILocation` COM API, but that one is sensor-only and fails on desktops and VMs without GPS hardware.)

**Linux:** GeoClue2 is a D-Bus broker — it doesn't source location itself. It delegates to whichever location provider your distro ships (historically Mozilla Location Service, though that was sunset in 2024; current providers vary by distro). `whereami` talks to GeoClue2 over libdbus-1. On a minimal or headless system with no provider configured, location will be unavailable — this is working as intended under the native-first rule. The `.desktop` file installed alongside the binary is what makes GeoClue2 recognize the application and grant it access.

## Platform support and known limitations

- **macOS:** fully featured — lat/lon, accuracy, reverse geocoding, address lookup, IP fallback.
- **Windows:** lat/lon and accuracy only; address lookups exit with an error. Reverse geocoding is technically possible via `Windows.Services.Maps.MapLocationFinder.FindLocationsAtAsync`, but that API requires a per-application Bing Maps API key (`MapService.ServiceToken`) that each installation would need to register. That requirement breaks the zero-config install story, so reverse geocoding is not implemented on Windows today. The door is open if Microsoft ever relaxes the API key requirement.
- **Linux:** lat/lon and accuracy only; address lookups exit with an error. Reverse geocoding has no system-level equivalent on Linux — every available option requires a third-party HTTP service (Nominatim and similar), which would violate the native-first philosophy. Not planned.
- **VM / headless environments:** Linux in a minimal or headless VM often has no GeoClue2 provider and will return "location unavailable." macOS VMs typically do not expose CoreLocation at all. `--mock=LAT,LON` is provided for these environments.

## Building from source

Zig 0.16.0 required.

```bash
zig build
```

`zig build` produces `zig-out/bin/whereami`.

- **macOS:** `zig build bundle` produces `zig-out/whereami.app`, an ad-hoc-signed `.app` bundle. Required because CoreLocation only grants permission to signed bundled apps, not raw binaries. `zig build run` automatically uses the bundled binary.
- **Linux:** requires `libdbus-1-dev` (or your distro's equivalent) at build time. The `assets/whereami.desktop` file is installed to `share/applications/` so GeoClue2 can identify the application.
- **Windows:** no extra build-time steps. WinRT is available on Windows 8 and later.

```bash
zig build bundle
```

## Why

Built during my time at [Recurse Center](https://www.recurse.com/) as project to explore native OS APIs in Zig. I wanted to see what it actually looks like to call CoreLocation from Zig on macOS, then do the same thing through COM/WinRT on Windows, then again through D-Bus on Linux. Three totally different native idioms for the same concept with enough coverage to be a little bit interesting.

I plan on writing a blog post walking through the implementation soon!

## License

MIT — see [LICENSE](LICENSE).
