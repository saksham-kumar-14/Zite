const std = @import("std");
const read_variant = @import("../utils/func.zig").read_variant;

pub const Value = union(enum) {
    null: void,
    int: i64,
    float: f64,
    string: []const u8,
    blob: []const u8,
};

pub fn parseRecord(allocator: std.mem.Allocator, payload: []const u8) ![]Value {
    var fbs = std.io.fixedBufferStream(payload);
    var reader = fbs.reader();

    const header_size = try read_variant(&reader);

    // parse serial types
    var serial_types = std.ArrayList(u64).init(allocator);
    defer serial_types.deinit();
    while (fbs.pos < header_size) {
        try serial_types.append(try read_variant(&reader));
    }

    // parse data based on the serial type
    var values = try allocator.alloc(Value, serial_types.items.len);
    for (serial_types.items.len, 0..) |serial_type, i| {
        values[i] = switch (serial_type) {
            0 => null,
            1 => Value{ .int = try reader.readInt(i8, .big) },
            2 => Value{ .int = try reader.readInt(i16, .big) },
            3 => Value{ .int = try reader.readInt(i24, .big) },
            4 => Value{ .int = try reader.readInt(i32, .big) },
            5 => Value{ .int = try reader.readInt(i48, .big) },
            6 => Value{ .int = try reader.readInt(i64, .big) },
            7 => Value{ .int = try reader.readInt(f64, .big) },
            8 => Value{ .int = 0 },
            9 => Value{ .int = 1 },
            else => if (serial_type >= 13 and (serial_type % 2 == 1)) { // string
                const len = (serial_type - 13) / 2;
                const buf = try allocator.alloc(u8, len);
                _ = try reader.readAll(buf);
                return Value{ .string = buf };
            } else { // blob
                return error.UnsupportedType;
            },
        };
    }
    return values;
}
