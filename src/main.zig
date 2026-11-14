const std = @import("std");
const builtin = @import("builtin");
const location = @import("location");

const version = "0.4.0";

fn printUsage(writer: *std.Io.Writer) !void {
    try writer.print(
        \\Usage: whereami [options] [address]
        \\
        \\Get your current location using native OS location services,
        \\or look up an address or a pair of coordinates.
        \\Version {s} ({s})
        \\
        \\Options:
        \\
    , .{ version, @tagName(builtin.os.tag) });
    try writer.print(
        \\  --json               Output as JSON
        \\  --at=LAT,LON         Look up the address at these coordinates (macOS)
        \\  --mock=LAT,LON       Use provided coordinates instead of location services
        \\  --version, -v        Show version
        \\  --help, -h           Show this help message
        \\  completions <shell>  Generate shell completions (bash, zsh, fish)
        \\
        \\Arguments:
        \\  [address]            Look up the coordinates of an address (macOS)
        \\
        \\Examples:
        \\  whereami
        \\  whereami --at=40.6892,-73.9857
        \\  whereami "1600 Pennsylvania Ave NW, Washington, DC" --json
        \\
        \\Created by George Mandis <george@mand.is>
        \\https://github.com/georgemandis/whereami
        \\
    , .{});
}

fn writeJsonString(writer: *std.Io.Writer, s: []const u8) !void {
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
    writer: *std.Io.Writer,
    loc: location.Location,
    addr: ?location.Address,
    show_accuracy: bool,
) !void {
    try writer.print("Location: {d:.4}, {d:.4}\n", .{ loc.latitude, loc.longitude });
    // Accuracy describes a position fix; a looked-up place doesn't have one.
    if (show_accuracy) try writer.print("Accuracy: {d:.0}m\n", .{loc.accuracy});

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
    writer: *std.Io.Writer,
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
    stdout_writer: *std.Io.Writer,
    stderr_writer: *std.Io.Writer,
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

fn printCompletions(
    shell: []const u8,
    stdout_writer: *std.Io.Writer,
    stderr_writer: *std.Io.Writer,
) !void {
    if (std.mem.eql(u8, shell, "bash")) {
        try stdout_writer.print(
            \\# whereami completions for bash
            \\# Install: eval "$(whereami completions bash)"
            \\# Persist: whereami completions bash > /etc/bash_completion.d/whereami
            \\
            \\_whereami() {{
            \\    local cur prev words cword
            \\    _init_completion || return
            \\
            \\    COMPREPLY=($(compgen -W "--json --at --mock --version -v --help -h completions" -- "$cur"))
            \\
            \\    case "$prev" in
            \\        completions)
            \\            COMPREPLY=($(compgen -W "bash zsh fish" -- "$cur"))
            \\            ;;
            \\    esac
            \\}}
            \\
            \\complete -F _whereami whereami
            \\
        , .{});
    } else if (std.mem.eql(u8, shell, "zsh")) {
        try stdout_writer.print(
            \\#compdef whereami
            \\# whereami completions for zsh
            \\# Install: whereami completions zsh | source /dev/stdin
            \\# Persist: whereami completions zsh > ~/.zfunc/_whereami && fpath+=(~/.zfunc)
            \\
            \\_whereami() {{
            \\    _arguments \
            \\        '--json[Output as JSON]' \
            \\        '--at=[Look up the address at these coordinates]:LAT,LON:' \
            \\        '--mock[Use provided coordinates]:LAT,LON:' \
            \\        '(--version -v)'{{--version,-v}}'[Show version]' \
            \\        '(--help -h)'{{--help,-h}}'[Show help]' \
            \\        '1:command:(completions)' \
            \\        '*::arg:->args'
            \\
            \\    case "$state" in
            \\        args)
            \\            case "$words[1]" in
            \\                completions)
            \\                    _arguments '1:shell:(bash zsh fish)'
            \\                    ;;
            \\            esac
            \\            ;;
            \\    esac
            \\}}
            \\
            \\_whereami "$@"
            \\
        , .{});
    } else if (std.mem.eql(u8, shell, "fish")) {
        try stdout_writer.print(
            \\# whereami completions for fish
            \\# Install: whereami completions fish | source
            \\# Persist: whereami completions fish > ~/.config/fish/completions/whereami.fish
            \\
            \\complete -e -c whereami
            \\complete -c whereami -f
            \\
            \\# flags (always available)
            \\complete -c whereami -l json -d "Output as JSON"
            \\complete -c whereami -l at -r -d "Look up the address at coordinates (LAT,LON)"
            \\complete -c whereami -l mock -r -d "Use provided coordinates (LAT,LON)"
            \\complete -c whereami -l version -s v -d "Show version"
            \\complete -c whereami -l help -s h -d "Show help"
            \\
            \\# completions pseudo-command
            \\complete -c whereami -n "__fish_use_subcommand" -a "completions" -d "Generate shell completions"
            \\complete -c whereami -n "__fish_seen_subcommand_from completions" -a "bash zsh fish" -d "Shell type"
            \\
        , .{});
    } else {
        try stderr_writer.print("Error: unsupported shell '{s}'. Use bash, zsh, or fish\n", .{shell});
        try stderr_writer.flush();
        std.process.exit(2);
        unreachable;
    }

    try stdout_writer.flush();
}

