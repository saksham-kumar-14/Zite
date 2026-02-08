const std = @import("std");
const read_variant = @import("../utils/func.zig").read_variant;

pub const Value = union(enum) {
    null: void,
    int: i64,
    float: f64,
    string: []const u8,
    blob: []const u8,
};

pub fn parse_record(allocator: std.mem.Allocator, payload: []const u8) ![]Value {
    var fbs = std.io.fixedBufferStream(payload);
    var reader = fbs.reader();

    const header_size = try read_variant(&reader);

    var serial_types = std.ArrayList(u64).init(allocator);
    defer serial_types.deinit();

    while (fbs.pos < header_size) {
        try serial_types.append(try read_variant(&reader));
    }

    var values = try allocator.alloc(Value, serial_types.items.len);
    errdefer allocator.free(values);

    for (serial_types.items, 0..) |stype, i| {
        values[i] = switch (stype) {
            0 => .null,
            1 => Value{ .int = try reader.readInt(i8, .big) },
            2 => Value{ .int = try reader.readInt(i16, .big) },
            3 => blk: {
                const bytes = try reader.readBytesNoEof(3);
                const res = (@as(i32, bytes[0]) << 16) | (@as(i32, bytes[1]) << 8) | @as(i32, bytes[2]);
                break :blk Value{ .int = res };
            },
            4 => Value{ .int = try reader.readInt(i32, .big) },
            5 => blk: {
                const bytes = try reader.readBytesNoEof(6);
                var res: i64 = 0;
                for (bytes) |byte| res = (res << 8) | byte;
                break :blk Value{ .int = res };
            },
            6 => Value{ .int = try reader.readInt(i64, .big) },
            7 => Value{ .float = @bitCast(try reader.readInt(u64, .big)) },
            8 => Value{ .int = 0 },
            9 => Value{ .int = 1 },
            10, 11 => return error.InternalReservedTypes,
            else => blk: {
                if (stype >= 13 and (stype % 2 == 1)) {
                    const len = (stype - 13) / 2;
                    const buf = try allocator.alloc(u8, len);
                    _ = try reader.readAll(buf);
                    break :blk Value{ .string = buf };
                } else if (stype >= 12 and (stype % 2 == 0)) {
                    const len = (stype - 12) / 2;
                    const buf = try allocator.alloc(u8, len);
                    _ = try reader.readAll(buf);
                    break :blk Value{ .blob = buf };
                } else {
                    return error.UnsupportedType;
                }
            },
        };
    }
    return values;
}
