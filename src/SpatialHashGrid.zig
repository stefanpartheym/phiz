const std = @import("std");
const m = @import("m");
const Aabb = @import("./Aabb.zig");
const BodyId = @import("./BodyId.zig");

pub const BodyPair = struct {
    a: BodyId,
    b: BodyId,
    key: u64,

    /// Create a normalized BodyPair (smaller index first) to avoid duplicates.
    pub inline fn new(a: BodyId, b: BodyId) @This() {
        return if (a.index < b.index)
            @This(){
                .a = a,
                .b = b,
                .key = (@as(u64, a.index) << 32) | @as(u64, b.index),
            }
        else
            @This(){
                .a = b,
                .b = a,
                .key = (@as(u64, b.index) << 32) | @as(u64, a.index),
            };
    }
};

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
non_empty_cells: std.ArrayList(*std.ArrayList(BodyId)),
// Incremental update tracking
body_positions: std.ArrayList(m.Vec2),
body_cells: std.ArrayList(std.ArrayList(GridCoord)),

pub fn init(allocator: std.mem.Allocator, cell_size: f32) Self {
    return Self{
        .cell_size = cell_size,
        .cells = CellHashMap.init(allocator),
        .allocator = allocator,
        .pairs = std.ArrayList(BodyPair){},
        .seen_pairs = PairHashMap.init(allocator),
        .non_empty_cells = std.ArrayList(*std.ArrayList(BodyId)){},
        .body_positions = std.ArrayList(m.Vec2){},
        .body_cells = std.ArrayList(std.ArrayList(GridCoord)){},
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
    self.non_empty_cells.deinit(self.allocator);
    self.body_positions.deinit(self.allocator);
    for (self.body_cells.items) |*cell_list| {
        cell_list.deinit(self.allocator);
    }
    self.body_cells.deinit(self.allocator);
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

/// Initialize incremental tracking for a body count.
pub fn initIncrementalTracking(self: *Self, body_count: usize) !void {
    // Only grow, never shrink to avoid invalidating existing data
    if (body_count <= self.body_positions.items.len) return;

    const old_len = self.body_positions.items.len;
    try self.body_positions.resize(self.allocator, body_count);
    try self.body_cells.resize(self.allocator, body_count);

    // Initialize only new cell lists
    for (self.body_cells.items[old_len..]) |*cell_list| {
        cell_list.* = std.ArrayList(GridCoord){};
    }

    // Initialize only new positions to invalid values to force initial update
    for (self.body_positions.items[old_len..]) |*pos| {
        pos.* = m.Vec2.new(std.math.inf(f32), std.math.inf(f32));
    }
}

/// Remove a body from its current cells.
fn removeBodyFromCells(self: *Self, body_id: BodyId) void {
    if (body_id.index >= self.body_cells.items.len) return;

    const cell_coords = &self.body_cells.items[body_id.index];
    for (cell_coords.items) |coord| {
        if (self.cells.getPtr(coord)) |cell_bodies| {
            // Remove body from this cell
            var i: usize = 0;
            while (i < cell_bodies.items.len) {
                if (cell_bodies.items[i].index == body_id.index) {
                    _ = cell_bodies.swapRemove(i);
                    break;
                }
                i += 1;
            }
        }
    }
    cell_coords.clearRetainingCapacity();
}

/// Insert body into new cells and track them.
fn insertBodyIntoCells(self: *Self, body_id: BodyId, aabb: Aabb) !void {
    const cells = self.getOverlappingCells(aabb);

    if (body_id.index >= self.body_cells.items.len) return;
    const cell_coords = &self.body_cells.items[body_id.index];

    var y = cells.min.y;
    while (y <= cells.max.y) : (y += 1) {
        var x = cells.min.x;
        while (x <= cells.max.x) : (x += 1) {
            const coord = GridCoord{ .x = x, .y = y };

            // Track this cell for the body
            try cell_coords.append(self.allocator, coord);

            // Add body to the cell
            const result = try self.cells.getOrPut(coord);
            if (!result.found_existing) {
                result.value_ptr.* = std.ArrayList(BodyId){};
            }
            try result.value_ptr.append(self.allocator, body_id);
        }
    }
}

/// Update a body's position.
pub fn updateBody(self: *Self, body_id: BodyId, aabb: Aabb) !void {
    if (body_id.index >= self.body_positions.items.len) return;

    const current_center = aabb.getCenter();
    const last_position = &self.body_positions.items[body_id.index];

    // Check if this is the first time the body appears, due to invalid (infinite) position.
    const is_first_time = std.math.isInf(last_position.x()) or std.math.isInf(last_position.y());

    if (is_first_time) {
        // First time: Just insert and update position.
        try self.insertBodyIntoCells(body_id, aabb);
        last_position.* = current_center;
    } else {
        // Check if body moved enough to warrant an update.
        const movement = current_center.sub(last_position.*);
        const movement_threshold = self.cell_size * 0.1; // 10% of cell size

        if (@abs(movement.x()) > movement_threshold or @abs(movement.y()) > movement_threshold) {
            // Remove from old cells
            self.removeBodyFromCells(body_id);
            // Insert into new cells
            try self.insertBodyIntoCells(body_id, aabb);
            // Update cached position
            last_position.* = current_center;
        }
    }
}

/// Returns a list of potentially colliding body pairs.
pub fn getPairs(self: *Self) ![]const BodyPair {
    self.pairs.clearRetainingCapacity();
    self.seen_pairs.clearRetainingCapacity();
    self.non_empty_cells.clearRetainingCapacity();

    // Single pass: collect non-empty cells and estimate pairs
    var estimated_pairs: usize = 0;
    var iterator = self.cells.iterator();
    while (iterator.next()) |entry| {
        const body_count = entry.value_ptr.items.len;
        if (body_count > 1) {
            estimated_pairs += (body_count * (body_count - 1)) / 2;
            try self.non_empty_cells.append(self.allocator, entry.value_ptr);
        }
    }

    // Pre-allocate containers with estimated capacity
    try self.pairs.ensureTotalCapacity(self.allocator, estimated_pairs);
    try self.seen_pairs.ensureTotalCapacity(@intCast(estimated_pairs));

    // Process pairs from collected cells
    for (self.non_empty_cells.items) |body_list| {
        // Check all pairs within this cell
        for (body_list.items, 0..) |body_a, i| {
            for (body_list.items[i + 1 ..]) |body_b| {
                const pair = BodyPair.new(body_a, body_b);
                // Use assumeCapacity since we pre-allocated
                const pair_key_entry = self.seen_pairs.getOrPutAssumeCapacity(pair.key);
                if (!pair_key_entry.found_existing) {
                    self.pairs.appendAssumeCapacity(pair);
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
