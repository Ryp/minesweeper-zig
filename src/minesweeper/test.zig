const std = @import("std");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

const game = @import("game.zig");
const u32_2 = game.u32_2;
const event = @import("event.zig");

const test_seed: u64 = 0xC0FFEE42DEADBEEF;

test "Critical path" {
    const extent = u32_2{ 5, 5 };
    const mine_count: u32 = 8;
    const uncover_pos_0 = game.cell_coords_to_flat_index(extent, .{ 2, 2 });
    const uncover_pos_1 = game.cell_coords_to_flat_index(extent, .{ 0, 1 });

    const allocator: std.mem.Allocator = std.heap.page_allocator;

    var game_state = try game.create_game_state(allocator, extent, mine_count, test_seed);
    defer game.destroy_game_state(allocator, &game_state);

    game.uncover(&game_state, uncover_pos_0);

    try expectEqual(false, game_state.is_ended);
    try expectEqual(false, game_state.board[uncover_pos_0].is_covered);

    game.uncover(&game_state, uncover_pos_1);

    try expectEqual(true, game_state.is_ended);
    try expectEqual(false, game_state.board[uncover_pos_1].is_covered);
}

test "Toggle flag" {
    const extent = u32_2{ 5, 5 };
    const mine_count: u32 = 8;
    const uncover_pos_0 = game.cell_coords_to_flat_index(extent, .{ 2, 2 });
    const uncover_pos_1 = game.cell_coords_to_flat_index(extent, .{ 0, 1 });

    const allocator: std.mem.Allocator = std.heap.page_allocator;

    var game_state = try game.create_game_state(allocator, extent, mine_count, test_seed);
    defer game.destroy_game_state(allocator, &game_state);

    game.uncover(&game_state, uncover_pos_0);
    try expectEqual(false, game_state.board[uncover_pos_0].is_covered);

    game.toggle_flag(&game_state, uncover_pos_1);
    game.uncover(&game_state, uncover_pos_1);
    try expectEqual(true, game_state.board[uncover_pos_1].is_covered);

    game.toggle_flag(&game_state, uncover_pos_1);
    game.uncover(&game_state, uncover_pos_1);
    try expectEqual(false, game_state.board[uncover_pos_1].is_covered);
}

test "Big uncover" {
    const extent = u32_2{ 100, 100 };
    const mine_count: u32 = 1;
    const start_pos = game.cell_coords_to_flat_index(extent, .{ 25, 25 });

    const allocator: std.mem.Allocator = std.heap.page_allocator;

    var game_state = try game.create_game_state(allocator, extent, mine_count, test_seed);
    defer game.destroy_game_state(allocator, &game_state);

    game.uncover(&game_state, start_pos);

    try expect(game_state.event_history[0] == .discover_many);
}

test "Number uncover" {
    const extent = u32_2{ 5, 5 };
    const mine_count: u32 = 3;
    const uncover_pos_0 = game.cell_coords_to_flat_index(extent, .{ 2, 2 });
    const toggle_pos = game.cell_coords_to_flat_index(extent, .{ 0, 2 });
    const uncover_pos_1 = game.cell_coords_to_flat_index(extent, .{ 1, 2 });

    const allocator: std.mem.Allocator = std.heap.page_allocator;

    var game_state = try game.create_game_state(allocator, extent, mine_count, test_seed);
    defer game.destroy_game_state(allocator, &game_state);

    game.uncover(&game_state, uncover_pos_0);
    game.toggle_flag(&game_state, toggle_pos);
    game.uncover(&game_state, uncover_pos_1);

    const test_pos = game.cell_coords_to_flat_index(extent, .{ 0, 1 });

    try expectEqual(false, game_state.board[test_pos].is_covered);

    try expect(game_state.event_history[0] == .discover_many);
    try expect(game_state.event_history[1] == .discover_number);

    try expectEqual(false, game_state.is_ended);
}
