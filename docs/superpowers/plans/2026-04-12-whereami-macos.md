# whereami macOS Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Zig CLI tool (`whereami`) that uses macOS CoreLocation to get the machine's current coordinates and reverse-geocoded address, via pure Zig ObjC runtime calls.

**Architecture:** Platform-dispatched library (like copycat's clipboard.zig) with a macOS backend that dynamically creates an ObjC delegate class at runtime to receive CoreLocation callbacks. The CLI wraps this in a synchronous blocking call using CFRunLoop. The binary is packaged as a .app bundle for macOS location permissions.

**Tech Stack:** Zig, macOS CoreLocation/Foundation frameworks via ObjC runtime (`libobjc`), CFRunLoop

**Spec:** `docs/superpowers/specs/2026-04-12-whereami-design.md`

**Reference project:** `/Users/georgemandis/Projects/recurse/2026/clipboard-manager/copycat/` — follow its patterns for project structure, `objc.zig`, build.zig, and platform dispatch.

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `build.zig` | Create | Build system: compile exe, link frameworks, create .app bundle, ad-hoc sign |
| `src/objc.zig` | Create | ObjC runtime bindings — copied from copycat, extended with class creation APIs |
| `src/location.zig` | Create | Public API dispatcher — compile-time platform selection, type definitions |
| `src/platform/macos.zig` | Create | CoreLocation backend — delegate class, getLocation, reverseGeocode |
| `src/main.zig` | Create | CLI entry point — flag parsing, output formatting, error handling |

---

### Task 1: Project Skeleton & Build System

**Files:**
- Create: `build.zig`

This task sets up the project with a minimal build that compiles and links correctly. No real logic yet — just prove the toolchain works.

- [ ] **Step 1: Initialize git repo**

```bash
cd /Users/georgemandis/Projects/recurse/2026/zig-geocoding
git init
```

- [ ] **Step 2: Create build.zig with exe + framework linkage**

Create `build.zig` that:
- Creates a `location_mod` module from `src/location.zig`
- Links `libobjc`, `CoreLocation`, and `Foundation` frameworks (macOS only)
- Builds a CLI executable named `whereami` from `src/main.zig` importing `location_mod`
- Adds a `run` step

Follow copycat's `build.zig` structure exactly (see `/Users/georgemandis/Projects/recurse/2026/clipboard-manager/copycat/build.zig`).

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const target_os = target.result.os.tag;

    const location_mod = b.createModule(.{
        .root_source_file = b.path("src/location.zig"),
        .target = target,
        .optimize = optimize,
    });

    switch (target_os) {
        .macos => {
            location_mod.linkSystemLibrary("objc", .{});
            location_mod.linkFramework("CoreLocation", .{});
            location_mod.linkFramework("Foundation", .{});
        },
        else => {},
    }

    const exe = b.addExecutable(.{
        .name = "whereami",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "location", .module = location_mod },
            },
        }),
    });
    b.installArtifact(exe);

    // Simple run step for initial development (runs bare binary).
    // Task 5 will replace this with a macOS .app bundle-based run step.
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run whereami");
    run_step.dependOn(&run_cmd.step);
}
```

- [ ] **Step 3: Create stub source files so it compiles**

Create `src/location.zig`:

```zig
const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

const platform = switch (builtin.os.tag) {
    .macos => @import("platform/macos.zig"),
    else => @compileError("Unsupported platform. Currently supported: macOS."),
};

