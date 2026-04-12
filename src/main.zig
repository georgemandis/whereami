const std = @import("std");
const location = @import("location");

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

    const loc = location.getLocation(allocator, 10000) catch |err| {
        switch (err) {
            error.PermissionDenied => try stderr.interface.print("Error: location permission denied\n", .{}),
            error.LocationUnavailable => try stderr.interface.print("Error: location unavailable\n", .{}),
            error.Timeout => try stderr.interface.print("Error: location request timed out\n", .{}),
            else => try stderr.interface.print("Error: unexpected error\n", .{}),
        }
        try stderr.interface.flush();
        std.process.exit(1);
    };

    try stdout.interface.print("Location: {d:.6}, {d:.6}\n", .{ loc.latitude, loc.longitude });
    try stdout.interface.print("Accuracy: {d:.1}m\n", .{loc.accuracy});
    try stdout.interface.flush();
}
