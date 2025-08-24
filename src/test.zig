const std = @import("std");

test {
    const root = @import("./root.zig");
    std.testing.refAllDecls(root);
}
