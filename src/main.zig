const std = @import("std");
const rl = @import("raylib");
const phiz = @import("phiz");

pub fn main() !void {
    rl.initWindow(800, 600, "phiz-example");
    defer rl.closeWindow();

    var state = State.init;
    while (state.running) {
        input(&state);
        rl.beginDrawing();
        rl.clearBackground(rl.Color.black);
        rl.endDrawing();
    }
}

fn input(state: *State) void {
    if (rl.windowShouldClose() or rl.isKeyDown(.q)) {
        state.running = false;
    }
}

const State = struct {
    const Self = @This();
    pub const init = Self{ .running = true };

    running: bool,
};
