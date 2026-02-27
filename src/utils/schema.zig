const std = @import("std");
const Value = @import("../backend/record.zig").Value;
const Reader = @import("../backend/b-tree.zig").Reader;
const parse_record = @import("../backend/record.zig").parse_record;

pub const SchemaRecord = struct {
    type: []const u8,
    name: []const u8,
    tbl_name: []const u8,
    rootpage: u32,
    sql: []const u8,

    pub fn from_record(values: []const Value) !SchemaRecord {
        if (values.len < 5) return error.InvalidSchemaRecord;

        const rec_type = switch (values[0]) {
            .string, .blob => |s| s,
            else => return error.InvalidSchemaRecord,
        };
        const rec_name = switch (values[1]) {
            .string, .blob => |s| s,
            else => return error.InvalidSchemaRecord,
        };
        const rec_tbl_name = switch (values[2]) {
            .string, .blob => |s| s,
            else => return error.InvalidSchemaRecord,
        };

        const rec_rootpage = switch (values[3]) {
            .int => |i| @as(u32, @intCast(i)),
            .null => 0,
            else => return error.InvalidSchemaRecord,
        };

        const rec_sql = switch (values[4]) {
            .string, .blob => |s| s,
            .null => "",
            else => return error.InvalidSchemaRecord,
        };

        return SchemaRecord{
            .type = rec_type,
            .name = rec_name,
            .tbl_name = rec_tbl_name,
            .rootpage = rec_rootpage,
            .sql = rec_sql,
        };
    }
};
