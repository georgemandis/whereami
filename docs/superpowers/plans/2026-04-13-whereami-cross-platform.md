# whereami Cross-Platform Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Windows and Linux platform support to `whereami`, plus a `--mock` flag for VM/headless testing.

**Architecture:** Each platform gets its own module (`windows.zig`, `linux.zig`) exporting the same three-function interface as `macos.zig`. The `--mock` flag bypasses all platform code and is handled in `main.zig`. Build system links platform-specific libraries conditionally.

**Tech Stack:** Zig 0.15.2, Win32 ILocation COM API (ole32), GeoClue2 via libdbus-1

**Spec:** `docs/superpowers/specs/2026-04-12-whereami-cross-platform-design.md`

---

**CRITICAL: Zig 0.15.2 I/O API**

This project uses Zig 0.15.2 which has breaking I/O changes from earlier versions. The standard output pattern is:

```zig
const stdout_file = std.fs.File.stdout();
var stdout_buf: [4096]u8 = undefined;
var stdout = stdout_file.writer(&stdout_buf);
// stdout.interface.print(...) / stdout.interface.flush()
```

Do NOT use `std.io.getStdOut().writer()` — it does not exist in 0.15.2.

---

## File Structure

```
src/
  main.zig              (modify: add --mock flag, update error messages)
  location.zig          (modify: add .windows, .linux to platform switch)
  platform/
    macos.zig           (unchanged)
    windows.zig         (new: Win32 ILocation COM)
    linux.zig           (new: GeoClue2 via D-Bus)
build.zig               (modify: link platform libraries)
```

## Task Order

1. **Mock mode + error messages** — modify `main.zig` (testable on macOS immediately)
2. **Platform dispatcher + build system** — modify `location.zig` and `build.zig` (enables compilation on all platforms)
3. **Windows stub** — create `windows.zig` with stub functions (compiles on Windows)
4. **Windows ILocation COM** — implement `getLocation` via COM vtables
5. **Linux stub** — create `linux.zig` with stub functions (compiles on Linux)
6. **Linux GeoClue2** — implement `getLocation` via D-Bus
7. **Cross-platform verification** — test on all three platforms

---

### Task 1: Mock Mode & Platform-Neutral Error Messages

**Files:**
- Modify: `src/main.zig`

Add `--mock=LAT,LON` flag parsing and update error messages to be platform-neutral.

- [ ] **Step 1: Add mock flag parsing and update usage text**

Replace the full `src/main.zig` with:

