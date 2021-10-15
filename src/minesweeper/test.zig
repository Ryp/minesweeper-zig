const std = @import("std");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

const minesweeper = @import("game.zig");

const test_seed: u64 = 0xC0FFEE42DEADBEEF;

test "Critical path" {
    const extent_x: u16 = 5;
    const extent_y: u16 = 5;
    const mine_count: u16 = 2;
    const start_x: u16 = 2;
    const start_y: u16 = 2;

    var rng = std.rand.DefaultPrng.init(test_seed);

    var game_state = try minesweeper.create_game_state(extent_x, extent_y, mine_count, &rng.random);
    defer minesweeper.destroy_game_state(&game_state);

    minesweeper.uncover(&game_state, .{ .x = start_x, .y = start_y });

    try expectEqual(game_state.is_ended, false);
    try expectEqual(game_state.board[start_x][start_y].is_covered, false);

    minesweeper.uncover(&game_state, .{ .x = 0, .y = 1 });

    try expectEqual(game_state.is_ended, true);
    try expectEqual(game_state.board[0][1].is_covered, false);
}

test "Big uncover" {
    const extent_x: u16 = 100;
    const extent_y: u16 = 100;
    const mine_count: u16 = 1;
    const start_x: u16 = 25;
    const start_y: u16 = 25;

    var rng = std.rand.DefaultPrng.init(test_seed);

    var game_state = try minesweeper.create_game_state(extent_x, extent_y, mine_count, &rng.random);
    defer minesweeper.destroy_game_state(&game_state);

    minesweeper.uncover(&game_state, .{ .x = start_x, .y = start_y });

    try expect(game_state.event_history[0] == minesweeper.GameEventTag.discover_many);
}

test "Number uncover" {
    const extent_x: u16 = 5;
    const extent_y: u16 = 5;
    const mine_count: u16 = 3;

    var rng = std.rand.DefaultPrng.init(test_seed);

    var game_state = try minesweeper.create_game_state(extent_x, extent_y, mine_count, &rng.random);
    defer minesweeper.destroy_game_state(&game_state);

    minesweeper.uncover(&game_state, .{ .x = 0, .y = 0 });
    minesweeper.toggle_flag(&game_state, .{ .x = 0, .y = 2 });
    minesweeper.uncover(&game_state, .{ .x = 1, .y = 1 });

    try expect(game_state.event_history[0] == minesweeper.GameEventTag.discover_many);
    try expect(game_state.event_history[1] == minesweeper.GameEventTag.discover_number);
    try expect(game_state.event_history[2] == minesweeper.GameEventTag.discover_single);
    try expect(game_state.event_history[3] == minesweeper.GameEventTag.discover_single);
    try expectEqual(game_state.is_ended, false);
}