pub const Location = struct {
    latitude: f64,
    longitude: f64,
    accuracy: f64,
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
```

Create `src/platform/macos.zig`:

```zig
// Stub — will be implemented in Task 3
```

Create `src/main.zig`:

```zig
pub fn main() !void {
    const stdout = @import("std").io.getStdOut().writer();
    try stdout.print("whereami: not yet implemented\n", .{});
}
```

- [ ] **Step 4: Verify it compiles and runs**

Run: `cd /Users/georgemandis/Projects/recurse/2026/zig-geocoding && zig build run`
Expected: prints "whereami: not yet implemented"

- [ ] **Step 5: Commit**

```bash
git add build.zig src/location.zig src/platform/macos.zig src/main.zig
git commit -m "feat: project skeleton with build system and stub files"
```

---

### Task 2: ObjC Runtime Bindings

**Files:**
- Create: `src/objc.zig`

Copy copycat's `objc.zig` and extend it with class creation APIs. This is a self-contained module with no dependencies beyond `libobjc`.

- [ ] **Step 1: Copy copycat's objc.zig**

Copy from `/Users/georgemandis/Projects/recurse/2026/clipboard-manager/copycat/src/objc.zig` to `src/objc.zig`.

- [ ] **Step 2: Add class creation extern declarations**

Add these to the "Core Obj-C runtime types and extern functions" section:

```zig
// Class creation (for dynamic delegate registration)
extern "objc" fn objc_allocateClassPair(superclass: ?Class, name: [*:0]const u8, extra_bytes: usize) ?Class;
extern "objc" fn objc_registerClassPair(cls: Class) void;
extern "objc" fn class_addMethod(cls: Class, name: SEL, imp: *const anyopaque, types: [*:0]const u8) bool;
```

- [ ] **Step 3: Add public wrapper functions for class creation**

```zig
/// Allocate a new Objective-C class pair. Returns null if the class name is already in use.
pub fn allocateClassPair(superclass: ?Class, name: [*:0]const u8) ?Class {
    return objc_allocateClassPair(superclass, name, 0);
}

/// Register a class pair previously created with allocateClassPair.
/// After registration, the class is ready for use and new methods cannot be added.
pub fn registerClassPair(cls: Class) void {
    objc_registerClassPair(cls);
}

/// Add a method to a class. Must be called before registerClassPair.
/// `imp` is a C function pointer implementing the method.
/// `types` is the ObjC type encoding string (e.g. "v@:@@").
pub fn addMethod(cls: Class, name: SEL, imp: *const anyopaque, types: [*:0]const u8) bool {
    return class_addMethod(cls, name, imp, types);
}
```

- [ ] **Step 4: Verify it compiles**

Update `src/platform/macos.zig` to import objc so the compiler checks the declarations:

```zig
const objc = @import("../objc.zig");

// Verify class creation APIs are accessible
comptime {
    _ = objc.allocateClassPair;
    _ = objc.registerClassPair;
    _ = objc.addMethod;
}
```

Run: `zig build`
Expected: compiles without errors

- [ ] **Step 5: Commit**

```bash
git add src/objc.zig src/platform/macos.zig
git commit -m "feat: add objc.zig with class creation APIs"
```

---

### Task 3: CoreLocation getLocation — Delegate & Run Loop

**Files:**
- Modify: `src/platform/macos.zig`
- Modify: `src/location.zig`

This is the core task — create the ObjC delegate class at runtime, wire up CoreLocation, and implement the synchronous `getLocation` wrapper using CFRunLoop.

- [ ] **Step 1: Add imports and CFRunLoop extern declarations to macos.zig**

Replace the stub content of `src/platform/macos.zig` with:

```zig
const std = @import("std");
const objc = @import("../objc.zig");
const Location = @import("../location.zig").Location;
const LocationError = @import("../location.zig").LocationError;

// CoreFoundation run loop externs
extern "c" fn CFRunLoopGetCurrent() *anyopaque;
extern "c" fn CFRunLoopStop(rl: *anyopaque) void;
extern "c" fn CFRunLoopRunInMode(mode: objc.id, seconds: f64, returnAfterSourceHandled: bool) i32;
extern "c" var kCFRunLoopDefaultMode: objc.id;
```

- [ ] **Step 2: Add module-level state**

```zig
var delegate_class: ?objc.Class = null;
var result_location: ?Location = null;
var result_error: ?LocationError = null;
var completed: bool = false;
var current_run_loop: ?*anyopaque = null;
```

- [ ] **Step 3: Implement delegate callback functions**

These are plain C-calling-convention functions that will be registered as ObjC methods:

```zig
fn didUpdateLocations(self: objc.id, _sel: objc.SEL, manager: objc.id, locations: objc.id) callconv(.c) void {
    _ = self;
    _ = _sel;
    _ = manager;

    const count = objc.nsArrayCount(locations);
    if (count == 0) return;

    // Get the last (most recent) location
    const cl_location = objc.nsArrayObjectAtIndex(locations, count - 1);

    // Extract lat/lon via KVC to avoid CLLocationCoordinate2D struct return issues.
    // [location valueForKey:@"latitude"] returns NSNumber, then call doubleValue.
    const lat_key = objc.nsString("latitude");
    const lon_key = objc.nsString("longitude");
    const lat_nsnum = objc.msgSend(objc.id, cl_location, objc.sel("valueForKey:"), .{lat_key});
    const lon_nsnum = objc.msgSend(objc.id, cl_location, objc.sel("valueForKey:"), .{lon_key});
    const lat = objc.msgSend(f64, lat_nsnum, objc.sel("doubleValue"), .{});
    const lon = objc.msgSend(f64, lon_nsnum, objc.sel("doubleValue"), .{});
    // horizontalAccuracy returns a plain f64, no struct return issue
    const acc = objc.msgSend(f64, cl_location, objc.sel("horizontalAccuracy"), .{});

    result_location = Location{
        .latitude = lat,
        .longitude = lon,
        .accuracy = acc,
    };
    completed = true;

    if (current_run_loop) |rl| CFRunLoopStop(rl);
}

fn didFailWithError(self: objc.id, _sel: objc.SEL, manager: objc.id, err: objc.id) callconv(.c) void {
    _ = self;
    _ = _sel;
    _ = manager;
    _ = err;

    result_error = LocationError.LocationUnavailable;
    completed = true;

    if (current_run_loop) |rl| CFRunLoopStop(rl);
}

fn didChangeAuthorization(self: objc.id, _sel: objc.SEL, manager: objc.id) callconv(.c) void {
    _ = self;
    _ = _sel;

    // CLAuthorizationStatus: 0=notDetermined, 1=restricted, 2=denied, 3=authorizedAlways, 4=authorizedWhenInUse
    const status = objc.msgSend(i32, manager, objc.sel("authorizationStatus"), .{});

    switch (status) {
        3, 4 => {
            // Authorized — start location updates
            objc.msgSend(void, manager, objc.sel("startUpdatingLocation"), .{});
        },
        1, 2 => {
            // Restricted or denied
            result_error = LocationError.PermissionDenied;
            completed = true;
            if (current_run_loop) |rl| CFRunLoopStop(rl);
        },
        else => {
            // notDetermined — still waiting for user prompt
        },
    }
}
```

**Why KVC for coordinates:** `CLLocation.coordinate` returns a `CLLocationCoordinate2D` struct (two f64s). ObjC selectors don't support dot syntax (`coordinate.latitude` is not valid). Using KVC (`valueForKey:`) returns an `NSNumber` wrapper, avoiding struct return calling convention issues entirely. `horizontalAccuracy` returns a plain `f64` so it can use `objc_msgSend` directly.

- [ ] **Step 4: Implement delegate class registration**

```zig
fn ensureDelegateClass() !void {
    if (delegate_class != null) return;

    const NSObject = objc.getClass("NSObject") orelse return LocationError.PlatformUnsupported;
    const cls = objc.allocateClassPair(NSObject, "WhereAmIDelegate") orelse return LocationError.PlatformUnsupported;

    _ = objc.addMethod(
        cls,
        objc.sel("locationManager:didUpdateLocations:"),
        @ptrCast(&didUpdateLocations),
        "v@:@@",
    );
    _ = objc.addMethod(
        cls,
        objc.sel("locationManager:didFailWithError:"),
        @ptrCast(&didFailWithError),
        "v@:@@",
    );
    _ = objc.addMethod(
        cls,
        objc.sel("locationManagerDidChangeAuthorization:"),
        @ptrCast(&didChangeAuthorization),
        "v@:@",
    );

    objc.registerClassPair(cls);
    delegate_class = cls;
}
```

- [ ] **Step 5: Implement getLocation**

```zig
pub fn getLocation(allocator: std.mem.Allocator, timeout_ms: u32) !Location {
    _ = allocator;

    // Reset state
    result_location = null;
    result_error = null;
    completed = false;

    try ensureDelegateClass();

    // Create delegate instance: [[WhereAmIDelegate alloc] init]
    const delegate = objc.msgSend(objc.id, delegate_class.?, objc.sel("alloc"), .{});
    const delegate_instance = objc.msgSend(objc.id, delegate, objc.sel("init"), .{});

    // Create CLLocationManager
    const CLLocationManager = objc.getClass("CLLocationManager") orelse return LocationError.PlatformUnsupported;
    const manager = objc.msgSend(objc.id, CLLocationManager, objc.sel("alloc"), .{});
    const manager_instance = objc.msgSend(objc.id, manager, objc.sel("init"), .{});

    // Set delegate
    objc.msgSend(void, manager_instance, objc.sel("setDelegate:"), .{delegate_instance});

    // Check authorization status
    const status = objc.msgSend(i32, manager_instance, objc.sel("authorizationStatus"), .{});

    switch (status) {
        3, 4 => {
            // Already authorized — start immediately
            objc.msgSend(void, manager_instance, objc.sel("startUpdatingLocation"), .{});
        },
        0 => {
            // Not determined — request authorization (async, delegate handles the rest)
            objc.msgSend(void, manager_instance, objc.sel("requestWhenInUseAuthorization"), .{});
        },
        else => {
            // Denied or restricted
            return LocationError.PermissionDenied;
        },
    }

    // Pump the run loop
    current_run_loop = CFRunLoopGetCurrent();
    const timeout_seconds: f64 = @as(f64, @floatFromInt(timeout_ms)) / 1000.0;
    _ = CFRunLoopRunInMode(kCFRunLoopDefaultMode, timeout_seconds, false);
    current_run_loop = null;

    // Stop updates
    objc.msgSend(void, manager_instance, objc.sel("stopUpdatingLocation"), .{});

    // Check results
    if (result_error) |err| return err;
    if (result_location) |loc| return loc;
    return LocationError.Timeout;
}
```

- [ ] **Step 6: Wire up location.zig dispatcher**

Update `src/location.zig` to delegate to the platform:

```zig
pub fn getLocation(allocator: Allocator, timeout_ms: u32) !Location {
    return platform.getLocation(allocator, timeout_ms);
}

pub fn reverseGeocode(allocator: Allocator, lat: f64, lon: f64) !?Address {
    return platform.reverseGeocode(allocator, lat, lon);
}

pub fn freeAddress(allocator: Allocator, address: Address) void {
    platform.freeAddress(allocator, address);
}
```

Add stubs for reverseGeocode and freeAddress in `src/platform/macos.zig`:

```zig
pub fn reverseGeocode(allocator: std.mem.Allocator, lat: f64, lon: f64) !?@import("../location.zig").Address {
    _ = allocator;
    _ = lat;
    _ = lon;
    return null; // Stub — implemented in Task 4
}

pub fn freeAddress(allocator: std.mem.Allocator, address: @import("../location.zig").Address) void {
    allocator.free(address.street);
    allocator.free(address.city);
    allocator.free(address.state);
    allocator.free(address.postal_code);
    allocator.free(address.country);
}
```

- [ ] **Step 7: Create a minimal main.zig to test getLocation**

```zig
const std = @import("std");
const location = @import("location");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const loc = location.getLocation(allocator, 10000) catch |err| {
        const stderr = std.io.getStdErr().writer();
        switch (err) {
            error.PermissionDenied => try stderr.print("Error: Location permission denied.\nEnable in System Preferences > Privacy & Security > Location Services.\n", .{}),
            error.Timeout => try stderr.print("Error: Location request timed out.\n", .{}),
            error.LocationUnavailable => try stderr.print("Error: Location unavailable.\n", .{}),
            else => try stderr.print("Error: {s}\n", .{@errorName(err)}),
        }
        std.process.exit(1);
    };

    const stdout = std.io.getStdOut().writer();
    try stdout.print("Location: {d:.4}, {d:.4}\nAccuracy: {d:.0}m\n", .{ loc.latitude, loc.longitude, loc.accuracy });
}
```

- [ ] **Step 8: Build and verify compilation**

Run: `zig build`
Expected: compiles without errors

Note: `zig build run` at this stage runs the bare binary (no .app bundle yet), so location access will be silently denied by macOS. That's expected — the full end-to-end test happens after Task 5 adds the bundle.

- [ ] **Step 9: Commit**

```bash
git add src/platform/macos.zig src/location.zig src/main.zig
git commit -m "feat: CoreLocation getLocation via ObjC runtime delegate"
```

---

### Task 4: Reverse Geocoding via CLGeocoder

**Files:**
- Modify: `src/platform/macos.zig`

Implement `reverseGeocode` using CLGeocoder with an ObjC block constructed from Zig.

- [ ] **Step 1: Add block ABI types**

Add to `src/platform/macos.zig`:

```zig
// ObjC block ABI layout for constructing blocks from Zig.
// See: https://clang.llvm.org/docs/Block-ABI-Apple.html
extern var _NSConcreteStackBlock: [1]usize; // sized extern; we only need its address

