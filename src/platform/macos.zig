const std = @import("std");
const objc = @import("../objc.zig");
const Location = @import("../location.zig").Location;
const Address = @import("../location.zig").Address;
const GeocodeResult = @import("../location.zig").GeocodeResult;
const LocationError = @import("../location.zig").LocationError;

// CLLocationCoordinate2D — two f64s, returned in registers on ARM64
const CLLocationCoordinate2D = extern struct {
    latitude: f64,
    longitude: f64,
};

// CoreFoundation run loop externs
extern "c" fn CFRunLoopGetCurrent() *anyopaque;
extern "c" fn CFRunLoopStop(rl: *anyopaque) void;
extern "c" fn CFRunLoopRunInMode(mode: objc.id, seconds: f64, returnAfterSourceHandled: bool) i32;
extern "c" var kCFRunLoopDefaultMode: objc.id;

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

// ---------------------------------------------------------------------------
// Module-level state shared between delegate callbacks and getLocation
// ---------------------------------------------------------------------------
var delegate_class: ?objc.Class = null;
var result_location: ?Location = null;
var result_error: ?LocationError = null;
var completed: bool = false;
var current_run_loop: ?*anyopaque = null;

// ---------------------------------------------------------------------------
// Module-level state for geocoder block callback
// ---------------------------------------------------------------------------
var geocode_result_address: ?Address = null;
var geocode_result_location: ?Location = null;
var geocode_result_error: ?LocationError = null;
var geocode_completed: bool = false;

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

    // On ARM64, CLLocationCoordinate2D (two f64s = 16 bytes) is returned in
    // registers, so we can call [location coordinate] directly via objc_msgSend.
    const coord = objc.msgSend(CLLocationCoordinate2D, location, objc.sel("coordinate"), .{});
    const lat = coord.latitude;
    const lon = coord.longitude;

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

    // CLError code 1 = kCLErrorDenied
    const code = objc.msgSend(isize, err, objc.sel("code"), .{});
    result_error = if (code == 1) LocationError.PermissionDenied else LocationError.LocationUnavailable;
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
// CLGeocoder block callback and helpers
// ---------------------------------------------------------------------------

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

    // The placemark's own coordinate — this is the answer for forward
    // geocoding, and the snapped point for reverse geocoding.
    const placemark_location: ?objc.id = objc.msgSend(?objc.id, placemark, objc.sel("location"), .{});
    if (placemark_location) |cl_location| {
        const coord = objc.msgSend(CLLocationCoordinate2D, cl_location, objc.sel("coordinate"), .{});
        geocode_result_location = Location{
            .latitude = coord.latitude,
            .longitude = coord.longitude,
            .accuracy = 0,
        };
    }

    const address = Address{
        .street = extractStreet(placemark) catch &[_]u8{},
        .city = extractPlacemarkField(placemark, "locality") catch &[_]u8{},
        .state = extractPlacemarkField(placemark, "administrativeArea") catch &[_]u8{},
        .postal_code = extractPlacemarkField(placemark, "postalCode") catch &[_]u8{},
        .country = extractPlacemarkField(placemark, "ISOcountryCode") catch &[_]u8{},
    };

    // Open ocean and similar spots come back as a placemark with no address
    // components at all. Report that as "no address" rather than an empty one.
    // (Nothing to free: empty fields are never heap-allocated.)
    const has_any_field = address.street.len + address.city.len + address.state.len +
        address.postal_code.len + address.country.len > 0;
    if (has_any_field) {
        geocode_result_address = address;
    } else {
        geocode_result_error = LocationError.GeocodingFailed;
    }
    geocode_completed = true;
    if (current_run_loop) |rl| CFRunLoopStop(rl);
}

/// Extract a string property from a CLPlacemark. Returns heap-allocated copy.
/// Uses c_allocator since we're inside an ObjC callback without access to the caller's allocator.
fn extractPlacemarkField(placemark: objc.id, property: [*:0]const u8) ![]const u8 {
    const nsstr: ?objc.id = objc.msgSend(?objc.id, placemark, objc.sel(property), .{});
    const str = nsstr orelse return "";
    const cstr = objc.fromNSString(str) orelse return "";
    const len = std.mem.len(cstr);
    const copy = try std.heap.c_allocator.alloc(u8, len);
    @memcpy(copy, cstr[0..len]);
    return copy;
}

