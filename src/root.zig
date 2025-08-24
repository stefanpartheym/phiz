//! By convention, root.zig is the root source file when making a library.
const std = @import("std");
const m = @import("m");

pub fn bufferedPrint() !void {
    // Stdout is for the actual output of your application, for example if you
    // are implementing gzip, then only the compressed bytes should be sent to
    // stdout, not any debugging messages.
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    try stdout.print("Run `zig build test` to run the tests.\n", .{});

    try stdout.flush(); // Don't forget to flush!
}

pub fn add(a: m.Vec2, b: m.Vec2) m.Vec2 {
    return a.add(b);
}

test "basic add functionality" {
    try std.testing.expect(add(m.Vec2.new(1, 2), m.Vec2.new(3, 4)).eql(m.Vec2.new(4, 6)));
}