const BlockDescriptor = extern struct {
    reserved: c_ulong,
    size: c_ulong,
};

const GeocoderBlockLiteral = extern struct {
    isa: *anyopaque,
    flags: c_int,
    reserved: c_int,
    invoke: *const fn (*GeocoderBlockLiteral, ?objc.id, ?objc.id) callconv(.c) void,
    descriptor: *const BlockDescriptor,
};

const geocoder_block_descriptor = BlockDescriptor{
    .reserved = 0,
    .size = @sizeOf(GeocoderBlockLiteral),
};
```

- [ ] **Step 2: Add geocoder module-level state**

```zig
var geocode_result_address: ?@import("../location.zig").Address = null;
var geocode_result_error: ?LocationError = null;
var geocode_completed: bool = false;
```

- [ ] **Step 3: Implement the block invoke function**

```zig
fn geocoderBlockInvoke(block: *GeocoderBlockLiteral, placemarks: ?objc.id, err: ?objc.id) callconv(.c) void {
    _ = block;

    if (err != null or placemarks == null) {
        geocode_result_error = LocationError.GeocodingFailed;
        geocode_completed = true;
        if (current_run_loop) |rl| CFRunLoopStop(rl);
        return;
    }

    const marks = placemarks.?;
    const count = objc.nsArrayCount(marks);
    if (count == 0) {
        geocode_result_error = LocationError.GeocodingFailed;
        geocode_completed = true;
        if (current_run_loop) |rl| CFRunLoopStop(rl);
        return;
    }

    const placemark = objc.nsArrayObjectAtIndex(marks, 0);

    // Extract address fields from CLPlacemark — each may be nil
    const Address = @import("../location.zig").Address;
    geocode_result_address = Address{
        .street = extractPlacemarkField(placemark, "thoroughfare") catch &[_]u8{},
        .city = extractPlacemarkField(placemark, "locality") catch &[_]u8{},
        .state = extractPlacemarkField(placemark, "administrativeArea") catch &[_]u8{},
        .postal_code = extractPlacemarkField(placemark, "postalCode") catch &[_]u8{},
        .country = extractPlacemarkField(placemark, "ISOcountryCode") catch &[_]u8{},
    };
    geocode_completed = true;
    if (current_run_loop) |rl| CFRunLoopStop(rl);
}

