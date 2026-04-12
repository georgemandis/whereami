const std = @import("std");
const objc = @import("../objc.zig");
const Location = @import("../location.zig").Location;
const LocationError = @import("../location.zig").LocationError;

// CoreFoundation run loop externs
extern "c" fn CFRunLoopGetCurrent() *anyopaque;
extern "c" fn CFRunLoopStop(rl: *anyopaque) void;
extern "c" fn CFRunLoopRunInMode(mode: objc.id, seconds: f64, returnAfterSourceHandled: bool) i32;
extern "c" var kCFRunLoopDefaultMode: objc.id;

// ---------------------------------------------------------------------------
// Module-level state shared between delegate callbacks and getLocation
// ---------------------------------------------------------------------------
var delegate_class: ?objc.Class = null;
var result_location: ?Location = null;
var result_error: ?LocationError = null;
var completed: bool = false;
var current_run_loop: ?*anyopaque = null;

// ---------------------------------------------------------------------------
// CLLocationManagerDelegate callback implementations
// ---------------------------------------------------------------------------

fn didUpdateLocations(_self: objc.id, _sel: objc.SEL, manager: objc.id, locations: objc.id) callconv(.c) void {
    _ = _self;
    _ = _sel;
    _ = manager;

    const count = objc.nsArrayCount(locations);
    if (count == 0) return;

    // Get the last (most recent) CLLocation from the array
    const location = objc.nsArrayObjectAtIndex(locations, count - 1);

    // Use KVC to extract latitude and longitude to avoid struct return issues.
    // [location valueForKey:@"latitude"] returns NSNumber
    const lat_key = objc.nsString("latitude");
    const lon_key = objc.nsString("longitude");

    const lat_num: ?objc.id = objc.msgSend(?objc.id, location, objc.sel("valueForKey:"), .{lat_key});
    const lon_num: ?objc.id = objc.msgSend(?objc.id, location, objc.sel("valueForKey:"), .{lon_key});

    if (lat_num == null or lon_num == null) {
        result_error = LocationError.LocationUnavailable;
        completed = true;
        if (current_run_loop) |rl| CFRunLoopStop(rl);
        return;
    }

    const lat = objc.msgSend(f64, lat_num.?, objc.sel("doubleValue"), .{});
    const lon = objc.msgSend(f64, lon_num.?, objc.sel("doubleValue"), .{});

    // horizontalAccuracy returns f64 directly — no struct return issue
    const accuracy = objc.msgSend(f64, location, objc.sel("horizontalAccuracy"), .{});

    result_location = Location{
        .latitude = lat,
        .longitude = lon,
        .accuracy = accuracy,
    };
    completed = true;
    if (current_run_loop) |rl| CFRunLoopStop(rl);
}

fn didFailWithError(_self: objc.id, _sel: objc.SEL, manager: objc.id, err: objc.id) callconv(.c) void {
    _ = _self;
    _ = _sel;
    _ = manager;
    _ = err;

    result_error = LocationError.LocationUnavailable;
    completed = true;
    if (current_run_loop) |rl| CFRunLoopStop(rl);
}

fn didChangeAuthorization(_self: objc.id, _sel: objc.SEL, manager: objc.id) callconv(.c) void {
    _ = _self;
    _ = _sel;

    // CLAuthorizationStatus: 0=notDetermined, 1=restricted, 2=denied,
    // 3=authorizedAlways, 4=authorizedWhenInUse
    const status = objc.msgSend(i32, manager, objc.sel("authorizationStatus"), .{});

    if (status == 3 or status == 4) {
        // Authorized — start location updates
        objc.msgSend(void, manager, objc.sel("startUpdatingLocation"), .{});
    } else if (status == 1 or status == 2) {
        // Restricted or denied
        result_error = LocationError.PermissionDenied;
        completed = true;
        if (current_run_loop) |rl| CFRunLoopStop(rl);
    }
    // status == 0 (notDetermined): still waiting, do nothing
}

