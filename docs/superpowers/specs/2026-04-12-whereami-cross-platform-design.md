# whereami Cross-Platform Design: Windows & Linux

## Scope

Add Windows and Linux platform support to `whereami`, plus a `--mock` flag for testing in environments without location hardware (VMs, headless servers).

**In scope:**
- `src/platform/windows.zig` — Win32 ILocation COM API, pure Zig vtable
- `src/platform/linux.zig` — GeoClue2 via D-Bus (`libdbus-1`)
- `--mock LAT,LON` flag — bypass platform APIs with user-supplied coordinates
- Build system changes for platform-specific linking
- Distribution documentation

**Out of scope:**
- Reverse geocoding on Windows/Linux (returns `null` — no native geocoding API)
- IP-based fallback (Phase 2)
- External network calls of any kind
- Changes to macOS implementation

---

## Project Structure (new/modified files)

```
src/
  main.zig              (modify: add --mock flag)
  location.zig          (modify: add .windows, .linux to platform switch)
  platform/
    macos.zig           (unchanged)
    windows.zig         (new)
    linux.zig           (new)
build.zig               (modify: link platform libraries)
```

---

## Platform Module Contract

Every platform module (`macos.zig`, `windows.zig`, `linux.zig`) must export these three functions with exact matching signatures:

```zig
pub fn getLocation(allocator: std.mem.Allocator, timeout_ms: u32) !Location
pub fn reverseGeocode(allocator: std.mem.Allocator, lat: f64, lon: f64) !?Address
pub fn freeAddress(allocator: std.mem.Allocator, address: Address) void
```

The dispatcher in `location.zig` references all three at comptime. For Windows and Linux, `reverseGeocode` returns `null` and `freeAddress` is a no-op, but both must exist.

The updated dispatcher:

```zig
const platform = switch (builtin.os.tag) {
    .macos => @import("platform/macos.zig"),
    .windows => @import("platform/windows.zig"),
    .linux => @import("platform/linux.zig"),
    else => @compileError("Unsupported platform. Currently supported: macOS, Windows, Linux."),
};
```

---

## Windows Implementation

### API: Win32 ILocation COM

Available since Windows 7. Uses the Windows Location API via COM.

### Approach

Define the COM vtable as Zig extern structs with function pointer fields. No C shim — pure Zig, consistent with the macOS ObjC runtime approach.

### Flow

1. `CoInitializeEx(null, COINIT_APARTMENTTHREADED)` — initialize COM
2. `CoCreateInstance(&CLSID_Location, null, CLSCTX_INPROC_SERVER, &IID_ILocation, ...)` — get `ILocation*`
3. `ILocation::SetDesiredAccuracy(IID_ILatLongReport, LOCATION_DESIRED_ACCURACY_HIGH)`
4. `ILocation::RequestPermissions(&IID_ILatLongReport, 1, fWaitForPermission=TRUE)` — triggers Windows location permission prompt
5. `ILocation::GetReport(IID_ILatLongReport, ...)` — get `ILocationReport*`
6. `QueryInterface` to get `ILatLongReport*`
7. `ILatLongReport::GetLatitude(&lat)`, `GetLongitude(&lon)`, `GetErrorRadius(&accuracy)`
8. Release all COM objects
9. `CoUninitialize()`

### COM Type Definitions

All externs use `callconv(.c)` per Zig 0.15 convention. COM vtables are position-sensitive — every slot must have correct parameter types.

