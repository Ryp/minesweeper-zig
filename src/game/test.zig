const std = @import("std");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

const minesweeper = @import("minesweeper.zig");

test "Critical path" {
    const extent_x: u16 = 2;
    const extent_y: u16 = 2;
    const mine_count: u16 = 2;
    const start_x: u16 = 1;
    const start_y: u16 = 1;

    var rng = std.rand.DefaultPrng.init(0x42424242); // FIXME

    var game_state = try minesweeper.create_game_state(extent_x, extent_y, mine_count, &rng.random);
    defer minesweeper.destroy_game_state(&game_state);

    minesweeper.uncover(&game_state, start_x, start_y);

    try expectEqual(game_state.last_move_result, minesweeper.UncoverResult.Continue);
    try expectEqual(game_state.board[start_x][start_y].is_covered, false);

    minesweeper.uncover(&game_state, 0, 0);

    try expect(game_state.last_move_result != minesweeper.UncoverResult.Continue);
}

test "Big uncover" {
    const extent_x: u16 = 100;
    const extent_y: u16 = 100;
    const mine_count: u16 = 1;
    const start_x: u16 = 25;
    const start_y: u16 = 25;

    var rng = std.rand.DefaultPrng.init(0x42424242); // FIXME

    var game_state = try minesweeper.create_game_state(extent_x, extent_y, mine_count, &rng.random);
    defer minesweeper.destroy_game_state(&game_state);

    minesweeper.uncover(&game_state, start_x, start_y);
}
