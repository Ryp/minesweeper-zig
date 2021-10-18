const std = @import("std");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

usingnamespace @import("game.zig");
usingnamespace @import("event.zig");

const test_seed: u64 = 0xC0FFEE42DEADBEEF;

test "Critical path" {
    const extent = u32_2{ 5, 5 };
    const mine_count: u32 = 2;
    const uncover_pos_0 = u16_2{ 2, 2 };
    const uncover_pos_1 = u16_2{ 0, 1 };

    var game_state = try create_game_state(extent, mine_count, test_seed);
    defer destroy_game_state(&game_state);

    uncover(&game_state, uncover_pos_0);

    try expectEqual(game_state.is_ended, false);
    try expectEqual(cell_at(&game_state, uncover_pos_0).is_covered, false);

    uncover(&game_state, uncover_pos_1);

    try expectEqual(game_state.is_ended, true);
    try expectEqual(cell_at(&game_state, uncover_pos_1).is_covered, false);
}

test "Toggle flag" {
    const extent = u32_2{ 5, 5 };
    const mine_count: u32 = 2;
    const uncover_pos_0 = u16_2{ 2, 2 };
    const uncover_pos_1 = u16_2{ 0, 1 };

    var game_state = try create_game_state(extent, mine_count, test_seed);
    defer destroy_game_state(&game_state);

    uncover(&game_state, uncover_pos_0);
    try expectEqual(cell_at(&game_state, uncover_pos_0).is_covered, false);

    toggle_flag(&game_state, uncover_pos_1);
    uncover(&game_state, uncover_pos_1);
    try expectEqual(cell_at(&game_state, uncover_pos_1).is_covered, true);

    toggle_flag(&game_state, uncover_pos_1);
    uncover(&game_state, uncover_pos_1);
    try expectEqual(cell_at(&game_state, uncover_pos_1).is_covered, false);
}

test "Big uncover" {
    const extent = u32_2{ 100, 100 };
    const mine_count: u32 = 1;
    const start_pos = u16_2{ 25, 25 };

    var game_state = try create_game_state(extent, mine_count, test_seed);
    defer destroy_game_state(&game_state);

    uncover(&game_state, start_pos);

    try expect(game_state.event_history[0] == GameEventTag.discover_many);
}

test "Number uncover" {
    const extent = u32_2{ 5, 5 };
    const mine_count: u32 = 3;

    var game_state = try create_game_state(extent, mine_count, test_seed);
    defer destroy_game_state(&game_state);

    uncover(&game_state, .{ 0, 0 });
    toggle_flag(&game_state, .{ 0, 2 });
    uncover(&game_state, .{ 1, 1 });

    try expect(game_state.event_history[0] == GameEventTag.discover_many);
    try expect(game_state.event_history[1] == GameEventTag.discover_number);
    try expect(game_state.event_history[2] == GameEventTag.discover_single);
    try expect(game_state.event_history[3] == GameEventTag.discover_single);
    try expectEqual(game_state.is_ended, false);
}
