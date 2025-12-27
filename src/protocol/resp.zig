const std = @import("std");

pub const RespValue = union(enum) {
    simple_str: []const u8,
    err: []const u8,
    integer: i64,
    bulk_str: ?[]const u8,
    array: ?[]RespValue,
};

pub const ParsedError = error{
    UnexpectedEnd,
    InvalidType,
    InvalidInteger,
    InvalidLength,
    OutOfMemory,
};

pub const Parser = struct {
    input: []const u8,
    position: usize,
    allocator: std.mem.Allocator,

    pub fn init(input: []const u8, allocator: std.mem.Allocator) Parser {
        return Parser{
            .input = input,
            .position = 0,
            .allocator = allocator,
        };
    }

    pub fn parse(self: *Parser) ParsedError!RespValue {
        const byte = self.peek() orelse return ParsedError.UnexpectedEnd;

        switch (byte) {
            // Array
            '*' => {
                // read array length
                const count = try self.readInteger();
                if (count < 0) {
                    return RespValue{ .array = null };
                }
                const count_usize: usize = @intCast(count);
                var items = try self.allocator.alloc(RespValue, count_usize);
                for (0..count_usize) |items_index| {
                    items[items_index] = try self.parse();
                }
                return RespValue{ .array = items };
            },
            // Simple String
            '+' => {
                self.position += 1;
                const start = self.position;
                while (self.position < self.input.len and self.input[self.position] != '\r') {
                    self.position += 1;
                }
                if (self.position + 1 >= self.input.len or self.input[self.position] != '\r' or self.input[self.position + 1] != '\n') {
                    return ParsedError.UnexpectedEnd;
                }
                const str = self.input[start..self.position];
                self.position += 2; // Skip \r\n
                return RespValue{ .simple_str = str };
            },
            // Bulk String
            '$' => {
                const length = try self.readInteger();
                if (length < 0) {
                    return RespValue{ .bulk_str = null };
                }
                const length_usize: usize = @intCast(length);
                if (self.position + length_usize + 2 > self.input.len) {
                    return ParsedError.UnexpectedEnd;
                }
                const str = self.input[self.position .. self.position + length_usize];
                self.position += length_usize;
                if (self.position + 1 >= self.input.len or self.input[self.position] != '\r' or self.input[self.position + 1] != '\n') {
                    return ParsedError.UnexpectedEnd;
                }
                self.position += 2; // Skip \r\n
                return RespValue{ .bulk_str = str };
            },
            // Integer
            ':' => {
                const int_value = try self.readInteger();
                return RespValue{ .integer = int_value };
            },
            // Error
            else => return ParsedError.InvalidType,
        }
    }
    // Explain
    // Reads an integer from the current position in the input.
    // It expects the integer to be prefixed by a type byte (e.g., '*', '$') and terminated by \r\n.
    // It updates the parser's position accordingly.
    fn readInteger(self: *Parser) ParsedError!i64 {
        self.position += 1; // Skip the type byte
        const start = self.position;
        while (self.position < self.input.len and self.input[self.position] != '\r') {
            self.position += 1;
        }
        if (self.position + 1 >= self.input.len or self.input[self.position] != '\r' or self.input[self.position + 1] != '\n') {
            return ParsedError.UnexpectedEnd;
        }
        const int_str = self.input[start..self.position];
        self.position += 2; // Skip \r\n

        const parsed = std.fmt.parseInt(i64, int_str, 10) catch return ParsedError.InvalidInteger;
        return parsed;
    }

    pub fn peek(self: Parser) ?u8 {
        if (self.position >= self.input.len) {
            return null;
        }
        return self.input[self.position];
    }
};

pub fn serialize(value: RespValue, writer: anytype) !void {
    switch (value) {
        .simple_str => |str| try writer.print("+{s}\r\n", .{str}),
        .err => |e| try writer.print("-{s}\r\n", .{e}),
        .integer => |n| try writer.print(":{d}\r\n", .{n}),
        .bulk_str => |opt| {
            if (opt) |s| {
                try writer.print("${d}\r\n{s}\r\n", .{ s.len, s });
            } else {
                try writer.writeAll("$-1\r\n");
            }
        },
        .array => |opt| {
            if (opt) |arr| {
                try writer.print("*{d}\r\n", .{arr.len});
                for (arr) |item| try serialize(item, writer);
            } else {
                try writer.writeAll("*-1\r\n");
            }
        },
    }
}
