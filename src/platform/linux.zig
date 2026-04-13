const std = @import("std");
const Location = @import("../location.zig").Location;
const LocationError = @import("../location.zig").LocationError;
const Address = @import("../location.zig").Address;

pub fn getLocation(allocator: std.mem.Allocator, timeout_ms: u32) !Location {
    _ = allocator;
    _ = timeout_ms;
    return LocationError.PlatformUnsupported;
}

pub fn reverseGeocode(allocator: std.mem.Allocator, lat: f64, lon: f64) !?Address {
    _ = allocator;
    _ = lat;
    _ = lon;
    return LocationError.PlatformUnsupported;
}

pub fn freeAddress(allocator: std.mem.Allocator, address: Address) void {
    _ = allocator;
    _ = address;
}
