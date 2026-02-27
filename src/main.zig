const std = @import("std");

const Reader = @import("backend/b-tree.zig").Reader;
const hexdump = @import("utils/func.zig").hexdump;
const display_record = @import("backend/b-tree.zig").display_record;
const SchemaRecord = @import("utils/schema.zig").SchemaRecord;
const parse_record = @import("backend/record.zig").parse_record;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();
    const allocator = arena.allocator();

    const args = try std.process.argsAlloc(allocator);

    if (args.len < 3) {
        try std.io.getStdErr().writer().print(
            "Usage: {s} <file_path> <command>\n",
            .{args[0]},
        );
        return;
    }

    const file_path = args[1];
    const cmd = args[2];

    if (std.mem.eql(u8, cmd, ".dbinfo")) {
        var reader = try Reader.init(file_path);
        defer reader.deinit();
        const stdout = std.io.getStdOut().writer();

        // info
        try stdout.print("database page size: {d}\n", .{reader.page_size});
        try stdout.print("database page count: {d}\n", .{reader.database_size});

        // page -> 1
        const page1 = try reader.read_page(1, allocator);

        const header = try Reader.parse_page_header(page1, true);
        try stdout.print("Page type: {}\n", .{header.page_type});
        try stdout.print("Cell count: {}\n", .{header.cell_count});
        try stdout.print("Cell content offset: {}\n", .{header.cell_content_start});

        // cell
        const cells = try Reader.parse_cells(page1, true, allocator);

        try stdout.print("Number of cells on page 1: {}\n", .{cells.len});

        for (cells, 0..) |cell, i| {
            try stdout.print("Cell {}: ", .{i});
            switch (cell) {
                .interior_index => |c| {
                    try stdout.print("InteriorIndex (left child: {}, payload_size: {})\n", .{ c.left_child_ptr, c.payload_size });
                    try display_record(cell, allocator, stdout);
                },
                .interior_table => |c| {
                    try stdout.print("InteriorTable (left child: {}, rowid: {})\n", .{ c.left_child_ptr, c.row_id });
                    try display_record(cell, allocator, stdout);
                },
                .leaf_index => |c| {
                    try stdout.print("LeafIndex (payload_size: {})\n", .{c.payload_size});
                    try display_record(cell, allocator, stdout);
                },
                .leaf_table => |c| {
                    try stdout.print("LeafTable (rowid: {}, payload_size: {})\n", .{ c.row_id, c.payload_size });
                    try display_record(cell, allocator, stdout);
                },
            }
        }
    } else if (std.mem.eql(u8, cmd, ".tables")) {
        var reader = try Reader.init(file_path);
        defer reader.deinit();
        const stdout = std.io.getStdOut().writer();

        const page1 = try reader.read_page(1, allocator);
        const cells = try Reader.parse_cells(page1, true, allocator);

        var schema_records = std.ArrayList(SchemaRecord).init(allocator);

        // extract data and parse into records
        for (cells) |cell| {
            const payload = switch (cell) {
                .leaf_table => |c| c.payload,
                else => continue, // Schema records are stored in leaf_table cells
            };

            const values = try parse_record(allocator, payload);
            const record = try SchemaRecord.from_record(values);

            try schema_records.append(record);
        }

        // print table names
        for (schema_records.items) |record| {
            std.debug.print("DEBUG: type='{s}', name='{s}'\n", .{ record.type, record.name });
            if (std.mem.eql(u8, record.type, "table") and
                !std.mem.startsWith(u8, record.name, "sqlite_"))
            {
                try stdout.print("{s} ", .{record.name});
            }
        }
        try stdout.print("\n", .{});
    }
}