/// Extract a string property from a CLPlacemark. Returns heap-allocated copy.
/// Uses the global c_allocator since we're inside an ObjC callback without access
/// to the caller's allocator. The freeAddress function uses the caller's allocator,
/// so we must use c_allocator here for consistency — or store the allocator in
/// module-level state. Using c_allocator is simpler and matches copycat's lib.zig FFI pattern.
fn extractPlacemarkField(placemark: objc.id, property: [*:0]const u8) ![]const u8 {
    const nsstr: ?objc.id = objc.msgSend(?objc.id, placemark, objc.sel(property), .{});
    const str = nsstr orelse return try std.heap.c_allocator.alloc(u8, 0);
    const cstr = objc.fromNSString(str) orelse return try std.heap.c_allocator.alloc(u8, 0);
    const len = std.mem.len(cstr);
    const copy = try std.heap.c_allocator.alloc(u8, len);
    @memcpy(copy, cstr[0..len]);
    return copy;
}
```

**Allocator note:** The block callback does not have access to the caller's allocator. We use `std.heap.c_allocator` for address field allocations inside the callback. The `freeAddress` function should also use `c_allocator` for consistency — update `freeAddress` to use `c_allocator` instead of the passed-in allocator, or store the allocator in module-level state. The simplest approach is to always use `c_allocator` for address strings and ignore the allocator parameter in `freeAddress`. Document this in freeAddress.

- [ ] **Step 4: Implement reverseGeocode**

```zig
pub fn reverseGeocode(allocator: std.mem.Allocator, lat: f64, lon: f64) !?@import("../location.zig").Address {
    _ = allocator; // Address fields use c_allocator (see block callback note)

    // Reset state
    geocode_result_address = null;
    geocode_result_error = null;
    geocode_completed = false;

    // Create CLLocation from lat/lon
    const CLLocation = objc.getClass("CLLocation") orelse return null;
    const cl_loc = objc.msgSend(objc.id, CLLocation, objc.sel("alloc"), .{});
    const cl_loc_instance = objc.msgSend(objc.id, cl_loc, objc.sel("initWithLatitude:longitude:"), .{ lat, lon });

    // Create CLGeocoder
    const CLGeocoder = objc.getClass("CLGeocoder") orelse return null;
    const geocoder = objc.msgSend(objc.id, CLGeocoder, objc.sel("alloc"), .{});
    const geocoder_instance = objc.msgSend(objc.id, geocoder, objc.sel("init"), .{});

    // Construct the block
    var block = GeocoderBlockLiteral{
        .isa = @ptrCast(&_NSConcreteStackBlock),
        .flags = 0,
        .reserved = 0,
        .invoke = &geocoderBlockInvoke,
        .descriptor = &geocoder_block_descriptor,
    };

    // Call [geocoder reverseGeocodeLocation:completionHandler:]
    current_run_loop = CFRunLoopGetCurrent();
    objc.msgSend(void, geocoder_instance, objc.sel("reverseGeocodeLocation:completionHandler:"), .{ cl_loc_instance, @as(objc.id, @ptrCast(&block)) });

    // Pump the run loop (5 second timeout for geocoding)
    _ = CFRunLoopRunInMode(kCFRunLoopDefaultMode, 5.0, false);
    current_run_loop = null;

    if (geocode_result_error != null) return null; // Silently return null on failure per spec
    return geocode_result_address;
}
```

- [ ] **Step 5: Update freeAddress to use c_allocator**

```zig
pub fn freeAddress(allocator: std.mem.Allocator, address: @import("../location.zig").Address) void {
    _ = allocator; // Address fields allocated with c_allocator in block callback
    const alloc = std.heap.c_allocator;
    if (address.street.len > 0) alloc.free(@constCast(address.street));
    if (address.city.len > 0) alloc.free(@constCast(address.city));
    if (address.state.len > 0) alloc.free(@constCast(address.state));
    if (address.postal_code.len > 0) alloc.free(@constCast(address.postal_code));
    if (address.country.len > 0) alloc.free(@constCast(address.country));
}
```

**Implementation note on `@constCast`:** The Address struct uses `[]const u8` for its fields (it's a read-only view for consumers). But `c_allocator.free` needs `[]u8`. Since we own these allocations, `@constCast` is safe here. If the Zig version does not support `@constCast` or this feels wrong, an alternative is to store fields as `[]u8` in the struct.

- [ ] **Step 6: Verify it compiles**

Run: `zig build`
Expected: compiles without errors

- [ ] **Step 7: Commit**

```bash
git add src/platform/macos.zig
git commit -m "feat: reverse geocoding via CLGeocoder with ObjC block ABI"
```

---

### Task 5: .app Bundle & Code Signing Build Step

**Files:**
- Modify: `build.zig`

Add custom build steps that create the `.app` bundle structure, write `Info.plist`, copy the binary, and ad-hoc sign. This is required for macOS location permissions.

- [ ] **Step 1: Rewrite build.zig to integrate the bundle into the run step**

On macOS, `zig build run` must execute the binary from the `.app` bundle (not the bare exe) for location permissions to work. Replace the full `build.zig` with:

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const target_os = target.result.os.tag;

    const location_mod = b.createModule(.{
        .root_source_file = b.path("src/location.zig"),
        .target = target,
        .optimize = optimize,
    });

    switch (target_os) {
        .macos => {
            location_mod.linkSystemLibrary("objc", .{});
            location_mod.linkFramework("CoreLocation", .{});
            location_mod.linkFramework("Foundation", .{});
        },
        else => {},
    }

    const exe = b.addExecutable(.{
        .name = "whereami",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "location", .module = location_mod },
            },
        }),
    });
    b.installArtifact(exe);

    const run_step = b.step("run", "Run whereami");

    if (target_os == .macos) {
        // macOS .app bundle for location permissions
        const bundle_step = b.step("bundle", "Create macOS .app bundle with ad-hoc signing");

        // Create .app directory structure and Info.plist
        const mkdir_and_plist = b.addSystemCommand(&.{
            "sh", "-c",
            \\mkdir -p zig-out/whereami.app/Contents/MacOS && \
            \\cat > zig-out/whereami.app/Contents/Info.plist << 'PLIST'
            \\<?xml version="1.0" encoding="UTF-8"?>
            \\<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            \\<plist version="1.0">
            \\<dict>
            \\    <key>CFBundleIdentifier</key>
            \\    <string>com.whereami.cli</string>
            \\    <key>CFBundleExecutable</key>
            \\    <string>whereami</string>
            \\    <key>CFBundleName</key>
            \\    <string>whereami</string>
            \\    <key>NSLocationUsageDescription</key>
            \\    <string>whereami needs your location to display coordinates.</string>
            \\    <key>NSLocationWhenInUseUsageDescription</key>
            \\    <string>whereami needs your location to display coordinates.</string>
            \\</dict>
            \\</plist>
            \\PLIST
        });
        mkdir_and_plist.step.dependOn(b.getInstallStep());

        // Copy binary into bundle
        const copy_binary = b.addSystemCommand(&.{
            "cp", "zig-out/bin/whereami", "zig-out/whereami.app/Contents/MacOS/whereami",
        });
        copy_binary.step.dependOn(&mkdir_and_plist.step);

        // Ad-hoc sign (requires Xcode Command Line Tools; fails with clear error if missing)
        const codesign = b.addSystemCommand(&.{
            "codesign", "--force", "--sign", "-", "zig-out/whereami.app",
        });
        codesign.step.dependOn(&copy_binary.step);

        bundle_step.dependOn(&codesign.step);

        // zig build run uses the bundle binary on macOS
        const bundle_run = b.addSystemCommand(&.{
            "zig-out/whereami.app/Contents/MacOS/whereami",
        });
        bundle_run.step.dependOn(&codesign.step);
        if (b.args) |args| {
            for (args) |arg| {
                bundle_run.addArg(arg);
            }
        }
        run_step.dependOn(&bundle_run.step);
    } else {
        const run_cmd = b.addRunArtifact(exe);
        run_cmd.step.dependOn(b.getInstallStep());
        if (b.args) |args| {
            run_cmd.addArgs(args);
        }
        run_step.dependOn(&run_cmd.step);
    }
}
```

