const std = @import("std");
const resp = @import("../protocol/resp.zig");
const storage = @import("../storage/engine.zig");

pub fn execute(
    cmd: []const resp.RespValue,
    store: *storage.Storage,
) !resp.RespValue {
    if (cmd.len == 0) {
        return resp.RespValue{ .err = "ERR empty command" };
    }

    const command = cmd[0];
    if (command.bulk_str == null) {
        return resp.RespValue{ .err = "ERR invalid command" };
    }

    if (std.mem.eql(u8, command.bulk_str.?, "PING")) {
        if (cmd.len > 1) {
            const message = cmd[1].bulk_str orelse return resp.RespValue{ .err = "ERR invalid argument for 'PING' command" };
            return resp.RespValue{ .bulk_str = message };
        }
        return resp.RespValue{ .simple_str = "PONG" };
    } else if (std.mem.eql(u8, command.bulk_str.?, "SET")) {
        if (cmd.len != 3) {
            return resp.RespValue{ .err = "ERR wrong number of arguments for 'SET' command" };
        }
        const key = cmd[1].bulk_str orelse return resp.RespValue{ .err = "ERR invalid key" };
        const value = cmd[2].bulk_str orelse return resp.RespValue{ .err = "ERR invalid value" };
        try store.set(key, value);
        return resp.RespValue{ .simple_str = "OK" };
    } else if (std.mem.eql(u8, command.bulk_str.?, "GET")) {
        if (cmd.len != 2) {
            return resp.RespValue{ .err = "ERR wrong number of arguments for 'GET' command" };
        }
        const key = cmd[1].bulk_str orelse return resp.RespValue{ .err = "ERR invalid key" };
        const value = store.get(key);
        if (value == null) {
            return resp.RespValue{ .bulk_str = null };
        } else {
            return resp.RespValue{ .bulk_str = value.? };
        }
    } else {
        return resp.RespValue{ .err = "ERR unknown command" };
    }
}

test "execute PING command" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    var store = storage.Storage.init(arena.allocator());

    var cmd = [_]resp.RespValue{
        resp.RespValue{ .bulk_str = "PING" },
    };
    const result = try execute(&cmd, &store);
    try std.testing.expectEqualStrings("PONG", result.simple_str);

    store.deinit();
}

test "execute SET and GET commands" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    var store = storage.Storage.init(arena.allocator());

    var set_cmd = [_]resp.RespValue{
        resp.RespValue{ .bulk_str = "SET" },
        resp.RespValue{ .bulk_str = "mykey" },
        resp.RespValue{ .bulk_str = "myvalue" },
    };
    const set_result = try execute(&set_cmd, &store);
    try std.testing.expectEqualStrings("OK", set_result.simple_str);

    var get_cmd = [_]resp.RespValue{
        resp.RespValue{ .bulk_str = "GET" },
        resp.RespValue{ .bulk_str = "mykey" },
    };
    const get_result = try execute(&get_cmd, &store);
    try std.testing.expectEqualStrings("myvalue", get_result.bulk_str.?);

    store.deinit();
}

test "execute PING with message" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    var store = storage.Storage.init(arena.allocator());

    var cmd = [_]resp.RespValue{
        resp.RespValue{ .bulk_str = "PING" },
        resp.RespValue{ .bulk_str = "Hello" },
    };
    const result = try execute(&cmd, &store);
    try std.testing.expectEqualStrings("Hello", result.bulk_str.?);

    store.deinit();
}