/// Street line including the house number ("45 Hoyt St").
/// Prefers CNPostalAddress.street, which orders number and street name the way
/// the address's own country does ("Hauptstraße 5"). Falls back to joining
/// subThoroughfare + thoroughfare if that isn't available.
fn extractStreet(placemark: objc.id) ![]const u8 {
    const postal: ?objc.id = objc.msgSend(?objc.id, placemark, objc.sel("postalAddress"), .{});
    if (postal) |postal_address| {
        const street = try extractPlacemarkField(postal_address, "street");
        if (street.len > 0) return street;
    }

    const number = try extractPlacemarkField(placemark, "subThoroughfare");
    const name = try extractPlacemarkField(placemark, "thoroughfare");
    if (number.len == 0) return name;
    if (name.len == 0) return number;
    defer std.heap.c_allocator.free(@constCast(number));
    defer std.heap.c_allocator.free(@constCast(name));

    return std.mem.concat(std.heap.c_allocator, u8, &.{ number, " ", name });
}

/// Send a CLGeocoder request whose signature is (argument, completionHandler)
/// and pump the run loop until the handler fires or the timeout passes.
/// Results land in the geocode_result_* module state.
fn runGeocoder(selector: [*:0]const u8, argument: objc.id, timeout_seconds: f64) void {
    geocode_result_address = null;
    geocode_result_location = null;
    geocode_result_error = null;
    geocode_completed = false;

    const CLGeocoder = objc.getClass("CLGeocoder") orelse {
        geocode_result_error = LocationError.GeocodingFailed;
        return;
    };
    const geocoder_alloc = objc.msgSend(objc.id, CLGeocoder, objc.sel("alloc"), .{});
    const geocoder = objc.msgSend(objc.id, geocoder_alloc, objc.sel("init"), .{});

    // Construct the ObjC block on the stack
    var block = GeocoderBlockLiteral{
        .isa = @ptrCast(&_NSConcreteStackBlock),
        .flags = 0,
        .reserved = 0,
        .invoke = &geocoderBlockInvoke,
        .descriptor = &geocoder_block_descriptor,
    };

    current_run_loop = CFRunLoopGetCurrent();
    objc.msgSend(void, geocoder, objc.sel(selector), .{ argument, @as(objc.id, @ptrCast(&block)) });
    _ = CFRunLoopRunInMode(kCFRunLoopDefaultMode, timeout_seconds, false);
    current_run_loop = null;
}

// ---------------------------------------------------------------------------
// Geocoding public API
// ---------------------------------------------------------------------------

pub fn reverseGeocode(allocator: std.mem.Allocator, lat: f64, lon: f64) !?Address {
    _ = allocator; // Address fields use c_allocator (see block callback)

    // Create CLLocation from lat/lon
    const CLLocation = objc.getClass("CLLocation") orelse return null;
    const cl_loc_alloc = objc.msgSend(objc.id, CLLocation, objc.sel("alloc"), .{});
    const cl_location = objc.msgSend(objc.id, cl_loc_alloc, objc.sel("initWithLatitude:longitude:"), .{ lat, lon });

    // [geocoder reverseGeocodeLocation:completionHandler:]
    runGeocoder("reverseGeocodeLocation:completionHandler:", cl_location, 5.0);

    if (geocode_result_error != null) return null;
    return geocode_result_address;
}

/// Forward geocoding: resolve a free-form address string to coordinates.
/// Returns null if nothing matched (or the lookup failed or timed out).
pub fn geocode(allocator: std.mem.Allocator, query: []const u8) !?GeocodeResult {
    const query_z = try allocator.dupeZ(u8, query);
    defer allocator.free(query_z);

    // [geocoder geocodeAddressString:completionHandler:]
    runGeocoder("geocodeAddressString:completionHandler:", objc.nsString(query_z), 10.0);

    const address = geocode_result_address orelse return null;
    const loc = geocode_result_location orelse {
        freeAddress(allocator, address);
        return null;
    };
    return GeocodeResult{ .location = loc, .address = address };
}

pub fn freeAddress(allocator: std.mem.Allocator, address: Address) void {
    _ = allocator; // Fields allocated with c_allocator in block callback
    const alloc = std.heap.c_allocator;
    if (address.street.len > 0) alloc.free(@constCast(address.street));
    if (address.city.len > 0) alloc.free(@constCast(address.city));
    if (address.state.len > 0) alloc.free(@constCast(address.state));
    if (address.postal_code.len > 0) alloc.free(@constCast(address.postal_code));
    if (address.country.len > 0) alloc.free(@constCast(address.country));
}