- [ ] **Step 2: Build the bundle and verify structure**

Run: `zig build bundle`
Expected: creates `zig-out/whereami.app/Contents/MacOS/whereami` and `zig-out/whereami.app/Contents/Info.plist`

Verify: `ls -la zig-out/whereami.app/Contents/MacOS/whereami && cat zig-out/whereami.app/Contents/Info.plist`

- [ ] **Step 3: Test running via `zig build run`**

Run: `zig build run`

Expected: since `zig build run` now goes through the bundle on macOS, it should trigger the location permission prompt on first run. After granting permission, it should print coordinates. If permission was already denied from a previous attempt, reset with:
`tccutil reset LocationServices com.whereami.cli`

This is the first real end-to-end test of location access.

- [ ] **Step 4: Commit**

```bash
git add build.zig
git commit -m "feat: macOS .app bundle with Info.plist and ad-hoc signing"
```

---

### Task 6: CLI — Flag Parsing, Output Formatting, Error Handling

**Files:**
- Modify: `src/main.zig`

Replace the stub main.zig with the full CLI: flag parsing, human-readable and JSON output, error messages with exit codes.

- [ ] **Step 1: Implement full main.zig**

```zig
const std = @import("std");
const location = @import("location");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var json_output = false;
    var help_requested = false;

    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "--json")) {
            json_output = true;
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            help_requested = true;
        } else {
            const stderr = std.io.getStdErr().writer();
            try stderr.print("Unknown option: {s}\n\n", .{arg});
            printUsage(stderr);
            std.process.exit(2);
        }
    }

    if (help_requested) {
        printUsage(std.io.getStdOut().writer());
        return;
    }

    // Get location (10 second timeout)
    const loc = location.getLocation(allocator, 10000) catch |err| {
        return handleError(err, json_output);
    };

    // Try reverse geocoding (may return null on non-macOS or failure)
    const address = location.reverseGeocode(allocator, loc.latitude, loc.longitude) catch null;
    defer if (address) |addr| location.freeAddress(allocator, addr);

    const stdout = std.io.getStdOut().writer();

    if (json_output) {
        try printJson(stdout, loc, address);
    } else {
        try printHuman(stdout, loc, address);
    }
}

fn printHuman(writer: anytype, loc: location.Location, address: ?location.Address) !void {
    try writer.print("Location: {d:.4}, {d:.4}\n", .{ loc.latitude, loc.longitude });
    try writer.print("Accuracy: {d:.0}m\n", .{loc.accuracy});

    if (address) |addr| {
        try writer.print("Address: ", .{});
        var need_comma = false;

        if (addr.street.len > 0) {
            try writer.print("{s}", .{addr.street});
            need_comma = true;
        }
        if (addr.city.len > 0) {
            if (need_comma) try writer.print(", ", .{});
            try writer.print("{s}", .{addr.city});
            need_comma = true;
        }
        if (addr.state.len > 0) {
            if (need_comma) try writer.print(", ", .{});
            try writer.print("{s}", .{addr.state});
            need_comma = true;
        }
        if (addr.postal_code.len > 0) {
            if (need_comma) try writer.print(" ", .{});
            try writer.print("{s}", .{addr.postal_code});
            need_comma = true;
        }
        if (addr.country.len > 0) {
            if (need_comma) try writer.print(", ", .{});
            try writer.print("{s}", .{addr.country});
        }
        try writer.print("\n", .{});
    }
}

fn printJson(writer: anytype, loc: location.Location, address: ?location.Address) !void {
    try writer.print("{{\"latitude\":{d},\"longitude\":{d},\"accuracy\":{d}", .{ loc.latitude, loc.longitude, loc.accuracy });

    if (address) |addr| {
        try writer.print(",\"address\":{{", .{});
        try writeJsonString(writer, "street", addr.street);
        try writer.print(",", .{});
        try writeJsonString(writer, "city", addr.city);
        try writer.print(",", .{});
        try writeJsonString(writer, "state", addr.state);
        try writer.print(",", .{});
        try writeJsonString(writer, "postal_code", addr.postal_code);
        try writer.print(",", .{});
        try writeJsonString(writer, "country", addr.country);
        try writer.print("}}", .{});
    } else {
        try writer.print(",\"address\":null", .{});
    }

    try writer.print("}}\n", .{});
}

fn writeJsonString(writer: anytype, key: []const u8, value: []const u8) !void {
    try writer.print("\"{s}\":\"", .{key});
    for (value) |c| {
        switch (c) {
            '"' => try writer.print("\\\"", .{}),
            '\\' => try writer.print("\\\\", .{}),
            '\n' => try writer.print("\\n", .{}),
            '\r' => try writer.print("\\r", .{}),
            '\t' => try writer.print("\\t", .{}),
            0x00...0x08, 0x0B, 0x0C, 0x0E...0x1F => {
                try writer.print("\\u{X:0>4}", .{c});
            },
            else => try writer.writeByte(c),
        }
    }
    try writer.print("\"", .{});
}

fn handleError(err: anyerror, json_output: bool) !void {
    const stderr = std.io.getStdErr().writer();

    if (json_output) {
        const stdout = std.io.getStdOut().writer();
        const msg: []const u8 = switch (err) {
            error.PermissionDenied => "permission_denied",
            error.Timeout => "timeout",
            error.LocationUnavailable => "location_unavailable",
            else => "unknown_error",
        };
        try stdout.print("{{\"error\":\"{s}\"}}\n", .{msg});
    }

    switch (err) {
        error.PermissionDenied => try stderr.print(
            "Error: Location permission denied.\n" ++
                "Enable in System Preferences > Privacy & Security > Location Services.\n",
            .{},
        ),
        error.Timeout => try stderr.print(
            "Error: Location request timed out (10s).\n" ++
                "Your machine may not have location hardware available.\n",
            .{},
        ),
        error.LocationUnavailable => try stderr.print(
            "Error: Location unavailable.\n" ++
                "Your machine may not have location hardware available.\n",
            .{},
        ),
        else => try stderr.print("Error: {s}\n", .{@errorName(err)}),
    }
    std.process.exit(1);
}

fn printUsage(writer: anytype) void {
    writer.print(
        \\Usage: whereami [options]
        \\
        \\Get your current location using native OS location services.
        \\
        \\Options:
        \\  --json       Output as JSON
        \\  --help, -h   Show this help message
        \\
    , .{}) catch {};
}
```

