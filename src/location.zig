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
