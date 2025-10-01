const std = @import("std");
const m = @import("m");
const Aabb = @import("./Aabb.zig");
const BodyId = @import("./BodyId.zig");

pub const BodyPair = struct { a: BodyId, b: BodyId };

const GridCoord = struct {
    x: i32,
    y: i32,

    pub fn eql(self: GridCoord, other: GridCoord) bool {
        return self.x == other.x and self.y == other.y;
    }
};

const GridCoordContext = struct {
    pub fn hash(self: @This(), coord: GridCoord) u64 {
        _ = self;
        var hasher = std.hash.Wyhash.init(0);
        std.hash.autoHash(&hasher, coord.x);
        std.hash.autoHash(&hasher, coord.y);
        return hasher.final();
    }

    pub fn eql(self: @This(), a: GridCoord, b: GridCoord) bool {
        _ = self;
        return a.eql(b);
    }
};

const CellHashMap = std.HashMap(
    GridCoord,
    std.ArrayList(BodyId),
    GridCoordContext,
    std.hash_map.default_max_load_percentage,
);

const PairHashMap = std.HashMap(
    u64,
    void,
    std.hash_map.AutoContext(u64),
    std.hash_map.default_max_load_percentage,
);

const Self = @This();

cell_size: f32,
cells: CellHashMap,
allocator: std.mem.Allocator,
pairs: std.ArrayList(BodyPair),
seen_pairs: PairHashMap,

