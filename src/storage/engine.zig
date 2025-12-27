const std = @import("std");

pub const Storage = struct {
    data: std.StringArrayHashMap([]const u8),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Storage {
        return .{
            .data = std.StringArrayHashMap([]const u8).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn set(self: *Storage, key: []const u8, value: []const u8) !void {
        const key_copy = try self.allocator.dupe(u8, key);
        const value_copy = try self.allocator.dupe(u8, value);
        try self.data.put(key_copy, value_copy);
    }

    pub fn get(self: *Storage, key: []const u8) ?[]const u8 {
        return self.data.get(key);
    }

    pub fn del(self: *Storage, key: []const u8) bool {
        return self.data.fetchSwapRemove(key) != null;
    }

    pub fn deinit(self: *Storage) void {
        self.data.deinit();
    }
};

test "storage set and get" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    var storage = Storage.init(arena.allocator());

    try storage.set("key1", "value1");
    const value = storage.get("key1");
    try std.testing.expect(value != null);
    try std.testing.expectEqualStrings("value1", value.?);

    storage.deinit();
}

test "storage delete" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    var storage = Storage.init(arena.allocator());

    try storage.set("key2", "value2");
    const value_before = storage.get("key2");
    try std.testing.expect(value_before != null);

    const deleted = storage.del("key2");
    try std.testing.expect(deleted);
    const value_after = storage.get("key2");
    try std.testing.expect(value_after == null);

    storage.deinit();
}
