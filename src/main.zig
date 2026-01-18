const std = @import("std");

const Reader = @import("backend/b-tree.zig").Reader;
const hexdump = @import("utils/func.zig").hexdump;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

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
        defer allocator.free(page1);

        const header = try Reader.parse_page_header(page1, true);
        try stdout.print("Page type: {}\n", .{header.page_type});
        try stdout.print("Cell count: {}\n", .{header.cell_count});
        try stdout.print("Cell content offset: {}\n", .{header.cell_content_start});

        // cell
        const cells = try Reader.parse_cells(page1, true, allocator);
        defer {
            for (cells) |cell| {
                switch (cell) {
                    .leaf_table => |c| allocator.free(c.payload),
                    .leaf_index => |c| allocator.free(c.payload),
                    .interior_index => |c| allocator.free(c.payload),
                    .interior_table => {},
                }
            }
            allocator.free(cells);
        }

        try stdout.print("Number of cells on page 1: {}\n", .{cells.len});

        for (cells, 0..) |cell, i| {
            try stdout.print("Cell {}: ", .{i});
            switch (cell) {
                .interior_index => |c| try stdout.print("InteriorIndex (left child: {}, payload_size: {})\n", .{ c.left_child_ptr, c.payload_size }),
                .interior_table => |c| try stdout.print("InteriorTable (left child: {}, rowid: {})\n", .{ c.left_child_ptr, c.row_id }),
                .leaf_index => |c| try stdout.print("LeafIndex (payload_size: {})\n", .{c.payload_size}),
                .leaf_table => |c| try stdout.print("LeafTable (rowid: {}, payload_size: {})\n", .{ c.row_id, c.payload_size }),
            }
        }
    }
}