pub fn init(allocator: std.mem.Allocator, cell_size: f32) Self {
    return Self{
        .cell_size = cell_size,
        .cells = CellHashMap.init(allocator),
        .allocator = allocator,
        .pairs = std.ArrayList(BodyPair){},
        .seen_pairs = PairHashMap.init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    var iterator = self.cells.iterator();
    while (iterator.next()) |entry| {
        entry.value_ptr.deinit(self.allocator);
    }
    self.cells.deinit();
    self.pairs.deinit(self.allocator);
    self.seen_pairs.deinit();
}

pub fn clear(self: *Self) void {
    var iterator = self.cells.iterator();
    while (iterator.next()) |entry| {
        entry.value_ptr.clearRetainingCapacity();
    }
}

/// Inserts a body into the grid based on its AABB.
pub fn insert(self: *Self, body_id: BodyId, aabb: Aabb) !void {
    const cells = self.getOverlappingCells(aabb);
    // Insert into body all overlapping cells.
    var y = cells.min.y;
    while (y <= cells.max.y) : (y += 1) {
        var x = cells.min.x;
        while (x <= cells.max.x) : (x += 1) {
            const coord = GridCoord{ .x = x, .y = y };
            const result = try self.cells.getOrPut(coord);
            if (!result.found_existing) {
                result.value_ptr.* = std.ArrayList(BodyId){};
            }
            try result.value_ptr.append(self.allocator, body_id);
        }
    }
}

/// Returns a list of potentially colliding body pairs.
pub fn getPairs(self: *Self) ![]const BodyPair {
    self.pairs.clearRetainingCapacity();
    self.seen_pairs.clearRetainingCapacity();

    var iterator = self.cells.iterator();
    while (iterator.next()) |entry| {
        const body_list = entry.value_ptr;

        // Check all pairs within this cell.
        for (body_list.items, 0..) |body_a, i| {
            for (body_list.items[i + 1 ..]) |body_b| {
                // Create a normalized pair (smaller index first) to avoid duplicates.
                const pair_key = if (body_a.index < body_b.index)
                    (@as(u64, body_a.index) << 32) | @as(u64, body_b.index)
                else
                    (@as(u64, body_b.index) << 32) | @as(u64, body_a.index);
                // Only add if we haven't seen this pair before.
                if (!self.seen_pairs.contains(pair_key)) {
                    try self.seen_pairs.put(pair_key, {});
                    const a_id = if (body_a.index < body_b.index) body_a else body_b;
                    const b_id = if (body_a.index < body_b.index) body_b else body_a;
                    try self.pairs.append(self.allocator, BodyPair{ .a = a_id, .b = b_id });
                }
            }
        }
    }

    return self.pairs.items;
}

/// Converts world position to grid coordinate.
fn worldToGrid(self: Self, pos: m.Vec2) GridCoord {
    return GridCoord{
        .x = @intFromFloat(@floor(pos.x() / self.cell_size)),
        .y = @intFromFloat(@floor(pos.y() / self.cell_size)),
    };
}

/// Gets the grid cells that an AABB overlaps.
fn getOverlappingCells(self: Self, aabb: Aabb) struct { min: GridCoord, max: GridCoord } {
    const min_coord = self.worldToGrid(aabb.min);
    const max_coord = self.worldToGrid(aabb.max);
    return .{ .min = min_coord, .max = max_coord };
}

//------------------------------------------------------------------------------
// Tests
//------------------------------------------------------------------------------

const SpatialHashGrid = Self;

test "SpatialHashGrid.worldToGrid: Should convert world coordinates to grid coordinates" {
    const grid = SpatialHashGrid.init(std.testing.allocator, 10);

    try std.testing.expectEqual(GridCoord{ .x = 0, .y = 0 }, grid.worldToGrid(m.Vec2.new(0, 0)));
    try std.testing.expectEqual(GridCoord{ .x = 1, .y = 1 }, grid.worldToGrid(m.Vec2.new(10, 10)));
    try std.testing.expectEqual(GridCoord{ .x = -1, .y = -1 }, grid.worldToGrid(m.Vec2.new(-5, -5)));
    try std.testing.expectEqual(GridCoord{ .x = 2, .y = 3 }, grid.worldToGrid(m.Vec2.new(25, 35)));
}

test "SpatialHashGrid.getOverlappingCells: Should return correct cell range for AABB" {
    const grid = SpatialHashGrid.init(std.testing.allocator, 10);

    const aabb = Aabb.new(m.Vec2.new(5, 5), m.Vec2.new(25, 15));
    const cells = grid.getOverlappingCells(aabb);

    try std.testing.expectEqual(GridCoord{ .x = 0, .y = 0 }, cells.min);
    try std.testing.expectEqual(GridCoord{ .x = 2, .y = 1 }, cells.max);
}

test "SpatialHashGrid.insert: Should insert body into correct cells" {
    var grid = SpatialHashGrid.init(std.testing.allocator, 10);
    defer grid.deinit();

    const body_id = BodyId.new(0);
    const aabb = Aabb.new(m.Vec2.new(5, 5), m.Vec2.new(15, 15));

    try grid.insert(body_id, aabb);

    // Body should be in 4 cells: (0,0), (0,1), (1,0), (1,1)
    try std.testing.expectEqual(@as(usize, 4), grid.cells.count());

    // Check that body is in the expected cells
    const expected_coords = [_]GridCoord{
        .{ .x = 0, .y = 0 },
        .{ .x = 0, .y = 1 },
        .{ .x = 1, .y = 0 },
        .{ .x = 1, .y = 1 },
    };

    for (expected_coords) |coord| {
        const cell = grid.cells.get(coord);
        try std.testing.expect(cell != null);
        try std.testing.expectEqual(@as(usize, 1), cell.?.items.len);
        try std.testing.expectEqual(body_id.index, cell.?.items[0].index);
    }
}

test "SpatialHashGrid.getPairs: Should return correct pairs" {
    var grid = SpatialHashGrid.init(std.testing.allocator, 10);
    defer grid.deinit();

    const body_a = BodyId.new(0);
    const body_b = BodyId.new(1);
    const body_c = BodyId.new(2);

    // Bodies A and B overlap in same cell
    try grid.insert(body_a, Aabb.new(m.Vec2.new(0, 0), m.Vec2.new(5, 5)));
    try grid.insert(body_b, Aabb.new(m.Vec2.new(2, 2), m.Vec2.new(7, 7)));

    // Body C is in a different cell
    try grid.insert(body_c, Aabb.new(m.Vec2.new(20, 20), m.Vec2.new(25, 25)));

    const pairs = try grid.getPairs();

    // Should only have one pair: A-B
    try std.testing.expectEqual(@as(usize, 1), pairs.len);
    const pair = pairs[0];
    try std.testing.expect((pair.a.index == 0 and pair.b.index == 1) or (pair.a.index == 1 and pair.b.index == 0));
}

test "SpatialHashGrid.clear: Should clear all cells but keep memory" {
    var grid = SpatialHashGrid.init(std.testing.allocator, 10);
    defer grid.deinit();

    try grid.insert(BodyId.new(0), Aabb.new(m.Vec2.new(0, 0), m.Vec2.new(5, 5)));
    try grid.insert(BodyId.new(1), Aabb.new(m.Vec2.new(10, 10), m.Vec2.new(15, 15)));

    try std.testing.expect(grid.cells.count() > 0);

    grid.clear();

    // Cells should still exist but be empty
    var iterator = grid.cells.iterator();
    while (iterator.next()) |entry| {
        try std.testing.expectEqual(@as(usize, 0), entry.value_ptr.items.len);
    }
}