- [ ] **Step 2: Verify it compiles**

Run: `zig build`
Expected: compiles without errors

- [ ] **Step 3: Test --help flag**

Run: `zig build run -- --help`
Expected: prints usage text, exits 0

- [ ] **Step 4: Test unknown flag**

Run: `zig build run -- --bogus 2>&1; echo "exit: $?"`
Expected: prints "Unknown option: --bogus" and usage, exits 2

- [ ] **Step 5: Full end-to-end test from bundle**

Run: `zig build bundle && zig-out/whereami.app/Contents/MacOS/whereami`

Expected output (example):
```
Location: 40.7128, -74.0060
Accuracy: 65m
Address: Broadway, New York, NY 10007, US
```

Run: `zig-out/whereami.app/Contents/MacOS/whereami --json`

Expected output (example):
```json
{"latitude":40.7128,"longitude":-74.006,"accuracy":65.0,"address":{"street":"Broadway","city":"New York","state":"NY","postal_code":"10007","country":"US"}}
```

- [ ] **Step 6: Commit**

```bash
git add src/main.zig
git commit -m "feat: CLI with human-readable and JSON output, error handling"
```

---

### Task 7: End-to-End Verification & Polish

**Files:**
- Possibly modify: `src/platform/macos.zig`, `src/main.zig`