```zig
const GUID = extern struct { data1: u32, data2: u16, data3: u16, data4: [8]u8 };
const HRESULT = i32;

// --- ILocation ---
// MSDN: https://learn.microsoft.com/en-us/windows/win32/api/locationapi/nn-locationapi-ilocation
const ILocationVtbl = extern struct {
    // IUnknown (3 methods)
    QueryInterface: *const fn (*ILocation, *const GUID, **anyopaque) callconv(.c) HRESULT,
    AddRef: *const fn (*ILocation) callconv(.c) u32,
    Release: *const fn (*ILocation) callconv(.c) u32,
    // ILocation (9 methods)
    RegisterForReport: *const fn (*ILocation, *anyopaque, *const GUID, u32) callconv(.c) HRESULT,
    UnregisterForReport: *const fn (*ILocation, *const GUID) callconv(.c) HRESULT,
    GetReport: *const fn (*ILocation, *const GUID, **ILocationReport) callconv(.c) HRESULT,
    GetReportStatus: *const fn (*ILocation, *const GUID, *u32) callconv(.c) HRESULT,
    GetReportInterval: *const fn (*ILocation, *const GUID, *u32) callconv(.c) HRESULT,
    SetReportInterval: *const fn (*ILocation, *const GUID, u32) callconv(.c) HRESULT,
    GetDesiredAccuracy: *const fn (*ILocation, *const GUID, *u32) callconv(.c) HRESULT,
    SetDesiredAccuracy: *const fn (*ILocation, *const GUID, u32) callconv(.c) HRESULT,
    RequestPermissions: *const fn (*ILocation, ?*anyopaque, [*]const GUID, u32, i32) callconv(.c) HRESULT,
};

const ILocation = extern struct {
    vtable: *const ILocationVtbl,
};

// --- ILocationReport ---
// MSDN: https://learn.microsoft.com/en-us/windows/win32/api/locationapi/nn-locationapi-ilocationreport
// IUnknown (3) + ILocationReport (4)
const ILocationReportVtbl = extern struct {
    QueryInterface: *const fn (*ILocationReport, *const GUID, **anyopaque) callconv(.c) HRESULT,
    AddRef: *const fn (*ILocationReport) callconv(.c) u32,
    Release: *const fn (*ILocationReport) callconv(.c) u32,
    GetSensorID: *const fn (*ILocationReport, *GUID) callconv(.c) HRESULT,
    GetTimestamp: *const fn (*ILocationReport, *anyopaque) callconv(.c) HRESULT,
    GetValue: *const fn (*ILocationReport, *const anyopaque, *anyopaque) callconv(.c) HRESULT,
    GetPropertyStoreIterator: *const fn (*ILocationReport, **anyopaque) callconv(.c) HRESULT,
};

const ILocationReport = extern struct {
    vtable: *const ILocationReportVtbl,
};

// --- ILatLongReport ---
// MSDN: https://learn.microsoft.com/en-us/windows/win32/api/locationapi/nn-locationapi-ilatlongreport
// IUnknown (3) + ILocationReport (4) + ILatLongReport (4)
const ILatLongReportVtbl = extern struct {
    // IUnknown
    QueryInterface: *const fn (*ILatLongReport, *const GUID, **anyopaque) callconv(.c) HRESULT,
    AddRef: *const fn (*ILatLongReport) callconv(.c) u32,
    Release: *const fn (*ILatLongReport) callconv(.c) u32,
    // ILocationReport
    GetSensorID: *const fn (*ILatLongReport, *GUID) callconv(.c) HRESULT,
    GetTimestamp: *const fn (*ILatLongReport, *anyopaque) callconv(.c) HRESULT,
    GetValue: *const fn (*ILatLongReport, *const anyopaque, *anyopaque) callconv(.c) HRESULT,
    GetPropertyStoreIterator: *const fn (*ILatLongReport, **anyopaque) callconv(.c) HRESULT,
    // ILatLongReport
    GetLatitude: *const fn (*ILatLongReport, *f64) callconv(.c) HRESULT,
    GetLongitude: *const fn (*ILatLongReport, *f64) callconv(.c) HRESULT,
    GetAltitude: *const fn (*ILatLongReport, *f64) callconv(.c) HRESULT,
    GetErrorRadius: *const fn (*ILatLongReport, *f64) callconv(.c) HRESULT,
};

const ILatLongReport = extern struct {
    vtable: *const ILatLongReportVtbl,
};
```

**COM initialization note:** `CoInitializeEx` returns `S_OK` (success), `S_FALSE` (already initialized, same model), or `RPC_E_CHANGED_MODE` (different apartment model). Check for `S_OK` or `S_FALSE` as success.

### Linking

- `ole32` — `CoInitializeEx`, `CoCreateInstance`, `CoUninitialize`
- `oleaut32` — COM automation support

Both are standard Windows system libraries, always available.

### Error Mapping

| HRESULT / condition | LocationError |
|---|---|
| `E_ACCESSDENIED` from RequestPermissions | `PermissionDenied` |
| `GetReport` failure / no data | `LocationUnavailable` |
| Polling timeout exceeded | `Timeout` |

### Reverse Geocoding

`reverseGeocode()` returns `null`. No native Windows geocoding API.

### Bundle/Signing

None needed. Bare `.exe` works. Windows Location Services has its own permission prompt without requiring bundle identity.

---

## Linux Implementation

### API: GeoClue2 over D-Bus

GeoClue2 is the standard location service on Linux desktops (GNOME, KDE). Communication via `libdbus-1` — the low-level D-Bus C library.

### Approach

