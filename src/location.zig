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

// ---------------------------------------------------------------------------
// Dispatcher functions — delegate to the platform implementation
// ---------------------------------------------------------------------------

pub fn getLocation(allocator: Allocator, timeout_ms: u32) !Location {
    return platform.getLocation(allocator, timeout_ms);
}

pub fn reverseGeocode(allocator: Allocator, lat: f64, lon: f64) !?Address {
    return platform.reverseGeocode(allocator, lat, lon);
}

pub fn freeAddress(allocator: Allocator, address: Address) void {
    platform.freeAddress(allocator, address);
}
