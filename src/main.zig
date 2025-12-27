const std = @import("std");
const resp = @import("protocol/resp.zig");
const storage = @import("storage/engine.zig");
const server = @import("server.zig");

pub fn main() !void {
    try server.run();
}

test {
    _ = @import("storage/engine.zig");
    _ = @import("protocol/resp.zig");
    _ = @import("protocol/command.zig");
}

test "parse simple array" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    var parser = resp.Parser.init("*1\r\n$4\r\nPING\r\n", arena.allocator());
    const result = try parser.parse();

    try std.testing.expect(result.array != null);
    try std.testing.expect(result.array.?.len == 1);

    const first = result.array.?[0];
    try std.testing.expect(first.bulk_str != null);
}

test "parse nested array" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    var parser = resp.Parser.init("*2\r\n*1\r\n+OK\r\n$5\r\nHello\r\n", arena.allocator());
    const result = try parser.parse();

    try std.testing.expect(result.array != null);
    try std.testing.expect(result.array.?.len == 2);

    const first = result.array.?[0];
    try std.testing.expect(first.array != null);
    try std.testing.expect(first.array.?.len == 1);
    const nested_first = first.array.?[0];
    try std.testing.expectEqualStrings("OK", nested_first.simple_str);

    const second = result.array.?[1];
    try std.testing.expect(second.bulk_str != null);
    try std.testing.expectEqualStrings("Hello", second.bulk_str.?);
}
