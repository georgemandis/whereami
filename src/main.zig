pub fn main() !void {
    const stdout_file = @import("std").fs.File.stdout();
    var buf: [256]u8 = undefined;
    var w = stdout_file.writer(&buf);
    try w.interface.print("whereami: not yet implemented\n", .{});
    try w.interface.flush();
}
