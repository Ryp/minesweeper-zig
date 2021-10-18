const std = @import("std");
const assert = std.debug.assert;

const sdl2 = @import("sdl2/sdl2_backend.zig");
const minesweeper = @import("minesweeper/minesweeper.zig");

pub fn main() !void {
    // Parse arguments
    var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = &general_purpose_allocator.allocator;

    const args = try std.process.argsAlloc(gpa);
    defer std.process.argsFree(gpa, args);

    assert(args.len == 4);

    const extent_x = try std.fmt.parseUnsigned(u32, args[1], 0);
    const extent_y = try std.fmt.parseUnsigned(u32, args[2], 0);
    const mine_count = try std.fmt.parseUnsigned(u32, args[3], 0);

    // Using the method from the docs to get a reasonably random seed
    var buf: [8]u8 = undefined;
    std.crypto.random.bytes(buf[0..]);
    const seed = std.mem.readIntSliceLittle(u64, buf[0..8]);

    // Create game state
    var game_state = try minesweeper.create_game_state(.{ extent_x, extent_y }, mine_count, seed);
    defer minesweeper.destroy_game_state(&game_state);

    try sdl2.execute_main_loop(&game_state);
}