/// Parse the "LAT,LON" value of a "--flag=LAT,LON" argument into a Location.
/// `prefix` is the flag including the "=", e.g. "--mock=".
fn parseCoordFlag(arg: []const u8, comptime prefix: []const u8) !location.Location {
    if (!std.mem.startsWith(u8, arg, prefix)) return error.InvalidCoordFormat;

    const value = arg[prefix.len..];
    const comma_pos = std.mem.indexOfScalar(u8, value, ',') orelse
        return error.InvalidCoordFormat;

    const lat_str = std.mem.trim(u8, value[0..comma_pos], " ");
    const lon_str = std.mem.trim(u8, value[comma_pos + 1 ..], " ");

    const lat = std.fmt.parseFloat(f64, lat_str) catch return error.InvalidCoordFormat;
    const lon = std.fmt.parseFloat(f64, lon_str) catch return error.InvalidCoordFormat;

    return location.Location{
        .latitude = lat,
        .longitude = lon,
        .accuracy = 0,
    };
}

fn isValidCoordinate(loc: location.Location) bool {
    return loc.latitude >= -90 and loc.latitude <= 90 and
        loc.longitude >= -180 and loc.longitude <= 180;
}

/// Report a usage error and exit with status 2.
fn usageError(stderr_writer: *std.Io.Writer, comptime fmt: []const u8, args: anytype) noreturn {
    stderr_writer.print("Error: " ++ fmt ++ "\n", args) catch {};
    stderr_writer.flush() catch {};
    std.process.exit(2);
}

