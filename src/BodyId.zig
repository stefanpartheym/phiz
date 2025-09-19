const Self = @This();

index: usize,

pub fn new(index: usize) Self {
    return .{ .index = index };
}
