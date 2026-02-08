const std = @import("std");
const MAGIC_HEADER = @import("../utils/constant.zig").MAGIC_HEADER;
const HEADER_SIZE = @import("../utils/constant.zig").HEADER_SIZE;
const read_variant = @import("../utils/func.zig").read_variant;

pub const PageType = enum(u8) {
    interior_index = 2,
    interior_table = 5,
    leaf_index = 10,
    leaf_table = 13,
};

// leaf - contains actual dat
// interior - contains pointers to other pages
pub const CellType = union(PageType) {
    interior_index: struct {
        left_child_ptr: u32,
        payload_size: u64,
        payload: []const u8,
    },
    interior_table: struct {
        left_child_ptr: u32,
        row_id: u64,
    },
    leaf_index: struct {
        payload_size: u64,
        payload: []const u8,
    },
    leaf_table: struct {
        payload_size: u64,
        row_id: u64,
        payload: []const u8,
    },
};

pub const PageHeader = struct {
    page_type: PageType,
    first_freeblock: u16, // The byte offset to the first "freeblock" in the page.
    // SQLite manages deleted or unused space within a page using a linked list;
    // if this is 0, there are no freeblocks.
    cell_count: u16,
    cell_content_start: u16, // data is usually filled bottom up
    fragmented_free_bytes: u8, // The number of "lost" bytes within the cell content area.
    // These are gaps too small to be added to the freeblock list.
    right_ptr: ?u32,
};

pub const Reader = struct {
    file: std.fs.File,
    page_size: u16,
    database_size: u32,

    pub fn init(filename: []const u8) !Reader {
        const file = try std.fs.cwd().openFile(filename, .{});
        errdefer file.close();

        var header: [100]u8 = undefined;
        const bytes_read = try file.readAll(&header);

        if (bytes_read < 100) return error.InvalidFile;

        if (!std.mem.eql(u8, header[0..16], MAGIC_HEADER)) {
            return error.InvalidMagicHeader;
        }

        const page_size = std.mem.readInt(u16, header[16..18], .big);
        const database_size = std.mem.readInt(u32, header[28..32], .big);

        return Reader{
            .file = file,
            .page_size = page_size,
            .database_size = database_size,
        };
    }

    pub fn deinit(self: *Reader) void {
        self.file.close();
    }

    pub fn read_page(self: *Reader, page_number: u32, allocator: std.mem.Allocator) ![]u8 {
        if (page_number == 0) return error.InvalidPageNumber;

        const offset = (page_number - 1) * self.page_size;
        try self.file.seekTo(offset);

        const page = try allocator.alloc(u8, self.page_size);
        errdefer allocator.free(page);

        const read_bytes = try self.file.readAll(page);
        if (read_bytes != self.page_size) {
            return error.IncompleteRead;
        }
        return page;
    }

    pub fn parse_page_header(page: []const u8, is_page_1: bool) !PageHeader {
        const offset: usize = if (is_page_1) 100 else 0;

        if (page.len < offset + 8) {
            return error.CorruptedData;
        }

        const page_type = switch (page[offset]) {
            2 => PageType.interior_index,
            5 => PageType.interior_table,
            10 => PageType.leaf_index,
            13 => PageType.leaf_table,
            else => return error.InvalidPageType,
        };

        var header = PageHeader{
            .page_type = page_type,
            .first_freeblock = std.mem.readInt(u16, page[offset + 1 ..][0..2], .big),
            .cell_count = std.mem.readInt(u16, page[offset + 3 ..][0..2], .big),
            .cell_content_start = std.mem.readInt(u16, page[offset + 5 ..][0..2], .big),
            .fragmented_free_bytes = page[offset + 7],
            .right_ptr = null,
        };

        if (header.page_type == .interior_index or header.page_type == .interior_table) {
            if (page.len < offset + 12) {
                return error.InvalidPage;
            }
            header.right_ptr = std.mem.readInt(u32, page[offset + 8 ..][0..4], .big);
        }
        return header;
    }

    pub fn parse_cell(page: []const u8, page_type: PageType, cell_offset: u16, allocator: std.mem.Allocator) !CellType {
        var fbs = std.io.fixedBufferStream(page[cell_offset..]);
        var reader = fbs.reader();

        switch (page_type) {
            .interior_index => {
                const left_child_ptr = try reader.readInt(u32, .big);
                const payload_size = try read_variant(&reader);
                const payload = try allocator.alloc(u8, @intCast(payload_size));
                _ = try reader.readAll(payload);
                return CellType{
                    .interior_index = .{
                        .left_child_ptr = left_child_ptr,
                        .payload_size = payload_size,
                        .payload = payload,
                    },
                };
            },
            .interior_table => {
                const left_child_ptr = try reader.readInt(u32, .big);
                const rowid = try read_variant(&reader);
                return CellType{
                    .interior_table = .{
                        .left_child_ptr = left_child_ptr,
                        .row_id = rowid,
                    },
                };
            },
            .leaf_index => {
                const payload_size = try read_variant(&reader);
                const payload = try allocator.alloc(u8, @intCast(payload_size));
                _ = try reader.readAll(payload);
                return CellType{
                    .leaf_index = .{
                        .payload_size = payload_size,
                        .payload = payload,
                    },
                };
            },
            .leaf_table => {
                const payload_size = try read_variant(&reader);
                const rowid = try read_variant(&reader);
                const payload = try allocator.alloc(u8, @intCast(payload_size));
                _ = try reader.readAll(payload);
                return CellType{
                    .leaf_table = .{
                        .payload_size = payload_size,
                        .row_id = rowid,
                        .payload = payload,
                    },
                };
            },
        }
    }

    pub fn parse_cells(page: []const u8, is_page_1: bool, alloc: std.mem.Allocator) ![]CellType {
        const header = try Reader.parse_page_header(page, is_page_1);

        const cells = try alloc.alloc(CellType, header.cell_count);
        errdefer alloc.free(cells);

        const page_start_offset: usize = if (is_page_1) 100 else 0;
        const header_size: usize = if (header.right_ptr != null) 12 else 8;
        const cell_ptr_arr_offset = page_start_offset + header_size;

        var cell_ptr_stream = std.io.fixedBufferStream(page[cell_ptr_arr_offset..]);
        var cell_ptr_reader = cell_ptr_stream.reader();

        for (cells) |*cell| {
            const cell_offset = try cell_ptr_reader.readInt(u16, .big);
            cell.* = try Reader.parse_cell(page, header.page_type, cell_offset, alloc);
        }

        return cells;
    }
};