Declare `libdbus-1` externs in Zig. Send D-Bus method calls to the GeoClue2 service on the system bus. No GLib/GObject dependency — just raw D-Bus protocol.

### Flow

1. `dbus_error_init(&err)` — initialize error struct (required before first use)
2. `dbus_bus_get(DBUS_BUS_SYSTEM, &err)` — connect to system bus
3. Call `org.freedesktop.GeoClue2.Manager.CreateClient()` at path `/org/freedesktop/GeoClue2/Manager` — returns client object path (e.g., `/org/freedesktop/GeoClue2/Client/0`)
4. Set `DesktopId` property on client to `"whereami"` via `org.freedesktop.DBus.Properties.Set` (see Property Access below)
5. Set `RequestedAccuracyLevel` property to `8` (GCLUE_ACCURACY_LEVEL_EXACT) via `org.freedesktop.DBus.Properties.Set`
6. Subscribe to `LocationUpdated` signal via `dbus_bus_add_match` with match rule `type='signal',interface='org.freedesktop.GeoClue2.Client',member='LocationUpdated'`
7. Call `org.freedesktop.GeoClue2.Client.Start()` on the client path — begins location acquisition
8. Loop on `dbus_connection_read_write_dispatch(conn, timeout_ms)` until `LocationUpdated` signal arrives or timeout expires. The signal contains `(old_path, new_path)` — extract `new_path` (the location object path).
9. Read `Latitude`, `Longitude`, `Accuracy` properties from the location object path via `org.freedesktop.DBus.Properties.Get`
10. Call `org.freedesktop.GeoClue2.Client.Stop()`
11. `dbus_error_free(&err)`, `dbus_connection_unref()` — cleanup

### D-Bus Property Access

Setting and getting properties on D-Bus objects requires calling methods on the `org.freedesktop.DBus.Properties` interface, not directly on the GeoClue2 interface.

**Setting a property** (e.g., `DesktopId`):
- Method call to `org.freedesktop.DBus.Properties.Set` on the client path
- Arguments: interface name (`"org.freedesktop.GeoClue2.Client"`), property name (`"DesktopId"`), variant-wrapped value (`DBUS_TYPE_VARIANT` containing `DBUS_TYPE_STRING`)

**Getting a property** (e.g., `Latitude`):
- Method call to `org.freedesktop.DBus.Properties.Get` on the location path
- Arguments: interface name (`"org.freedesktop.GeoClue2.Location"`), property name (`"Latitude"`)
- Reply contains a variant wrapping the actual value (`DBUS_TYPE_DOUBLE`)

The variant wrapping requires using `dbus_message_iter_open_container` / `dbus_message_iter_close_container` with type `DBUS_TYPE_VARIANT`.

### D-Bus Type Definitions and Extern Declarations

```zig
// Opaque types
const DBusConnection = opaque {};
const DBusMessage = opaque {};

// DBusError — must be initialized with dbus_error_init before use.
// The dummy1-5 fields in the C header are bitfields (1 bit each) packed
// into a single unsigned int.
const DBusError = extern struct {
    name: ?[*:0]const u8,
    message: ?[*:0]const u8,
    dummy_bits: c_uint, // 5 single-bit fields packed into one uint
    padding1: ?*anyopaque,
};

// DBusMessageIter — opaque stack-allocated iterator (14 pointer-sized slots)
const DBusMessageIter = extern struct {
    data: [14]?*anyopaque,
};

// Constants
const DBUS_BUS_SYSTEM: c_int = 1;
const DBUS_TYPE_STRING: c_int = 's';
const DBUS_TYPE_VARIANT: c_int = 'v';
const DBUS_TYPE_DOUBLE: c_int = 'd';
const DBUS_TYPE_UINT32: c_int = 'u';
const DBUS_TYPE_OBJECT_PATH: c_int = 'o';

// Key functions from libdbus-1
extern "c" fn dbus_error_init(err: *DBusError) void;
extern "c" fn dbus_error_free(err: *DBusError) void;
extern "c" fn dbus_error_is_set(err: *const DBusError) bool;
extern "c" fn dbus_bus_get(bus_type: c_int, err: *DBusError) ?*DBusConnection;
extern "c" fn dbus_bus_add_match(conn: *DBusConnection, rule: [*:0]const u8, err: *DBusError) void;
extern "c" fn dbus_connection_unref(conn: *DBusConnection) void;
extern "c" fn dbus_connection_read_write_dispatch(conn: *DBusConnection, timeout_ms: c_int) bool;
extern "c" fn dbus_connection_pop_message(conn: *DBusConnection) ?*DBusMessage;
extern "c" fn dbus_message_new_method_call(dest: [*:0]const u8, path: [*:0]const u8, iface: [*:0]const u8, method: [*:0]const u8) ?*DBusMessage;
extern "c" fn dbus_message_is_signal(msg: *DBusMessage, iface: [*:0]const u8, name: [*:0]const u8) bool;
extern "c" fn dbus_connection_send_with_reply_and_block(conn: *DBusConnection, msg: *DBusMessage, timeout: c_int, err: *DBusError) ?*DBusMessage;
extern "c" fn dbus_message_iter_init(msg: *DBusMessage, iter: *DBusMessageIter) bool;
extern "c" fn dbus_message_iter_get_basic(iter: *DBusMessageIter, value: *anyopaque) void;
extern "c" fn dbus_message_iter_recurse(iter: *DBusMessageIter, sub: *DBusMessageIter) void;
extern "c" fn dbus_message_iter_next(iter: *DBusMessageIter) bool;
extern "c" fn dbus_message_iter_init_append(msg: *DBusMessage, iter: *DBusMessageIter) void;
extern "c" fn dbus_message_iter_append_basic(iter: *DBusMessageIter, arg_type: c_int, value: *const anyopaque) bool;
extern "c" fn dbus_message_iter_open_container(iter: *DBusMessageIter, container_type: c_int, contained_sig: ?[*:0]const u8, sub: *DBusMessageIter) bool;
extern "c" fn dbus_message_iter_close_container(iter: *DBusMessageIter, sub: *DBusMessageIter) bool;
extern "c" fn dbus_message_unref(msg: *DBusMessage) void;
```