```zig
const std = @import("std");
const location = @import("location");

fn printUsage(writer: *std.io.Writer) !void {
    try writer.print(
        \\Usage: whereami [options]
        \\
        \\Get your current location using native OS location services.
        \\
        \\Options:
        \\  --json               Output as JSON
        \\  --mock=LAT,LON       Use provided coordinates instead of location services
        \\  --help, -h           Show this help message
        \\
    , .{});
}

fn writeJsonString(writer: *std.io.Writer, s: []const u8) !void {
    for (s) |c| {
        switch (c) {
            '"' => try writer.print("\\\"", .{}),
            '\\' => try writer.print("\\\\", .{}),
            '\n' => try writer.print("\\n", .{}),
            '\r' => try writer.print("\\r", .{}),
            '\t' => try writer.print("\\t", .{}),
            0x00...0x08, 0x0B, 0x0C, 0x0E...0x1F => try writer.print("\\u{X:0>4}", .{c}),
            else => try writer.print("{c}", .{c}),
        }
    }
}

fn printHuman(
    writer: *std.io.Writer,
    loc: location.Location,
    addr: ?location.Address,
) !void {
    try writer.print("Location: {d:.4}, {d:.4}\n", .{ loc.latitude, loc.longitude });
    try writer.print("Accuracy: {d:.0}m\n", .{loc.accuracy});

    if (addr) |a| {
        var first = true;
        try writer.print("Address: ", .{});

        const fields = [_][]const u8{ a.street, a.city, a.state, a.postal_code, a.country };
        for (fields) |field| {
            if (field.len == 0) continue;
            if (!first) try writer.print(", ", .{});
            try writer.print("{s}", .{field});
            first = false;
        }
        try writer.print("\n", .{});
    }
}

fn printJson(
    writer: *std.io.Writer,
    loc: location.Location,
    addr: ?location.Address,
) !void {
    try writer.print(
        "{{\"latitude\":{d},\"longitude\":{d},\"accuracy\":{d}",
        .{ loc.latitude, loc.longitude, loc.accuracy },
    );

    if (addr) |a| {
        try writer.print(",\"address\":{{", .{});
        try writer.print("\"street\":\"", .{});
        try writeJsonString(writer, a.street);
        try writer.print("\",\"city\":\"", .{});
        try writeJsonString(writer, a.city);
        try writer.print("\",\"state\":\"", .{});
        try writeJsonString(writer, a.state);
        try writer.print("\",\"postal_code\":\"", .{});
        try writeJsonString(writer, a.postal_code);
        try writer.print("\",\"country\":\"", .{});
        try writeJsonString(writer, a.country);
        try writer.print("\"}}", .{});
    } else {
        try writer.print(",\"address\":null", .{});
    }

    try writer.print("}}\n", .{});
}

fn handleError(
    err: anyerror,
    json_mode: bool,
    stdout_writer: *std.io.Writer,
    stderr_writer: *std.io.Writer,
) void {
    if (json_mode) {
        const error_key: []const u8 = switch (err) {
            error.PermissionDenied => "permission_denied",
            error.LocationUnavailable => "location_unavailable",
            error.Timeout => "timeout",
            else => "unknown_error",
        };
        stdout_writer.print("{{\"error\":\"{s}\"}}\n", .{error_key}) catch {};
        stdout_writer.flush() catch {};
    }

    switch (err) {
        error.PermissionDenied => stderr_writer.print(
            "Error: location permission denied.\nGrant location access in your system's privacy/location settings.\n",
            .{},
        ) catch {},
        error.LocationUnavailable => stderr_writer.print(
            "Error: location unavailable.\nMake sure location services are enabled.\n",
            .{},
        ) catch {},
        error.Timeout => stderr_writer.print(
            "Error: location request timed out.\n",
            .{},
        ) catch {},
        else => stderr_writer.print("Error: unexpected error ({s})\n", .{@errorName(err)}) catch {},
    }
    stderr_writer.flush() catch {};
    std.process.exit(1);
}

/// Parse "--mock=LAT,LON" and return a Location, or null if not a mock flag.
/// Returns error for malformed mock values.
fn parseMockFlag(arg: []const u8) !?location.Location {
    const prefix = "--mock=";
    if (!std.mem.startsWith(u8, arg, prefix)) return null;

    const value = arg[prefix.len..];
    const comma_pos = std.mem.indexOfScalar(u8, value, ',') orelse
        return error.InvalidMockFormat;

    const lat_str = value[0..comma_pos];
    const lon_str = value[comma_pos + 1 ..];

    const lat = std.fmt.parseFloat(f64, lat_str) catch return error.InvalidMockFormat;
    const lon = std.fmt.parseFloat(f64, lon_str) catch return error.InvalidMockFormat;

    return location.Location{
        .latitude = lat,
        .longitude = lon,
        .accuracy = 0,
    };
}

pub fn main() !void {
    const stdout_file = std.fs.File.stdout();
    var stdout_buf: [4096]u8 = undefined;
    var stdout = stdout_file.writer(&stdout_buf);

    const stderr_file = std.fs.File.stderr();
    var stderr_buf: [4096]u8 = undefined;
    var stderr = stderr_file.writer(&stderr_buf);

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var json_output = false;
    var mock_location: ?location.Location = null;

    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "--json")) {
            json_output = true;
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            try printUsage(&stdout.interface);
            try stdout.interface.flush();
            return;
        } else if (std.mem.startsWith(u8, arg, "--mock")) {
            if (std.mem.eql(u8, arg, "--mock")) {
                try stderr.interface.print("Error: --mock requires a value (e.g., --mock=40.7128,-74.0060)\n", .{});
                try stderr.interface.flush();
                std.process.exit(2);
            }
            mock_location = parseMockFlag(arg) catch {
                try stderr.interface.print("Error: invalid --mock format, expected --mock=LAT,LON\n", .{});
                try stderr.interface.flush();
                std.process.exit(2);
            };
        } else {
            try stderr.interface.print("Error: unknown flag: {s}\n\n", .{arg});
            try printUsage(&stderr.interface);
            try stderr.interface.flush();
            std.process.exit(2);
        }
    }

    // Get location: either from mock or from platform APIs
    const loc = if (mock_location) |ml| ml else location.getLocation(allocator, 10000) catch |err| {
        handleError(err, json_output, &stdout.interface, &stderr.interface);
        unreachable;
    };

    // Reverse geocoding: skip in mock mode
    const addr_result = if (mock_location != null)
        @as(?location.Address, null)
    else
        location.reverseGeocode(allocator, loc.latitude, loc.longitude) catch null;
    defer if (addr_result) |a| location.freeAddress(allocator, a);

    if (json_output) {
        try printJson(&stdout.interface, loc, addr_result);
    } else {
        try printHuman(&stdout.interface, loc, addr_result);
    }

    try stdout.interface.flush();
}
```

- [ ] **Step 2: Verify it compiles**

Run: `zig build`
Expected: compiles without errors

- [ ] **Step 3: Test mock mode on macOS**

Run: `zig build run -- --mock=40.7128,-74.0060`
Expected:
```
Location: 40.7128, -74.0060
Accuracy: 0m
```

Run: `zig build run -- --mock=40.7128,-74.0060 --json`
Expected:
```json
{"latitude":40.7128,"longitude":-74.006,"accuracy":0,"address":null}
```

Run: `zig build run -- --mock`
Expected: "Error: --mock requires a value" + exit 2

Run: `zig build run -- --mock=notanumber`
Expected: "Error: invalid --mock format" + exit 2

- [ ] **Step 4: Verify real location still works**

Run: `zig build bundle && zig-out/bin/whereami`
Expected: prints real location with address (as before)

- [ ] **Step 5: Commit**

```bash
git add src/main.zig
git commit -m "feat: add --mock flag and platform-neutral error messages"
```

---

### Task 2: Platform Dispatcher & Build System

**Files:**
- Modify: `src/location.zig`
- Modify: `build.zig`

Update the platform switch to include Windows and Linux, and add platform-specific library linking.

- [ ] **Step 1: Update location.zig platform switch**

In `src/location.zig`, replace lines 5-8:

