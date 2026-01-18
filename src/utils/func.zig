const std = @import("std");

pub fn read_variant(reader: anytype) !u64 {
    var result: u64 = 0;
    var shift: u6 = 0;

    while (true) {
        const byte = try reader.readByte();
        result |= @as(u64, byte & 0x7F) << shift;
        if (byte & 0x80 == 0) break;
        shift += 7;
        if (shift >= 64) return error.VarintTooLarge;
    }

    return result;
}

pub fn variant_size(value: u64) usize {
    if (value < 128) return 1;
    var size: usize = 1;
    var v = value >> 7;
    while (v > 0) : (v >>= 7) {
        size += 1;
    }
    return size;
}