### Linking

- `dbus-1` — the only dependency. Installed by default on Ubuntu 22 desktop (`libdbus-1-3`). Build requires `libdbus-1-dev` for the shared library.

### GeoClue2 Permissions

GeoClue2 uses an agent-based permission model. On GNOME, a dialog appears. The `DesktopId` property ideally matches a `.desktop` file for the app name to display correctly in the dialog, but it works without one (shows a generic prompt). Acceptable for a CLI tool.

### Error Mapping

| Condition | LocationError |
|---|---|
| No D-Bus connection / no GeoClue2 daemon | `LocationUnavailable` |
| GeoClue2 permission denied | `PermissionDenied` |
| Signal/property timeout | `Timeout` |

### Reverse Geocoding

`reverseGeocode()` returns `null`. No native Linux geocoding API.

### Bundle/Signing

None needed.

---

## Mock Mode

### Flag

`--mock LAT,LON` — e.g., `whereami --mock 40.7128,-74.0060`

### Behavior

- Parses comma-separated lat/lon from the argument value
- Bypasses all platform APIs entirely — no location service calls
- Returns `Location{ .latitude = lat, .longitude = lon, .accuracy = 0 }`
- Reverse geocoding returns `null`
- Works on all platforms, including headless
- Combinable with `--json`: `whereami --mock 40.7,-74.0 --json`

### Implementation

Handled entirely in `main.zig`. Uses the single-token form `--mock=LAT,LON` so it works with the existing argument iteration loop (no lookahead needed).

Parsing: split on `=` to get the value, then split on `,` to get lat/lon, then `std.fmt.parseFloat(f64, ...)` for each. If `--mock` is present, construct the `Location` struct directly and skip `location.getLocation()` and `location.reverseGeocode()`.

### Error Handling

- `--mock` with no `=VALUE` → "Error: --mock requires a value (e.g., --mock=40.7128,-74.0060)", exit 2
- `--mock=` with missing comma → "Error: invalid --mock format, expected LAT,LON", exit 2
- Non-numeric values → "Error: invalid --mock coordinates", exit 2

### Usage Text Update

```
Usage: whereami [options]

Get your current location using native OS location services.

Options:
  --json               Output as JSON
  --mock=LAT,LON       Use provided coordinates instead of location services
  --help, -h           Show this help message
```

---

## Build System Changes

### Platform-specific linking in `build.zig`

```zig
switch (target_os) {
    .macos => {
        location_mod.linkSystemLibrary("objc", .{});
        location_mod.linkFramework("CoreLocation", .{});
        location_mod.linkFramework("Foundation", .{});
    },
    .windows => {
        location_mod.linkSystemLibrary("ole32", .{});
        location_mod.linkSystemLibrary("oleaut32", .{});
    },
    .linux => {
        location_mod.linkSystemLibrary("dbus-1", .{});
    },
    else => {},
}
```

