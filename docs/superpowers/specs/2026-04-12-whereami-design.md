# whereami — Native OS Geolocation CLI & Library

## Overview

A Zig library and CLI tool that interfaces with native OS-level location services to determine the current machine's location. Returns coordinates, accuracy, and (on macOS) a reverse-geocoded human-readable address. No external network services — native OS APIs only.

Modeled after the [copycat](../../..) clipboard manager project, sharing the same architectural patterns: platform-specific backends behind a unified dispatcher, ObjC runtime bindings from pure Zig, dual library+CLI build, and eventual FFI for Bun/TypeScript.

## Scope

### In scope (this spec)

- macOS backend via CoreLocation (pure Zig, ObjC runtime calls)
- CLI tool: `whereami` prints location, `whereami --json` for machine-readable output
- `.app` bundle creation in the build step (required for macOS location permissions)
- Ad-hoc code signing
- Reverse geocoding via CLGeocoder (macOS only, native API)

### Deferred

- Windows backend (Win32 ILocation COM API)
- Linux backend (GeoClue2 via D-Bus or libgeoclue)
- IP-based geolocation fallback
- External reverse geocoding APIs for non-macOS platforms
- FFI / shared library for Bun/TypeScript (`lib.zig`)
- `--watch`, `--format`, `--timeout`, or other CLI flags beyond `--json`
- Additional CLLocation properties (altitude, speed, course, timestamp) — can be added to the `Location` struct in a future version

## Project Structure

```
whereami/
  build.zig
  src/
    location.zig          # Public API dispatcher (compile-time platform selection)
    objc.zig              # ObjC runtime bindings (extended from copycat)
    main.zig              # CLI entry point
    platform/
      macos.zig           # CoreLocation + CLGeocoder implementation
```

Future additions (not in this spec):

```
    lib.zig               # C ABI exports for FFI/Bun
    platform/
      windows.zig         # Win32 ILocation COM
      linux.zig           # GeoClue2
```

## Core API (`location.zig`)

```zig
pub const Location = struct {
    latitude: f64,
    longitude: f64,
    accuracy: f64,          // meters
};

pub const Address = struct {
    street: []const u8,
    city: []const u8,
    state: []const u8,
    postal_code: []const u8,
    country: []const u8,
};

pub const LocationError = error{
    PermissionDenied,
    LocationUnavailable,
    Timeout,
    GeocodingFailed,
    PlatformUnsupported,
};

/// Get current coordinates. Blocks until location fix or timeout.
/// The allocator is used for internal ObjC string operations (null-terminated
/// string duplication for selector names, etc.).
pub fn getLocation(allocator: Allocator, timeout_ms: u32) !Location

/// Reverse geocode coordinates to address. Returns null on platforms
/// without native geocoding support.
pub fn reverseGeocode(allocator: Allocator, lat: f64, lon: f64) !?Address

/// Free an Address returned by reverseGeocode. Each field in Address is a
/// separately heap-allocated slice. freeAddress frees each field individually.
pub fn freeAddress(allocator: Allocator, address: Address) void
```

The dispatcher uses compile-time platform selection identical to copycat's `clipboard.zig`:

```zig
const platform = switch (builtin.os.tag) {
    .macos => @import("platform/macos.zig"),
    else => @compileError("Unsupported platform. Currently supported: macOS."),
};
```

## macOS Platform Implementation (`platform/macos.zig`)

### ObjC Runtime Extensions

`objc.zig` is copied from copycat and extended with class creation APIs:

```zig
extern "objc" fn objc_allocateClassPair(superclass: Class, name: [*:0]const u8, extra_bytes: usize) ?Class;
extern "objc" fn objc_registerClassPair(cls: Class) void;
extern "objc" fn class_addMethod(cls: Class, sel: SEL, imp: *const anyopaque, types: [*:0]const u8) bool;
```

These enable dynamically creating an Objective-C delegate class at runtime — required because CoreLocation uses the delegate pattern for async location delivery.

### Delegate Class

A `WhereAmIDelegate` class is registered once (lazily, process-global) inheriting from `NSObject`. It implements three methods:

