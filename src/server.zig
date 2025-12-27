const std = @import("std");
const posix = std.posix;
const net = std.net;

const parser = @import("protocol/resp.zig").Parser;
const resp_serialize = @import("protocol/resp.zig").serialize;
const command = @import("protocol/command.zig");
const storage = @import("storage/engine.zig");

pub fn run() !void {
    const addr = net.Address.initIp4(.{ 0, 0, 0, 0 }, 6379);
    const server = try posix.socket(posix.AF.INET, posix.SOCK.STREAM, 0);
    defer posix.close(server);

    // bind & listen
    try posix.bind(server, &addr.any, addr.getOsSockLen());
    try posix.listen(server, 128);

    std.debug.print("Server listening on port 6379\n", .{});

    var store = storage.Storage.init(std.heap.page_allocator);
    defer store.deinit();

    while (true) {
        // accept
        const client = try posix.accept(server, null, null, 0);
        defer posix.close(client);

        var buffer: [4096]u8 = undefined;

        while (true) {
            const n = try posix.read(
                client,
                &buffer,
            );
            if (n == 0) {
                break; // connection closed
            }
            std.debug.print("Received {d} bytes\n", .{n});

            var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            defer arena.deinit();

            var parser_instance = parser.init(buffer[0..n], arena.allocator());
            const resp_value = try parser_instance.parse();
            const items = resp_value.array orelse {
                std.debug.print("Invalid command format\n", .{});
                break;
            };
            const result = try command.execute(
                items,
                &store,
            );

            // Serialize response
            var res_buffer: [4096]u8 = undefined;
            var stream = std.io.fixedBufferStream(&res_buffer);
            try resp_serialize(result, stream.writer());
            const response = stream.getWritten();

            // Send response
            _ = try posix.write(client, response);
        }

        std.debug.print("Client disconnected\n", .{});
    }
}
