const std = @import("std");
const assert = std.debug.assert;

//const chip8 = @import("chip8/chip8.zig");
//const sdl2 = @import("sdl2/sdl2_backend.zig");
const minesweeper = @import("game/minesweeper.zig");

pub fn main() !void {
    var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = &general_purpose_allocator.allocator;

    const args = try std.process.argsAlloc(gpa);
    defer std.process.argsFree(gpa, args);

    assert(args.len == 4);

    const extent_x = try std.fmt.parseUnsigned(u16, args[1], 0);
    const extent_y = try std.fmt.parseUnsigned(u16, args[2], 0);
    const mine_count = try std.fmt.parseUnsigned(u16, args[3], 0);
    const start_x: u16 = 1;
    const start_y: u16 = 1;
    var rng = std.rand.DefaultPrng.init(0x42424242); // FIXME

    var board = try minesweeper.create_board(extent_x, extent_y);
    defer minesweeper.destroy_board(board);

    minesweeper.fill_mines(board, start_x, start_y, mine_count, &rng.random);

    //    try sdl2.execute_main_loop(board, config);
}