| Method | ObjC Type Encoding | Purpose |
|---|---|---|
| `locationManager:didUpdateLocations:` | `"v@:@@"` (void, self, _cmd, CLLocationManager, NSArray) | Extracts lat/lon/accuracy from the CLLocation array, writes to module-level result, signals completion via `CFRunLoopStop` |
| `locationManager:didFailWithError:` | `"v@:@@"` (void, self, _cmd, CLLocationManager, NSError) | Stores the error, signals completion |
| `locationManagerDidChangeAuthorization:` | `"v@:@"` (void, self, _cmd, CLLocationManager) | Called when authorization status changes; if authorized, calls `startUpdatingLocation`; if denied, stores `PermissionDenied` and signals completion |

### `getLocation` Flow

1. Register the delegate class (once, lazily)
2. Allocate a delegate instance
3. Create `CLLocationManager`, set its delegate
4. Check `authorizationStatus`:
   - If `.authorizedAlways`: proceed to step 5
   - If `.notDetermined`: call `requestWhenInUseAuthorization` — the authorization prompt is async; the `locationManagerDidChangeAuthorization:` delegate callback will call `startUpdatingLocation` once authorized, or store `PermissionDenied` if denied
   - If `.denied` or `.restricted`: return `PermissionDenied` immediately
5. Call `startUpdatingLocation` (skipped if waiting for authorization — the delegate callback handles it)
6. Run `CFRunLoopRunInMode(kCFRunLoopDefaultMode, timeout, false)` — pumps the run loop so CoreLocation can deliver callbacks. `kCFRunLoopDefaultMode` is obtained by externing the `kCFRunLoopDefaultMode` symbol from CoreFoundation (it is a `CFStringRef` constant).
7. Delegate callback writes result and calls `CFRunLoopStop(CFRunLoopGetCurrent())`
8. Return `Location` or appropriate error (`PermissionDenied`, `Timeout`, `LocationUnavailable`)

### `reverseGeocode` Flow

1. Create `CLGeocoder` instance
2. Create `CLLocation` from lat/lon
3. Call `reverseGeocodeLocation:completionHandler:` — this requires constructing an Objective-C block
4. Pump the run loop until completion
5. Extract fields from the returned `CLPlacemark` (street, city, state, postal code, country)
6. Return populated `Address` struct

**Block ABI:** `CLGeocoder.reverseGeocodeLocation:completionHandler:` requires an Objective-C block. There is no alternative API — the result is only delivered through the block's completion handler. The block must be constructed from Zig using the documented C ABI layout:

```zig
const BlockDescriptor = extern struct {
    reserved: c_ulong,
    size: c_ulong,
};

const BlockLiteral = extern struct {
    isa: *anyopaque,        // &_NSConcreteStackBlock (extern symbol)
    flags: c_int,           // 1 << 30 for BLOCK_HAS_SIGNATURE
    reserved: c_int,
    invoke: *const anyopaque, // fn(*BlockLiteral, ?objc.id, ?objc.id) callconv(.c) void
    descriptor: *const BlockDescriptor,
};
```

The `invoke` function pointer receives the block itself as its first argument, followed by the completion handler parameters (`NSArray<CLPlacemark> *`, `NSError *`). The block is stack-allocated and passed directly to the ObjC method via `msgSend`.

If block construction proves unworkable, reverse geocoding will be deferred — there is no polling fallback since the result is only accessible through the completion handler.

### Module-Level State and Thread Safety

```zig
var delegate_class: ?objc.Class = null;   // registered once, never freed
var result_location: ?Location = null;
var result_error: ?LocationError = null;
var completed: bool = false;
```

**Thread safety:** `getLocation` and `reverseGeocode` are **not reentrant and not thread-safe**. They use module-level state for communication between the run loop callbacks and the caller. This is acceptable because the CLI is single-threaded and calls these functions sequentially. Future FFI callers must ensure serialized access.

**Run loop requirement:** `CLLocationManager` must be used on a thread with an active run loop. The CLI's main thread satisfies this. Future library/FFI callers must ensure the same — calling from a bare background thread will silently fail.

## CLI (`main.zig`)

### Default Output

```
$ whereami
Location: 40.6892, -74.0445
Accuracy: 50m
Address: 1 Liberty Island, New York, NY 10004, US
```

The `Address` line appears only on macOS when reverse geocoding succeeds. On other platforms (future) or on geocoding failure, it is silently omitted.

### JSON Output

```
$ whereami --json
{"latitude":40.6892,"longitude":-74.0445,"accuracy":50.0,"address":{"street":"1 Liberty Island","city":"New York","state":"NY","postal_code":"10004","country":"US"}}
```

