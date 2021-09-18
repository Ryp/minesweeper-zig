const std = @import("std");
const assert = std.debug.assert;

const sdl2 = @import("sdl2/sdl2_backend.zig");
const minesweeper = @import("minesweeper/game.zig");

pub fn main() !void {
    var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = &general_purpose_allocator.allocator;

    const args = try std.process.argsAlloc(gpa);
    defer std.process.argsFree(gpa, args);

    assert(args.len == 4);

    const extent_x = try std.fmt.parseUnsigned(u16, args[1], 0);
    const extent_y = try std.fmt.parseUnsigned(u16, args[2], 0);
    const mine_count = try std.fmt.parseUnsigned(u16, args[3], 0);

    var rng = std.rand.DefaultPrng.init(0x42424242); // FIXME

    var game_state = try minesweeper.create_game_state(extent_x, extent_y, mine_count, &rng.random);
    defer minesweeper.destroy_game_state(&game_state);

    try sdl2.execute_main_loop(&game_state);
}
