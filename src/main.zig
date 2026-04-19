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
        \\Created by George Mandis <george@mand.is>
        \\https://github.com/georgemandis/whereami
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