The `address` field is `null` if geocoding is unavailable or fails.

### Error Messages

- `PermissionDenied`: print instructions for enabling location in System Preferences > Privacy & Security > Location Services
- `LocationUnavailable`: suggest the machine may not have location hardware
- `Timeout`: suggest the location fix is taking too long; the default timeout is 10 seconds
- `GeocodingFailed`: note that coordinates were obtained but address lookup failed (coordinates are still printed)
- `--help` / `-h`: brief usage text

### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Location error (permission denied, unavailable, timeout) |
| 2 | Usage error (bad flags) |

### Flags

| Flag | Description |
|------|-------------|
| `--json` | Output as JSON |
| `--help`, `-h` | Show usage |

No subcommands. No `--watch`, `--format`, or other flags initially. Default timeout is 10 seconds (hardcoded; `--timeout` is deferred).

### JSON Escaping

Address fields in JSON output must properly escape `"`, `\`, and control characters. Use manual JSON escaping consistent with copycat's `lib.zig` pattern, or Zig's `std.json` if it provides a simpler path.

## Build System (`build.zig`)

### Compilation

- Shared `location_mod` module from `src/location.zig`
- macOS: links `libobjc`, `CoreLocation`, and `Foundation` frameworks. Foundation is needed for `NSObject` (delegate superclass) and NSString helpers in `objc.zig`. CoreLocation does not guarantee transitive linkage of Foundation at the build system level.
- CLI executable from `src/main.zig`, imports `location_mod`

### macOS `.app` Bundle

Required because macOS Ventura+ silently denies location access to bare CLI binaries. The build step:

1. Creates `zig-out/whereami.app/Contents/MacOS/`
2. Copies the compiled binary into it
3. Writes `Contents/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.whereami.cli</string>
    <key>CFBundleExecutable</key>
    <string>whereami</string>
    <key>CFBundleName</key>
    <string>whereami</string>
    <key>NSLocationUsageDescription</key>
    <string>whereami needs your location to display coordinates.</string>
    <key>NSLocationWhenInUseUsageDescription</key>
    <string>whereami needs your location to display coordinates.</string>
</dict>
</plist>
```

4. Ad-hoc signs: `codesign --sign - whereami.app`

`codesign` requires Xcode Command Line Tools to be installed. If `codesign` is not found, the build step should fail with a clear error message suggesting `xcode-select --install`.

This is the standard, documented `.app` bundle format. No Xcode IDE required. Ad-hoc signing is sufficient for local use and source-based distribution (e.g. Homebrew formulae that compile from source). Prebuilt binary distribution would require Developer ID signing + notarization (out of scope).

### Run Step

`zig build run` executes the binary from within the `.app` bundle so location permissions work correctly.

## Cross-Platform Capability Matrix

| Capability | macOS | Windows (future) | Linux (future) |
|---|---|---|---|
| Get lat/lon | CoreLocation | Win32 ILocation COM | GeoClue2 |
| Reverse geocode | CLGeocoder (native) | External API needed | External API needed |
| Bundle requirement | `.app` bundle + signing | None | None |

## Known Risks and Mitigations

1. **ObjC block ABI for CLGeocoder** — constructing Objective-C blocks from Zig is feasible (documented C ABI) but fiddly. There is no polling fallback — the result is only accessible through the block's completion handler. If block construction proves unworkable, reverse geocoding will be deferred to a future version.

2. **macOS permission prompt UX** — first run triggers a system dialog. If denied, subsequent runs fail silently (no re-prompt). Mitigation: clear error message with instructions to re-enable in System Preferences.

3. **Location accuracy** — desktop Macs without GPS may only get WiFi-based positioning (meters of accuracy) or fail entirely. Mitigation: always display the accuracy value so the user knows what they're getting; timeout with a helpful message if no fix is available.

4. **CFRunLoop complexity** — the run loop must be pumped correctly for CoreLocation to deliver callbacks. Mitigation: use `CFRunLoopRunInMode` with a timeout, which is the standard pattern for synchronous-over-async in CoreLocation CLI tools.

5. **Run loop thread requirement** — `CLLocationManager` must be created and used on a thread with an active run loop. The CLI's main thread satisfies this. Future FFI callers (Bun/TypeScript) must ensure the same, or the library must spawn a dedicated thread with its own run loop.