This task is for verifying everything works end-to-end and fixing any issues discovered during real testing.

- [ ] **Step 1: Clean build and full test**

```bash
rm -rf zig-out zig-cache .zig-cache
zig build bundle
zig-out/whereami.app/Contents/MacOS/whereami
zig-out/whereami.app/Contents/MacOS/whereami --json
```

Verify both outputs are correct and well-formed.

- [ ] **Step 2: Verify coordinate values are correct**

Run `whereami` and cross-check the lat/lon against a known reference (e.g., Apple Maps, Google Maps with your actual location). Verify accuracy value is reasonable (typically 50-100m for WiFi-based positioning on desktop Macs).

If KVC coordinate access via `valueForKey:` returns unexpected values, an alternative approach is to define a `CLLocationCoordinate2D` extern struct and use a typed `objc_msgSend` cast (works on ARM64 without `_stret`).

- [ ] **Step 3: Test with location permission denied**

Reset permissions: `tccutil reset LocationServices com.whereami.cli`
Then deny when prompted. Verify the error message is printed correctly.

- [ ] **Step 4: Fix any issues found and commit**

```bash
git add -A
git commit -m "fix: end-to-end verification fixes"
```

(Only if changes were needed. Skip if everything works.)

- [ ] **Step 5: Create .gitignore**

```
zig-out/
zig-cache/
.zig-cache/
```

```bash
git add .gitignore
git commit -m "chore: add .gitignore"
```

---

## Task Dependency Summary

```
Task 1 (skeleton) → Task 2 (objc.zig) → Task 3 (getLocation) → Task 4 (reverseGeocode)
                                                                         ↓
Task 5 (bundle) depends on Task 1 ──────────────────────────────────→ Task 6 (CLI)
                                                                         ↓
                                                                    Task 7 (verify)
```

Tasks 3 and 5 can be done in parallel since they touch different files. Task 4 depends on Task 3 (extends the same file). Task 6 depends on both Task 3/4 (needs the API) and Task 5 (needs the bundle to test). Task 7 is the final verification.