pub fn main(init: std.process.Init) !void {
    const stdout_file = std.Io.File.stdout();
    var stdout_buf: [4096]u8 = undefined;
    var stdout = stdout_file.writerStreaming(init.io, &stdout_buf);

    const stderr_file = std.Io.File.stderr();
    var stderr_buf: [4096]u8 = undefined;
    var stderr = stderr_file.writerStreaming(init.io, &stderr_buf);

    const allocator = init.gpa;

    var json_output = false;
    var mock_location: ?location.Location = null;
    var at_location: ?location.Location = null;

    // Positional arguments are joined into one address, so quoting is optional:
    // `whereami 350 5th Ave, New York` works the same as the quoted form.
    var address_query: std.ArrayList(u8) = .empty;
    var has_address = false;
    defer address_query.deinit(allocator);

    var args_iter = try init.minimal.args.iterateAllocator(allocator);
    defer args_iter.deinit();
    _ = args_iter.next(); // skip program name
    while (args_iter.next()) |arg| {
        if (std.mem.eql(u8, arg, "--json")) {
            json_output = true;
        } else if (std.mem.eql(u8, arg, "--version") or std.mem.eql(u8, arg, "-v")) {
            try stdout.interface.print("whereami " ++ version ++ " (" ++ @tagName(builtin.os.tag) ++ ")\n", .{});
            try stdout.interface.flush();
            return;
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            try printUsage(&stdout.interface);
            try stdout.interface.flush();
            return;
        } else if (std.mem.eql(u8, arg, "completions")) {
            const shell = args_iter.next() orelse {
                try stderr.interface.print("Error: 'completions' requires a shell: bash, zsh, or fish\n", .{});
                try stderr.interface.flush();
                std.process.exit(2);
                unreachable;
            };
            try printCompletions(shell, &stdout.interface, &stderr.interface);
            return;
        } else if (std.mem.startsWith(u8, arg, "--mock")) {
            mock_location = parseCoordFlag(arg, "--mock=") catch
                usageError(&stderr.interface, "invalid --mock format, expected --mock=LAT,LON (e.g., --mock=40.7128,-74.0060)", .{});
        } else if (std.mem.startsWith(u8, arg, "--at")) {
            const at = parseCoordFlag(arg, "--at=") catch
                usageError(&stderr.interface, "invalid --at format, expected --at=LAT,LON (e.g., --at=40.7128,-74.0060)", .{});
            if (!isValidCoordinate(at))
                usageError(&stderr.interface, "--at coordinates out of range (latitude -90..90, longitude -180..180)", .{});
            at_location = at;
        } else if (std.mem.startsWith(u8, arg, "-")) {
            try stderr.interface.print("Error: unknown flag: {s}\n\n", .{arg});
            try printUsage(&stderr.interface);
            try stderr.interface.flush();
            std.process.exit(2);
        } else {
            has_address = true;
            if (address_query.items.len > 0) try address_query.append(allocator, ' ');
            try address_query.appendSlice(allocator, arg);
        }
    }

    const address = std.mem.trim(u8, address_query.items, " \t\r\n");

    if (has_address and address.len == 0)
        usageError(&stderr.interface, "address is empty", .{});
    if (has_address and (at_location != null or mock_location != null))
        usageError(&stderr.interface, "an address can't be combined with --at or --mock", .{});
    if (at_location != null and mock_location != null)
        usageError(&stderr.interface, "--at and --mock can't be used together", .{});

    // Address mode: forward geocode the address to coordinates.
    if (has_address) {
        const found = location.geocode(allocator, address) catch |err| switch (err) {
            error.PlatformUnsupported => {
                if (json_output) {
                    try stdout.interface.print("{{\"error\":\"platform_unsupported\"}}\n", .{});
                    try stdout.interface.flush();
                }
                try stderr.interface.print("Error: address lookup is not supported on this platform.\n", .{});
                try stderr.interface.flush();
                std.process.exit(1);
            },
            else => return err,
        } orelse {
            if (json_output) {
                try stdout.interface.print("{{\"error\":\"address_not_found\"}}\n", .{});
                try stdout.interface.flush();
            }
            try stderr.interface.print(
                "Error: couldn't find a location for \"{s}\".\nCheck the address and your network connection.\n",
                .{address},
            );
            try stderr.interface.flush();
            std.process.exit(1);
        };
        defer location.freeAddress(allocator, found.address);

        if (json_output) {
            try printJson(&stdout.interface, found.location, found.address);
        } else {
            try printHuman(&stdout.interface, found.location, found.address, false);
        }
        try stdout.interface.flush();
        return;
    }

    // Get location: from --at, from --mock, or from platform APIs
    const loc = at_location orelse mock_location orelse location.getLocation(allocator, 10000) catch |err| {
        handleError(err, json_output, &stdout.interface, &stderr.interface);
        unreachable;
    };

    // Reverse geocoding: skipped in mock mode, which stays fully offline
    const addr_result = if (mock_location != null)
        @as(?location.Address, null)
    else
        location.reverseGeocode(allocator, loc.latitude, loc.longitude) catch null;
    defer if (addr_result) |a| location.freeAddress(allocator, a);

    // With --at the address is the whole point, so say so when there isn't one.
    if (at_location != null and addr_result == null) {
        try stderr.interface.print("Warning: no address found for these coordinates.\n", .{});
        try stderr.interface.flush();
    }

    if (json_output) {
        try printJson(&stdout.interface, loc, addr_result);
    } else {
        try printHuman(&stdout.interface, loc, addr_result, at_location == null);
    }

    try stdout.interface.flush();
}