The `.app` bundle / symlink / codesign steps remain macOS-only. Windows and Linux use the simple `addRunArtifact` run path.

### Cross-compilation

Zig can cross-compile, but platform APIs need their system libraries at link time. Build on each target:
- macOS: `zig build bundle` (as today)
- Ubuntu VM: `zig build`
- Windows VM: `zig build`

### `@compileError` removal

The current `else => @compileError("Unsupported platform")` in `location.zig` gets replaced with the three platform branches. The `else` branch can either remain as a compile error or return `PlatformUnsupported`.

---

## Cross-Platform Capability Matrix

| Capability | macOS | Windows | Linux |
|---|---|---|---|
| Get lat/lon | CoreLocation (ObjC runtime) | ILocation COM (vtable) | GeoClue2 (D-Bus) |
| Reverse geocode | CLGeocoder (native) | `null` | `null` |
| Bundle requirement | `.app` + ad-hoc signing | None | None |
| System library deps | libobjc, CoreLocation, Foundation | ole32, oleaut32 | dbus-1 |
| Permission model | Info.plist + OS prompt | Windows Location prompt | GeoClue2 agent dialog |
| Mock mode | `--mock` flag | `--mock` flag | `--mock` flag |

---

## Distribution

### macOS — Homebrew Tap

- Separate repo: `georgemandis/homebrew-tap` with `Formula/whereami.rb`
- Formula downloads source tarball from a GitHub release tag, runs `zig build`, installs `.app` bundle + symlink
- Ad-hoc signing at build time on user's machine — no Apple Developer ID needed
- Install: `brew tap georgemandis/tap && brew install whereami`

### Linux

- **Static binary via GitHub Releases** — user downloads and puts in PATH
- **Homebrew on Linux** — same tap repo works (Homebrew runs on Linux). Same formula with platform conditional.
- **AUR (Arch)** — `PKGBUILD` file in a separate AUR repo
- **`.deb` package (Ubuntu/Debian)** — `dpkg-deb` build step, can add later

### Windows

- **Scoop** — Windows package manager with tap-style model. Separate repo (`georgemandis/scoop-bucket`) with a JSON manifest pointing at `.exe` in a GitHub release
- **GitHub Releases** — zip containing `whereami.exe`. SmartScreen may warn without Authenticode signing ($200-400/year), but users can click through
- **WinGet** — Microsoft's package manager. More formal submission, similar to Homebrew Core

### Common

- Push `whereami` to public GitHub repo
- Tag releases (`v0.1.0`)
- GitHub Actions can automate builds for all three platforms per release

Distribution is deferred until after cross-platform implementation is verified.

---

## Error Message Updates

The current `handleError` in `main.zig` has macOS-specific guidance (e.g., "System Settings > Privacy & Security > Location Services"). Update error messages to be platform-neutral:

- **PermissionDenied**: "Error: location permission denied. Grant location access in your system's privacy/location settings."
- **LocationUnavailable**: "Error: location unavailable. Make sure location services are enabled."
- **Timeout**: "Error: location request timed out."

These generic messages work across all three platforms without conditional compilation in `main.zig`.

---

## Testing Strategy

### VM Testing (Ubuntu 22 + Windows 11 via UTM)

- Build on each VM natively
- `whereami --mock 40.7128,-74.0060` — verifies full pipeline (flag parsing, output formatting, JSON) without needing location hardware
- `whereami --mock 40.7128,-74.0060 --json` — verifies JSON output
- `whereami` (no mock) — will likely return `LocationUnavailable` or `Timeout` in a VM, which verifies the error path
- If the VM has network-based location (WiFi positioning), the real path may work

### Error Path Verification

- No location service → `LocationUnavailable`
- Permission denied → `PermissionDenied`
- Timeout → `Timeout`
- Bad `--mock` input → exit 2 with error message

---

## Risks

| Risk | Mitigation |
|---|---|
| ILocation COM vtable layout wrong | Test on real Windows. COM vtables are well-documented and stable. |
| GeoClue2 D-Bus protocol changes | GeoClue2 API has been stable since 2.0. Ubuntu 22 ships 2.6.x. |
| `libdbus-1` not installed on minimal Linux | Fail gracefully with `LocationUnavailable`. Document dependency. |
| Windows VM has no location provider | `--mock` flag for testing. Error path still verifiable. |
| D-Bus message parsing complexity | libdbus-1 API is verbose but well-documented. Stick to synchronous calls. |