// ---------------------------------------------------------------------------
// Delegate class registration
// ---------------------------------------------------------------------------

fn ensureDelegateClass() void {
    if (delegate_class != null) return;

    const NSObject = objc.getClass("NSObject") orelse unreachable;
    const cls = objc.allocateClassPair(NSObject, "WhereAmIDelegate") orelse unreachable;

    // locationManager:didUpdateLocations: — "v@:@@"
    _ = objc.addMethod(
        cls,
        objc.sel("locationManager:didUpdateLocations:"),
        @ptrCast(&didUpdateLocations),
        "v@:@@",
    );

    // locationManager:didFailWithError: — "v@:@@"
    _ = objc.addMethod(
        cls,
        objc.sel("locationManager:didFailWithError:"),
        @ptrCast(&didFailWithError),
        "v@:@@",
    );

    // locationManagerDidChangeAuthorization: — "v@:@"
    _ = objc.addMethod(
        cls,
        objc.sel("locationManagerDidChangeAuthorization:"),
        @ptrCast(&didChangeAuthorization),
        "v@:@",
    );

    objc.registerClassPair(cls);
    delegate_class = cls;
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

pub fn getLocation(allocator: std.mem.Allocator, timeout_ms: u32) !Location {
    _ = allocator;

    // Reset module state
    result_location = null;
    result_error = null;
    completed = false;

    ensureDelegateClass();

    // Create delegate: [[WhereAmIDelegate alloc] init]
    const del_cls = delegate_class.?;
    const del_alloc = objc.msgSend(objc.id, del_cls, objc.sel("alloc"), .{});
    const delegate = objc.msgSend(objc.id, del_alloc, objc.sel("init"), .{});

    // Create CLLocationManager: [[CLLocationManager alloc] init]
    const CLLocationManager = objc.getClass("CLLocationManager") orelse return LocationError.LocationUnavailable;
    const mgr_alloc = objc.msgSend(objc.id, CLLocationManager, objc.sel("alloc"), .{});
    const manager = objc.msgSend(objc.id, mgr_alloc, objc.sel("init"), .{});

    // Set delegate
    objc.msgSend(void, manager, objc.sel("setDelegate:"), .{delegate});

    // Check current authorization status
    const status = objc.msgSend(i32, manager, objc.sel("authorizationStatus"), .{});

    if (status == 3 or status == 4) {
        // Already authorized — start immediately
        objc.msgSend(void, manager, objc.sel("startUpdatingLocation"), .{});
    } else if (status == 0) {
        // Not determined — request authorization (async; delegate handles the rest)
        objc.msgSend(void, manager, objc.sel("requestWhenInUseAuthorization"), .{});
    } else {
        // Restricted or denied
        return LocationError.PermissionDenied;
    }

    // Run the run loop until we get a result or timeout
    const timeout_seconds: f64 = @as(f64, @floatFromInt(timeout_ms)) / 1000.0;
    current_run_loop = CFRunLoopGetCurrent();
    _ = CFRunLoopRunInMode(kCFRunLoopDefaultMode, timeout_seconds, false);
    current_run_loop = null;

    // Stop location updates
    objc.msgSend(void, manager, objc.sel("stopUpdatingLocation"), .{});

    // Check results
    if (result_error) |err| return err;
    if (result_location) |loc| return loc;
    return LocationError.Timeout;
}

// ---------------------------------------------------------------------------
// Stubs for Task 4
// ---------------------------------------------------------------------------

pub fn reverseGeocode(allocator: std.mem.Allocator, lat: f64, lon: f64) !?@import("../location.zig").Address {
    _ = allocator;
    _ = lat;
    _ = lon;
    return null;
}

pub fn freeAddress(allocator: std.mem.Allocator, address: @import("../location.zig").Address) void {
    _ = allocator;
    _ = address;
}