```zig
const platform = switch (builtin.os.tag) {
    .macos => @import("platform/macos.zig"),
    else => @compileError("Unsupported platform. Currently supported: macOS."),
};
```

With:

```zig
const platform = switch (builtin.os.tag) {
    .macos => @import("platform/macos.zig"),
    .windows => @import("platform/windows.zig"),
    .linux => @import("platform/linux.zig"),
    else => @compileError("Unsupported platform. Currently supported: macOS, Windows, Linux."),
};
```

- [ ] **Step 2: Update build.zig platform linking**

In `build.zig`, replace lines 14-21:

```zig
    switch (target_os) {
        .macos => {
            location_mod.linkSystemLibrary("objc", .{});
            location_mod.linkFramework("CoreLocation", .{});
            location_mod.linkFramework("Foundation", .{});
        },
        else => {},
    }
```

With:

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

- [ ] **Step 3: Verify macOS still compiles**

Run: `zig build`
Expected: compiles without errors (the new platform files don't exist yet, but they're behind comptime switches that won't be evaluated on macOS)

- [ ] **Step 4: Commit**

```bash
git add src/location.zig build.zig
git commit -m "feat: add Windows and Linux to platform dispatcher and build system"
```

---

### Task 3: Windows Platform Stub

**Files:**
- Create: `src/platform/windows.zig`

Create the Windows platform module with stub implementations that return `LocationUnavailable`. This ensures the project compiles on Windows before implementing the real COM logic.

- [ ] **Step 1: Create windows.zig with stub functions**

Create `src/platform/windows.zig`:

```zig
const std = @import("std");
const Location = @import("../location.zig").Location;
const Address = @import("../location.zig").Address;
const LocationError = @import("../location.zig").LocationError;

pub fn getLocation(allocator: std.mem.Allocator, timeout_ms: u32) !Location {
    _ = allocator;
    _ = timeout_ms;
    // TODO: Implement via Win32 ILocation COM API
    return LocationError.LocationUnavailable;
}

pub fn reverseGeocode(allocator: std.mem.Allocator, lat: f64, lon: f64) !?Address {
    _ = allocator;
    _ = lat;
    _ = lon;
    // No native Windows geocoding API
    return null;
}

pub fn freeAddress(allocator: std.mem.Allocator, address: Address) void {
    _ = allocator;
    _ = address;
    // No-op: reverseGeocode always returns null
}
```

- [ ] **Step 2: Verify it compiles on Windows VM**

Copy the project to the Windows 11 VM and run: `zig build`
Expected: compiles without errors

Test: `zig build run -- --mock=40.7128,-74.0060`
Expected: prints mock location (verifies the full pipeline works on Windows)

Test: `zig build run`
Expected: "Error: location unavailable" + exit 1

- [ ] **Step 3: Commit**

```bash
git add src/platform/windows.zig
git commit -m "feat: add Windows platform stub"
```

---

### Task 4: Windows ILocation COM Implementation

**Files:**
- Modify: `src/platform/windows.zig`

Replace the stub `getLocation` with the full Win32 ILocation COM implementation.

- [ ] **Step 1: Implement the full windows.zig**

Replace `src/platform/windows.zig` with:

```zig
const std = @import("std");
const Location = @import("../location.zig").Location;
const Address = @import("../location.zig").Address;
const LocationError = @import("../location.zig").LocationError;

// ---------------------------------------------------------------------------
// Win32 COM type definitions
// ---------------------------------------------------------------------------

const GUID = extern struct {
    data1: u32,
    data2: u16,
    data3: u16,
    data4: [8]u8,
};

const HRESULT = i32;

const S_OK: HRESULT = 0;
const S_FALSE: HRESULT = 1;
const E_ACCESSDENIED: HRESULT = @bitCast(@as(u32, 0x80070005));

const COINIT_APARTMENTTHREADED: u32 = 0x2;
const CLSCTX_INPROC_SERVER: u32 = 0x1;
const LOCATION_DESIRED_ACCURACY_HIGH: u32 = 0;

// CLSID_Location: {E5B8E079-EE6D-4E33-A438-C87F2E959254}
const CLSID_Location = GUID{
    .data1 = 0xE5B8E079,
    .data2 = 0xEE6D,
    .data3 = 0x4E33,
    .data4 = .{ 0xA4, 0x38, 0xC8, 0x7F, 0x2E, 0x95, 0x92, 0x54 },
};

// IID_ILocation: {AB2ECE69-56D9-4F28-B525-DE1B0EE44237}
const IID_ILocation = GUID{
    .data1 = 0xAB2ECE69,
    .data2 = 0x56D9,
    .data3 = 0x4F28,
    .data4 = .{ 0xB5, 0x25, 0xDE, 0x1B, 0x0E, 0xE4, 0x42, 0x37 },
};

// IID_ILatLongReport: {7FED806D-0EF8-4F07-80AC-36A0BEAE3134}
const IID_ILatLongReport = GUID{
    .data1 = 0x7FED806D,
    .data2 = 0x0EF8,
    .data3 = 0x4F07,
    .data4 = .{ 0x80, 0xAC, 0x36, 0xA0, 0xBE, 0xAE, 0x31, 0x34 },
};

// IID_ILocationReport: {C8B7F7EE-75D0-4DB9-B62A-7A0F394C1CBB} (not directly used but needed for reference)

// --- COM vtable definitions ---
// COM vtables are position-sensitive. Every slot must be present with correct types.

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

const ILocationReportVtbl = extern struct {
    // IUnknown (3)
    QueryInterface: *const fn (*ILocationReport, *const GUID, **anyopaque) callconv(.c) HRESULT,
    AddRef: *const fn (*ILocationReport) callconv(.c) u32,
    Release: *const fn (*ILocationReport) callconv(.c) u32,
    // ILocationReport (4)
    GetSensorID: *const fn (*ILocationReport, *GUID) callconv(.c) HRESULT,
    GetTimestamp: *const fn (*ILocationReport, *anyopaque) callconv(.c) HRESULT,
    GetValue: *const fn (*ILocationReport, *const anyopaque, *anyopaque) callconv(.c) HRESULT,
    GetPropertyStoreIterator: *const fn (*ILocationReport, **anyopaque) callconv(.c) HRESULT,
};

const ILocationReport = extern struct {
    vtable: *const ILocationReportVtbl,
};

const ILatLongReportVtbl = extern struct {
    // IUnknown (3)
    QueryInterface: *const fn (*ILatLongReport, *const GUID, **anyopaque) callconv(.c) HRESULT,
    AddRef: *const fn (*ILatLongReport) callconv(.c) u32,
    Release: *const fn (*ILatLongReport) callconv(.c) u32,
    // ILocationReport (4)
    GetSensorID: *const fn (*ILatLongReport, *GUID) callconv(.c) HRESULT,
    GetTimestamp: *const fn (*ILatLongReport, *anyopaque) callconv(.c) HRESULT,
    GetValue: *const fn (*ILatLongReport, *const anyopaque, *anyopaque) callconv(.c) HRESULT,
    GetPropertyStoreIterator: *const fn (*ILatLongReport, **anyopaque) callconv(.c) HRESULT,
    // ILatLongReport (4)
    GetLatitude: *const fn (*ILatLongReport, *f64) callconv(.c) HRESULT,
    GetLongitude: *const fn (*ILatLongReport, *f64) callconv(.c) HRESULT,
    GetAltitude: *const fn (*ILatLongReport, *f64) callconv(.c) HRESULT,
    GetErrorRadius: *const fn (*ILatLongReport, *f64) callconv(.c) HRESULT,
};

const ILatLongReport = extern struct {
    vtable: *const ILatLongReportVtbl,
};

// ---------------------------------------------------------------------------
// Win32 COM extern functions
// ---------------------------------------------------------------------------

extern "system" fn CoInitializeEx(reserved: ?*anyopaque, co_init: u32) HRESULT;
extern "system" fn CoCreateInstance(
    clsid: *const GUID,
    outer: ?*anyopaque,
    cls_context: u32,
    iid: *const GUID,
    ppv: **anyopaque,
) HRESULT;
extern "system" fn CoUninitialize() void;

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

pub fn getLocation(allocator: std.mem.Allocator, timeout_ms: u32) !Location {
    _ = allocator;

    // Initialize COM
    const hr_init = CoInitializeEx(null, COINIT_APARTMENTTHREADED);
    if (hr_init != S_OK and hr_init != S_FALSE) {
        return LocationError.LocationUnavailable;
    }
    defer CoUninitialize();

    // Create ILocation instance
    var location_ptr: *anyopaque = undefined;
    const hr_create = CoCreateInstance(
        &CLSID_Location,
        null,
        CLSCTX_INPROC_SERVER,
        &IID_ILocation,
        &location_ptr,
    );
    if (hr_create != S_OK) {
        return LocationError.LocationUnavailable;
    }
    const loc: *ILocation = @ptrCast(@alignCast(location_ptr));
    defer _ = loc.vtable.Release(loc);

    // Set desired accuracy
    _ = loc.vtable.SetDesiredAccuracy(loc, &IID_ILatLongReport, LOCATION_DESIRED_ACCURACY_HIGH);

    // Request permissions (blocking — waits for user response)
    const report_types = [_]GUID{IID_ILatLongReport};
    const hr_perm = loc.vtable.RequestPermissions(loc, null, &report_types, 1, 1); // fWaitForPermission=TRUE
    if (hr_perm == E_ACCESSDENIED) {
        return LocationError.PermissionDenied;
    }

    // Poll for a location report with timeout
    const timeout_ns: i128 = @as(i128, timeout_ms) * std.time.ns_per_ms;
    const start: i128 = std.time.nanoTimestamp();

    while (true) {
        var report_ptr: *ILocationReport = undefined;
        const hr_report = loc.vtable.GetReport(loc, &IID_ILatLongReport, &report_ptr);

        if (hr_report == S_OK) {
            defer _ = report_ptr.vtable.Release(report_ptr);

            // QueryInterface to ILatLongReport
            var latlng_ptr: *anyopaque = undefined;
            const hr_qi = report_ptr.vtable.QueryInterface(report_ptr, &IID_ILatLongReport, &latlng_ptr);
            if (hr_qi == S_OK) {
                const latlng: *ILatLongReport = @ptrCast(@alignCast(latlng_ptr));
                defer _ = latlng.vtable.Release(latlng);

                var lat: f64 = 0;
                var lon: f64 = 0;
                var accuracy: f64 = 0;

                const hr_lat = latlng.vtable.GetLatitude(latlng, &lat);
                const hr_lon = latlng.vtable.GetLongitude(latlng, &lon);
                _ = latlng.vtable.GetErrorRadius(latlng, &accuracy);

                if (hr_lat == S_OK and hr_lon == S_OK) {
                    return Location{
                        .latitude = lat,
                        .longitude = lon,
                        .accuracy = accuracy,
                    };
                }
            }
        }

        // Check timeout
        const now: i128 = std.time.nanoTimestamp();
        if (now - start >= timeout_ns) {
            return LocationError.Timeout;
        }

        // Sleep 500ms before retrying
        std.time.sleep(500 * std.time.ns_per_ms);
    }
}

pub fn reverseGeocode(allocator: std.mem.Allocator, lat: f64, lon: f64) !?Address {
    _ = allocator;
    _ = lat;
    _ = lon;
    return null;
}

pub fn freeAddress(allocator: std.mem.Allocator, address: Address) void {
    _ = allocator;
    _ = address;
}
```

**Important note about `extern "system"`:** On Windows, COM functions use the `stdcall` calling convention. In Zig, `extern "system"` selects the platform's default system calling convention (`stdcall` on x86, `C` on x86_64). The vtable function pointers use `callconv(.c)` which works for COM on x86_64 (the calling convention is identical). If you need to support 32-bit Windows, the vtable function pointers would need `callconv(.stdcall)`. For this project (64-bit Windows 11 VM), `callconv(.c)` is correct.

- [ ] **Step 2: Build and test on Windows VM**

Copy project to Windows 11 VM and run:

```
zig build
zig build run -- --mock=40.7128,-74.0060
zig build run -- --mock=40.7128,-74.0060 --json
zig build run
```

Expected: mock mode works, real location may return `LocationUnavailable` or `Timeout` depending on the VM's location services configuration.

- [ ] **Step 3: Commit**

```bash
git add src/platform/windows.zig
git commit -m "feat: Windows ILocation COM implementation"
```

---

### Task 5: Linux Platform Stub

**Files:**
- Create: `src/platform/linux.zig`

Create the Linux platform module with stub implementations.

- [ ] **Step 1: Create linux.zig with stub functions**

Create `src/platform/linux.zig`:

```zig
const std = @import("std");
const Location = @import("../location.zig").Location;
const Address = @import("../location.zig").Address;
const LocationError = @import("../location.zig").LocationError;

pub fn getLocation(allocator: std.mem.Allocator, timeout_ms: u32) !Location {
    _ = allocator;
    _ = timeout_ms;
    // TODO: Implement via GeoClue2 D-Bus
    return LocationError.LocationUnavailable;
}

pub fn reverseGeocode(allocator: std.mem.Allocator, lat: f64, lon: f64) !?Address {
    _ = allocator;
    _ = lat;
    _ = lon;
    return null;
}

pub fn freeAddress(allocator: std.mem.Allocator, address: Address) void {
    _ = allocator;
    _ = address;
}
```

- [ ] **Step 2: Verify it compiles on Linux VM**

Copy project to Ubuntu 22 VM. Install Zig 0.15.2 if needed, then run:

```bash
sudo apt install libdbus-1-dev  # needed for linking
zig build
zig build run -- --mock=40.7128,-74.0060
zig build run
```

Expected: mock works, real returns "location unavailable"

- [ ] **Step 3: Commit**

```bash
git add src/platform/linux.zig
git commit -m "feat: add Linux platform stub"
```

---

### Task 6: Linux GeoClue2 D-Bus Implementation

**Files:**
- Modify: `src/platform/linux.zig`

Replace the stub `getLocation` with the full GeoClue2 implementation over D-Bus.

- [ ] **Step 1: Implement the full linux.zig**

Replace `src/platform/linux.zig` with:

```zig
const std = @import("std");
const Location = @import("../location.zig").Location;
const Address = @import("../location.zig").Address;
const LocationError = @import("../location.zig").LocationError;

// ---------------------------------------------------------------------------
// D-Bus type definitions and extern declarations
// ---------------------------------------------------------------------------

const DBusConnection = opaque {};
const DBusMessage = opaque {};

// DBusError — the dummy1-5 fields are bitfields (1 bit each) packed into
// a single unsigned int. In Zig we represent the packed bits as one c_uint.
const DBusError = extern struct {
    name: ?[*:0]const u8,
    message: ?[*:0]const u8,
    dummy_bits: c_uint, // 5 single-bit fields packed into one uint
    padding1: ?*anyopaque,
};

const DBusMessageIter = extern struct {
    data: [14]?*anyopaque,
};

const DBUS_BUS_SYSTEM: c_int = 1;
const DBUS_TYPE_STRING: c_int = 's';
const DBUS_TYPE_VARIANT: c_int = 'v';
const DBUS_TYPE_DOUBLE: c_int = 'd';
const DBUS_TYPE_UINT32: c_int = 'u';
const DBUS_TYPE_OBJECT_PATH: c_int = 'o';

extern "c" fn dbus_error_init(err: *DBusError) void;
extern "c" fn dbus_error_free(err: *DBusError) void;
extern "c" fn dbus_error_is_set(err: *const DBusError) c_uint;
extern "c" fn dbus_bus_get(bus_type: c_int, err: *DBusError) ?*DBusConnection;
extern "c" fn dbus_bus_add_match(conn: *DBusConnection, rule: [*:0]const u8, err: *DBusError) void;
extern "c" fn dbus_connection_unref(conn: *DBusConnection) void;
extern "c" fn dbus_connection_read_write_dispatch(conn: *DBusConnection, timeout_ms: c_int) c_uint;
extern "c" fn dbus_connection_pop_message(conn: *DBusConnection) ?*DBusMessage;
extern "c" fn dbus_message_new_method_call(
    dest: [*:0]const u8,
    path: [*:0]const u8,
    iface: [*:0]const u8,
    method: [*:0]const u8,
) ?*DBusMessage;
extern "c" fn dbus_message_is_signal(msg: *DBusMessage, iface: [*:0]const u8, name: [*:0]const u8) c_uint;
extern "c" fn dbus_connection_send_with_reply_and_block(
    conn: *DBusConnection,
    msg: *DBusMessage,
    timeout: c_int,
    err: *DBusError,
) ?*DBusMessage;
extern "c" fn dbus_message_iter_init(msg: *DBusMessage, iter: *DBusMessageIter) c_uint;
extern "c" fn dbus_message_iter_get_basic(iter: *DBusMessageIter, value: *anyopaque) void;
extern "c" fn dbus_message_iter_recurse(iter: *DBusMessageIter, sub: *DBusMessageIter) void;
extern "c" fn dbus_message_iter_next(iter: *DBusMessageIter) c_uint;
extern "c" fn dbus_message_iter_init_append(msg: *DBusMessage, iter: *DBusMessageIter) void;
extern "c" fn dbus_message_iter_append_basic(iter: *DBusMessageIter, arg_type: c_int, value: *const anyopaque) c_uint;
extern "c" fn dbus_message_iter_open_container(
    iter: *DBusMessageIter,
    container_type: c_int,
    contained_sig: ?[*:0]const u8,
    sub: *DBusMessageIter,
) c_uint;
extern "c" fn dbus_message_iter_close_container(iter: *DBusMessageIter, sub: *DBusMessageIter) c_uint;
extern "c" fn dbus_message_unref(msg: *DBusMessage) void;

// ---------------------------------------------------------------------------
// D-Bus helpers
// ---------------------------------------------------------------------------

const GEOCLUE_DEST = "org.freedesktop.GeoClue2";
const GEOCLUE_MANAGER_PATH = "/org/freedesktop/GeoClue2/Manager";
const GEOCLUE_MANAGER_IFACE = "org.freedesktop.GeoClue2.Manager";
const GEOCLUE_CLIENT_IFACE = "org.freedesktop.GeoClue2.Client";
const GEOCLUE_LOCATION_IFACE = "org.freedesktop.GeoClue2.Location";
const DBUS_PROPERTIES_IFACE = "org.freedesktop.DBus.Properties";

/// Call a D-Bus method that returns an object path string.
/// Returns a heap-allocated copy (caller must free with c_allocator).
/// The D-Bus reply is unreffed before returning, so the string must be copied.
fn callMethodGetObjectPath(
    conn: *DBusConnection,
    dest: [*:0]const u8,
    path: [*:0]const u8,
    iface: [*:0]const u8,
    method: [*:0]const u8,
    err: *DBusError,
) ?[*:0]const u8 {
    const msg = dbus_message_new_method_call(dest, path, iface, method) orelse return null;
    defer dbus_message_unref(msg);

    const reply = dbus_connection_send_with_reply_and_block(conn, msg, 5000, err) orelse return null;
    defer dbus_message_unref(reply);

    var iter: DBusMessageIter = undefined;
    if (dbus_message_iter_init(reply, &iter) == 0) return null;

    var raw_path: [*:0]const u8 = undefined;
    dbus_message_iter_get_basic(&iter, @ptrCast(&raw_path));

    // Copy the string — the original points into the reply message's buffer
    // which becomes invalid after dbus_message_unref.
    const len = std.mem.len(raw_path);
    const copy = std.heap.c_allocator.allocSentinel(u8, len, 0) catch return null;
    @memcpy(copy[0..len], raw_path[0..len]);
    return copy;
}

/// Set a string property via org.freedesktop.DBus.Properties.Set
fn setStringProperty(
    conn: *DBusConnection,
    dest: [*:0]const u8,
    path: [*:0]const u8,
    iface_name: [*:0]const u8,
    prop_name: [*:0]const u8,
    value: [*:0]const u8,
    err: *DBusError,
) bool {
    const msg = dbus_message_new_method_call(dest, path, DBUS_PROPERTIES_IFACE, "Set") orelse return false;
    defer dbus_message_unref(msg);

    var args: DBusMessageIter = undefined;
    dbus_message_iter_init_append(msg, &args);

    // Append interface name (string)
    _ = dbus_message_iter_append_basic(&args, DBUS_TYPE_STRING, @ptrCast(&iface_name));
    // Append property name (string)
    _ = dbus_message_iter_append_basic(&args, DBUS_TYPE_STRING, @ptrCast(&prop_name));

    // Append variant containing the string value
    var variant: DBusMessageIter = undefined;
    _ = dbus_message_iter_open_container(&args, DBUS_TYPE_VARIANT, "s", &variant);
    _ = dbus_message_iter_append_basic(&variant, DBUS_TYPE_STRING, @ptrCast(&value));
    _ = dbus_message_iter_close_container(&args, &variant);

    const reply = dbus_connection_send_with_reply_and_block(conn, msg, 5000, err);
    if (reply) |r| dbus_message_unref(r);
    return dbus_error_is_set(err) == 0;
}

/// Set a uint32 property via org.freedesktop.DBus.Properties.Set
fn setUint32Property(
    conn: *DBusConnection,
    dest: [*:0]const u8,
    path: [*:0]const u8,
    iface_name: [*:0]const u8,
    prop_name: [*:0]const u8,
    value: u32,
    err: *DBusError,
) bool {
    const msg = dbus_message_new_method_call(dest, path, DBUS_PROPERTIES_IFACE, "Set") orelse return false;
    defer dbus_message_unref(msg);

    var args: DBusMessageIter = undefined;
    dbus_message_iter_init_append(msg, &args);

    _ = dbus_message_iter_append_basic(&args, DBUS_TYPE_STRING, @ptrCast(&iface_name));
    _ = dbus_message_iter_append_basic(&args, DBUS_TYPE_STRING, @ptrCast(&prop_name));

    var variant: DBusMessageIter = undefined;
    _ = dbus_message_iter_open_container(&args, DBUS_TYPE_VARIANT, "u", &variant);
    _ = dbus_message_iter_append_basic(&variant, DBUS_TYPE_UINT32, @ptrCast(&value));
    _ = dbus_message_iter_close_container(&args, &variant);

    const reply = dbus_connection_send_with_reply_and_block(conn, msg, 5000, err);
    if (reply) |r| dbus_message_unref(r);
    return dbus_error_is_set(err) == 0;
}

/// Get a double property via org.freedesktop.DBus.Properties.Get
fn getDoubleProperty(
    conn: *DBusConnection,
    dest: [*:0]const u8,
    path: [*:0]const u8,
    iface_name: [*:0]const u8,
    prop_name: [*:0]const u8,
    err: *DBusError,
) ?f64 {
    const msg = dbus_message_new_method_call(dest, path, DBUS_PROPERTIES_IFACE, "Get") orelse return null;
    defer dbus_message_unref(msg);

    var args: DBusMessageIter = undefined;
    dbus_message_iter_init_append(msg, &args);
    _ = dbus_message_iter_append_basic(&args, DBUS_TYPE_STRING, @ptrCast(&iface_name));
    _ = dbus_message_iter_append_basic(&args, DBUS_TYPE_STRING, @ptrCast(&prop_name));

    const reply = dbus_connection_send_with_reply_and_block(conn, msg, 5000, err) orelse return null;
    defer dbus_message_unref(reply);

    // Reply is a variant containing the double
    var iter: DBusMessageIter = undefined;
    if (dbus_message_iter_init(reply, &iter) == 0) return null;

    var variant_iter: DBusMessageIter = undefined;
    dbus_message_iter_recurse(&iter, &variant_iter);

    var result: f64 = 0;
    dbus_message_iter_get_basic(&variant_iter, @ptrCast(&result));
    return result;
}

/// Call a void method (no arguments, no meaningful return)
fn callVoidMethod(
    conn: *DBusConnection,
    dest: [*:0]const u8,
    path: [*:0]const u8,
    iface: [*:0]const u8,
    method: [*:0]const u8,
    err: *DBusError,
) void {
    const msg = dbus_message_new_method_call(dest, path, iface, method) orelse return;
    defer dbus_message_unref(msg);
    const reply = dbus_connection_send_with_reply_and_block(conn, msg, 5000, err);
    if (reply) |r| dbus_message_unref(r);
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

pub fn getLocation(allocator: std.mem.Allocator, timeout_ms: u32) !Location {
    _ = allocator;

    var err: DBusError = undefined;
    dbus_error_init(&err);
    defer dbus_error_free(&err);

    // Connect to system bus
    const conn = dbus_bus_get(DBUS_BUS_SYSTEM, &err) orelse {
        return LocationError.LocationUnavailable;
    };
    // Note: don't unref a shared connection from dbus_bus_get

    // Create a GeoClue2 client
    const client_path = callMethodGetObjectPath(
        conn,
        GEOCLUE_DEST,
        GEOCLUE_MANAGER_PATH,
        GEOCLUE_MANAGER_IFACE,
        "CreateClient",
        &err,
    ) orelse {
        return LocationError.LocationUnavailable;
    };

    // Set DesktopId
    _ = setStringProperty(conn, GEOCLUE_DEST, client_path, GEOCLUE_CLIENT_IFACE, "DesktopId", "whereami", &err);

    // Set RequestedAccuracyLevel to EXACT (8)
    _ = setUint32Property(conn, GEOCLUE_DEST, client_path, GEOCLUE_CLIENT_IFACE, "RequestedAccuracyLevel", 8, &err);

    // Subscribe to LocationUpdated signal
    dbus_bus_add_match(
        conn,
        "type='signal',interface='org.freedesktop.GeoClue2.Client',member='LocationUpdated'",
        &err,
    );

    // Start location acquisition
    callVoidMethod(conn, GEOCLUE_DEST, client_path, GEOCLUE_CLIENT_IFACE, "Start", &err);
    if (dbus_error_is_set(&err) != 0) {
        // Check if it's a permission error
        if (err.name) |name| {
            const name_slice = std.mem.span(name);
            if (std.mem.indexOf(u8, name_slice, "AccessDenied") != null) {
                return LocationError.PermissionDenied;
            }
        }
        return LocationError.LocationUnavailable;
    }

    // Wait for LocationUpdated signal
    const timeout_per_poll: c_int = 1000; // 1 second per dispatch loop
    var remaining_ms: i64 = @intCast(timeout_ms);

    while (remaining_ms > 0) {
        const poll_timeout: c_int = if (remaining_ms < timeout_per_poll) @intCast(remaining_ms) else timeout_per_poll;
        _ = dbus_connection_read_write_dispatch(conn, poll_timeout);
        remaining_ms -= poll_timeout;

        // Check for messages
        while (dbus_connection_pop_message(conn)) |msg| {
            defer dbus_message_unref(msg);

            if (dbus_message_is_signal(msg, GEOCLUE_CLIENT_IFACE, "LocationUpdated") != 0) {
                // Signal args: (old_path: object_path, new_path: object_path)
                var iter: DBusMessageIter = undefined;
                if (dbus_message_iter_init(msg, &iter) == 0) continue;

                // Skip old_path
                _ = dbus_message_iter_next(&iter);

                // Get new_path (the location object path)
                var location_path: [*:0]const u8 = undefined;
                dbus_message_iter_get_basic(&iter, @ptrCast(&location_path));

                // Read properties from the location object
                const lat = getDoubleProperty(conn, GEOCLUE_DEST, location_path, GEOCLUE_LOCATION_IFACE, "Latitude", &err) orelse continue;
                const lon = getDoubleProperty(conn, GEOCLUE_DEST, location_path, GEOCLUE_LOCATION_IFACE, "Longitude", &err) orelse continue;
                const accuracy = getDoubleProperty(conn, GEOCLUE_DEST, location_path, GEOCLUE_LOCATION_IFACE, "Accuracy", &err) orelse 0;

                // Stop the client
                callVoidMethod(conn, GEOCLUE_DEST, client_path, GEOCLUE_CLIENT_IFACE, "Stop", &err);

                return Location{
                    .latitude = lat,
                    .longitude = lon,
                    .accuracy = accuracy,
                };
            }
        }
    }

    // Timeout — stop client before returning
    callVoidMethod(conn, GEOCLUE_DEST, client_path, GEOCLUE_CLIENT_IFACE, "Stop", &err);
    return LocationError.Timeout;
}

pub fn reverseGeocode(allocator: std.mem.Allocator, lat: f64, lon: f64) !?Address {
    _ = allocator;
    _ = lat;
    _ = lon;
    return null;
}

pub fn freeAddress(allocator: std.mem.Allocator, address: Address) void {
    _ = allocator;
    _ = address;
}
```

- [ ] **Step 2: Build and test on Ubuntu VM**

On the Ubuntu 22 VM:

```bash
sudo apt install libdbus-1-dev  # if not already installed
zig build
zig build run -- --mock=40.7128,-74.0060
zig build run -- --mock=40.7128,-74.0060 --json
zig build run
```

Expected: mock mode works. Real location may work if GeoClue2 is running with a location provider, or may return `LocationUnavailable`/`Timeout`.

- [ ] **Step 3: Commit**

```bash
git add src/platform/linux.zig
git commit -m "feat: Linux GeoClue2 D-Bus implementation"
```

---

### Task 7: Cross-Platform Verification

**Files:**
- None (testing only), possibly minor fixes

Verify `whereami` works on all three platforms.

- [ ] **Step 1: macOS verification**

```bash
zig build bundle
zig-out/bin/whereami
zig-out/bin/whereami --json
zig-out/bin/whereami --mock=51.5074,-0.1278
zig-out/bin/whereami --mock=51.5074,-0.1278 --json
zig-out/bin/whereami --help
```

Expected: real location works, mock works, JSON works, help works.

- [ ] **Step 2: Windows VM verification**

On Windows 11 VM:

```
zig build
zig build run -- --mock=48.8566,2.3522
zig build run -- --mock=48.8566,2.3522 --json
zig build run -- --help
zig build run
```

Expected: mock and help work. Real location returns either coordinates or a clean error message.

- [ ] **Step 3: Ubuntu VM verification**

On Ubuntu 22 VM:

```bash
zig build
zig build run -- --mock=35.6762,139.6503
zig build run -- --mock=35.6762,139.6503 --json
zig build run -- --help
zig build run
```

Expected: mock and help work. Real location returns either coordinates or a clean error message.

- [ ] **Step 4: Fix any issues and commit**

If any fixes were needed:
```bash
git add -A
git commit -m "fix: cross-platform verification fixes"
```

(Skip if everything works.)

---

## Task Dependency Summary

```
Task 1 (mock mode) ─────────────────────────────────────────┐
Task 2 (dispatcher + build) ─────────────────────────────────┤
                                                              │
Task 3 (Windows stub) ──→ Task 4 (Windows COM) ──────────────┤
                                                              ├──→ Task 7 (verify)
Task 5 (Linux stub) ──→ Task 6 (Linux D-Bus) ────────────────┘
```

Tasks 1 and 2 can be done first (on macOS). Tasks 3-4 and 5-6 are independent of each other. Task 7 requires all others.
