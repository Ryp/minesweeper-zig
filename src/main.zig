const std = @import("std");
const builtin = @import("builtin");
const assert = std.debug.assert;
const native_endian = builtin.cpu.arch.endian();

const game = @import("minesweeper/game.zig");
const backend = @import("sdl_backend.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    // Parse arguments
    const args = try std.process.argsAlloc(gpa.allocator());
    defer std.process.argsFree(gpa.allocator(), args);

    assert(args.len == 4);

    const extent_x = try std.fmt.parseUnsigned(u32, args[1], 0);
    const extent_y = try std.fmt.parseUnsigned(u32, args[2], 0);
    const mine_count = try std.fmt.parseUnsigned(u32, args[3], 0);

    // Using the method from the docs to get a reasonably random seed
    var buf: [8]u8 = undefined;
    std.crypto.random.bytes(buf[0..]);
    const seed = std.mem.readInt(u64, buf[0..8], native_endian);

    // Create game state
    var game_state = try game.create_game_state(gpa.allocator(), .{ extent_x, extent_y }, mine_count, seed);
    defer game.destroy_game_state(gpa.allocator(), &game_state);

    try backend.execute_main_loop(gpa.allocator(), &game_state);
}
