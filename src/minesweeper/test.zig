const std = @import("std");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

const game = @import("game.zig");
const @"u32_2" = game.u32_2;
const @"u16_2" = game.u16_2;
const event = @import("event.zig");

const test_seed: u64 = 0xC0FFEE42DEADBEEF;

test "Critical path" {
    const extent = u32_2{ 5, 5 };
    const mine_count: u32 = 2;
    const uncover_pos_0 = u16_2{ 2, 2 };
    const uncover_pos_1 = u16_2{ 0, 1 };

    const allocator: std.mem.Allocator = std.heap.page_allocator;

    var game_state = try game.create_game_state(allocator, extent, mine_count, test_seed);
    defer game.destroy_game_state(allocator, &game_state);

    game.uncover(&game_state, uncover_pos_0);

    try expectEqual(game_state.is_ended, false);
    try expectEqual(game.cell_at(&game_state, uncover_pos_0).is_covered, false);

    game.uncover(&game_state, uncover_pos_1);

    try expectEqual(game_state.is_ended, true);
    try expectEqual(game.cell_at(&game_state, uncover_pos_1).is_covered, false);
}

test "Toggle flag" {
    const extent = u32_2{ 5, 5 };
    const mine_count: u32 = 2;
    const uncover_pos_0 = u16_2{ 2, 2 };
    const uncover_pos_1 = u16_2{ 0, 1 };

    const allocator: std.mem.Allocator = std.heap.page_allocator;

    var game_state = try game.create_game_state(allocator, extent, mine_count, test_seed);
    defer game.destroy_game_state(allocator, &game_state);

    game.uncover(&game_state, uncover_pos_0);
    try expectEqual(game.cell_at(&game_state, uncover_pos_0).is_covered, false);

    game.toggle_flag(&game_state, uncover_pos_1);
    game.uncover(&game_state, uncover_pos_1);
    try expectEqual(game.cell_at(&game_state, uncover_pos_1).is_covered, true);

    game.toggle_flag(&game_state, uncover_pos_1);
    game.uncover(&game_state, uncover_pos_1);
    try expectEqual(game.cell_at(&game_state, uncover_pos_1).is_covered, false);
}

test "Big uncover" {
    const extent = u32_2{ 100, 100 };
    const mine_count: u32 = 1;
    const start_pos = u16_2{ 25, 25 };

    const allocator: std.mem.Allocator = std.heap.page_allocator;

    var game_state = try game.create_game_state(allocator, extent, mine_count, test_seed);
    defer game.destroy_game_state(allocator, &game_state);

    game.uncover(&game_state, start_pos);

    try expect(game_state.event_history[0] == event.GameEventTag.discover_many);
}

test "Number uncover" {
    const extent = u32_2{ 5, 5 };
    const mine_count: u32 = 3;

    const allocator: std.mem.Allocator = std.heap.page_allocator;

    var game_state = try game.create_game_state(allocator, extent, mine_count, test_seed);
    defer game.destroy_game_state(allocator, &game_state);

    game.uncover(&game_state, .{ 0, 0 });
    game.toggle_flag(&game_state, .{ 0, 2 });
    game.uncover(&game_state, .{ 1, 1 });

    try expectEqual(game.cell_at(&game_state, .{ 2, 1 }).is_covered, false);
    try expectEqual(game.cell_at(&game_state, .{ 3, 1 }).is_covered, false);
    try expect(game_state.event_history[0] == event.GameEventTag.discover_many);
    try expect(game_state.event_history[1] == event.GameEventTag.discover_number);
    try expectEqual(game_state.is_ended, false);
}
