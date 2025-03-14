const std = @import("std");
const assert = std.debug.assert;

const event = @import("event.zig");

pub const DefaultExtentX = 25;
pub const DefaultExtentY = 20;
pub const DefaultMineCount = 60;

const BoardExtentMin = u32_2{ 5, 5 };
const BoardExtentMax = u32_2{ 1024, 1024 };
const UncoverAllMinesAfterLosing = true;
const EnableGuessFlag = true;

const NeighborhoodOffsetTableWithCenter = [9]i32_2{
    .{ -1, -1 },
    .{ -1, 0 },
    .{ -1, 1 },
    .{ 0, -1 },
    .{ 0, 1 },
    .{ 1, -1 },
    .{ 1, 0 },
    .{ 1, 1 },
    .{ 0, 0 }, // Center position at the end so we can easily ignore it
};

const NeighborhoodOffsetTable = NeighborhoodOffsetTableWithCenter[0..8];

pub const GameState = struct {
    extent: u32_2,
    mine_count: u32,
    board: []CellState,
    rng: std.Random.Xoroshiro128, // Hardcode PRNG type for forward compatibility
    is_first_move: bool = true,
    is_ended: bool = false,
    flag_count: u32 = 0,

    // Storage for game events
    event_history: []event.GameEvent,
    event_history_index: usize = 0,
    children_array: []u32,
    children_array_index: usize = 0,
};

pub const u32_2 = @Vector(2, u32);
const i32_2 = @Vector(2, i32);

pub const Marking = enum {
    None,
    Flag,
    Guess,
};

pub const CellState = struct {
    is_mine: bool = false,
    is_covered: bool = true,
    marking: Marking = .None,
    mine_neighbors: u4 = 0,
};

pub fn cell_coords_to_flat_index(extent: u32_2, cell_coords: u32_2) u32 {
    return cell_coords[0] + extent[0] * cell_coords[1];
}

pub fn cell_flat_index_to_coords(extent: u32_2, flat_index: u32) u32_2 {
    return .{
        @intCast(flat_index % extent[0]),
        @intCast(flat_index / extent[0]),
    };
}

fn is_coords_valid(extent: u32_2, coords: i32_2) bool {
    return all(coords >= i32_2{ 0, 0 }) and all(@as(u32_2, @intCast(coords)) < extent);
}

// I borrowed this name from HLSL
fn all(vector: anytype) bool {
    const type_info = @typeInfo(@TypeOf(vector));
    assert(type_info.vector.child == bool);
    assert(type_info.vector.len > 1);

    return @reduce(.And, vector);
}

// Creates blank board without mines.
// Placement of mines is done on the first player input.
pub fn create_game_state(allocator: std.mem.Allocator, extent: u32_2, mine_count: u32, seed: u64) !GameState {
    assert(all(extent >= BoardExtentMin));
    assert(all(extent <= BoardExtentMax));

    const cell_count = extent[0] * extent[1];
    assert(mine_count > 0);
    assert(mine_count <= (cell_count - 9) / 2); // 9 is to take into account the starting position that has no mines in the neighborhood

    // Allocate board
    const board = try allocator.alloc(CellState, extent[0] * extent[1]);
    errdefer allocator.free(board);

    for (board) |*cell| {
        cell.* = .{};
    }

    // Allocate array to hold events
    const max_events = cell_count + 2000;

    const event_history = try allocator.alloc(event.GameEvent, max_events);
    errdefer allocator.free(event_history);

    // Allocate array to hold cells discovered in events
    const children_array = try allocator.alloc(u32, cell_count);
    errdefer allocator.free(children_array);

    return GameState{
        .extent = extent,
        .mine_count = mine_count,
        .rng = std.Random.Xoroshiro128.init(seed),
        .board = board,
        .event_history = event_history,
        .children_array = children_array,
    };
}

pub fn destroy_game_state(allocator: std.mem.Allocator, game: *GameState) void {
    allocator.free(game.children_array);
    allocator.free(game.event_history);
    allocator.free(game.board);
}

// Process an oncover events and propagates the state on the board.
pub fn uncover(game: *GameState, uncover_index: u32) void {
    assert(uncover_index < game.board.len);

    if (game.is_first_move) {
        fill_mines(game, uncover_index);
        game.is_first_move = false;
    }

    if (game.is_ended)
        return;

    const uncovered_cell = &game.board[uncover_index];

    if (uncovered_cell.marking == .Flag) {
        return; // Nothing happens!
    }

    if (!uncovered_cell.is_covered) {
        if (!uncovered_cell.is_mine and uncovered_cell.mine_neighbors > 0) {
            const start_children = game.children_array_index;

            uncover_from_number(game, uncover_index, uncovered_cell);

            const end_children = game.children_array_index;

            event.allocate_new_event(game).* = .{
                .discover_number = .{
                    .location = uncover_index,
                    .children = game.children_array[start_children..end_children],
                },
            };
        } else {
            return; // Nothing happens!
        }
    } else if (uncovered_cell.mine_neighbors == 0) {
        // Create new event
        const start_children = game.children_array_index;

        uncover_zero_neighbors(game, uncover_index);

        const end_children = game.children_array_index;

        event.allocate_new_event(game).* = .{
            .discover_many = .{
                .location = uncover_index,
                .children = game.children_array[start_children..end_children],
            },
        };
    } else {
        uncovered_cell.is_covered = false;
        event.allocate_new_event(game).* = .{
            .discover_single = .{
                .location = uncover_index,
            },
        };
    }

    check_win_conditions(game);
}

fn check_win_conditions(game: *GameState) void {
    assert(!game.is_ended);

    {
        // Did we lose?
        // It's possible to lose by doing a wrong number discover.
        // That means we potentially lose on another cell, or multiple
        // other cells - so we check the full board here.
        // Also we count the flags here since we're at it.
        const start_children = game.children_array_index;

        game.flag_count = 0;
        for (game.board, 0..) |*cell, flat_index| {
            // Oops!
            if (cell.is_mine and !cell.is_covered) {
                game.is_ended = true;
                game.children_array[game.children_array_index] = @intCast(flat_index);
                game.children_array_index += 1;
            }

            if (cell.marking == .Flag)
                game.flag_count += 1;
        }

        const end_children = game.children_array_index;

        if (game.is_ended) {
            assert(end_children > start_children);

            if (UncoverAllMinesAfterLosing) {
                for (game.board) |*cell| {
                    if (cell.is_mine)
                        cell.is_covered = false;
                }
            }

            event.allocate_new_event(game).* = .{
                .game_end = .{
                    .result = .Lose,
                    .exploded_mines = game.children_array[start_children..end_children],
                },
            };
        }
    }

    // Did we win?
    if (is_board_won(game.board)) {
        // Uncover the board and flag all mines
        for (game.board) |*cell| {
            if (cell.is_mine) {
                // Here we should update the flag count but since we won there's no need
                cell.marking = .Flag;
            } else {
                cell.is_covered = false;
            }
        }

        game.is_ended = true;

        event.allocate_new_event(game).* = .{
            .game_end = .{
                .result = .Win,
                .exploded_mines = game.children_array[0..0],
            },
        };
    }
}

fn is_neighbor(a: u32_2, b: u32_2) !bool {
    const dx = @abs(@as(i32, @intCast(a[0])) - @as(i32, @intCast(b[0])));
    const dy = @abs(@as(i32, @intCast(a[1])) - @as(i32, @intCast(b[1])));
    return dx <= 1 and dy <= 1;
}

// Feed a blank but initialized board and it will dart throw mines at it until it has the right
// number of mines.
// We make sure that no mines is placed in the startup location, including its immediate neighborhood.
// Often players restart the game until they land on this type of spots anyway, that removes the
// frustrating guessing part.
fn fill_mines(game: *GameState, start_index: u32) void {
    const start = cell_flat_index_to_coords(game.extent, start_index);

    var remaining_mines = game.mine_count;

    // Randomly place the mines on the board
    while (remaining_mines > 0) {
        const random_pos_index = game.rng.random().uintLessThan(u32, @intCast(game.board.len));
        const random_pos = cell_flat_index_to_coords(game.extent, random_pos_index);

        // Do not generate mines where the player starts
        if (is_neighbor(random_pos, start) catch false)
            continue;

        const random_cell = &game.board[random_pos_index];

        if (random_cell.is_mine)
            continue;

        random_cell.is_mine = true;

        for (NeighborhoodOffsetTableWithCenter) |neighbor_offset| {
            const neighbor_coords = @as(i32_2, @intCast(random_pos)) + neighbor_offset;

            if (is_coords_valid(game.extent, neighbor_coords)) {
                const index_flat = cell_coords_to_flat_index(game.extent, @intCast(neighbor_coords));

                game.board[index_flat].mine_neighbors += 1;
            }
        }

        remaining_mines -= 1;
    }
}

// Discovers all cells adjacents to a zero-neighbor cell.
// Assumes that the play is valid.
// Careful, this function is recursive! It WILL smash the stack on large boards
fn uncover_zero_neighbors(game: *GameState, uncover_cell_index: u32) void {
    const cell = &game.board[uncover_cell_index];

    assert(cell.mine_neighbors == 0);

    // If the user put an invalid flag there by mistake, we clear it for him
    // That can only happens in recursive calls.
    cell.marking = .None;
    cell.is_covered = false;

    game.children_array[game.children_array_index] = uncover_cell_index;
    game.children_array_index += 1;

    const uncover_coords: i32_2 = @intCast(cell_flat_index_to_coords(game.extent, uncover_cell_index));

    for (NeighborhoodOffsetTable) |neighbor_offset| {
        const neighbor_coords = uncover_coords + neighbor_offset;

        if (is_coords_valid(game.extent, neighbor_coords)) {
            const target_index = cell_coords_to_flat_index(game.extent, @intCast(neighbor_coords));
            const target_cell = &game.board[target_index];

            if (!target_cell.is_covered)
                continue;

            if (target_cell.mine_neighbors > 0) {
                target_cell.is_covered = false;

                game.children_array[game.children_array_index] = target_index;
                game.children_array_index += 1;
            } else {
                uncover_zero_neighbors(game, target_index);
            }
        }
    }
}

// Discovers all adjacent cells around a numbered cell,
// if the number of flags around it equals that number.
// This can make you lose if your flags aren't set properly.
fn uncover_from_number(game: *GameState, uncover_cell_index: u32, number_cell: *CellState) void {
    assert(number_cell.mine_neighbors > 0);
    assert(!number_cell.is_covered);
    assert(!number_cell.is_mine);

    var candidates: [8]u32 = undefined;
    var candidate_count: u32 = 0;
    var flag_count: u32 = 0;

    const uncover_coords: i32_2 = @intCast(cell_flat_index_to_coords(game.extent, uncover_cell_index));

    // Count covered cells
    for (NeighborhoodOffsetTable) |neighbor_offset| {
        const neighbor_coords = uncover_coords + neighbor_offset;

        if (is_coords_valid(game.extent, neighbor_coords)) {
            const target_index = cell_coords_to_flat_index(game.extent, @intCast(neighbor_coords));
            const target_cell = game.board[target_index];

            // Only count covered cells
            if (!target_cell.is_covered) {
                continue;
            }

            if (target_cell.marking == .Flag) {
                flag_count += 1;
            } else if (target_cell.is_covered) {
                candidates[candidate_count] = target_index;
                candidate_count += 1;
            }
        }
    }

    if (number_cell.mine_neighbors == flag_count) {
        for (candidates[0..candidate_count]) |candidate_index| {
            const cell = &game.board[candidate_index];

            assert(cell.marking != .Flag);

            // We might trigger second-hand big uncovers!
            if (cell.mine_neighbors == 0) {
                uncover_zero_neighbors(game, candidate_index);
            } else {
                cell.is_covered = false;
            }

            game.children_array[game.children_array_index] = candidate_index;
            game.children_array_index += 1;
        }
    }
}

pub fn toggle_flag(game: *GameState, cell_index: u32) void {
    assert(cell_index < game.board.len);

    if (game.is_first_move or game.is_ended)
        return;

    const cell = &game.board[cell_index];

    if (!cell.is_covered)
        return;

    switch (cell.marking) {
        .None => {
            cell.marking = .Flag;
            game.flag_count += 1;
        },
        .Flag => {
            if (EnableGuessFlag) {
                cell.marking = .Guess;
            } else cell.marking = .None;
            game.flag_count -= 1;
        },
        .Guess => {
            cell.marking = .None;
        },
    }
}

fn is_board_won(board: []CellState) bool {
    for (board) |cell| {
        if (cell.is_covered and !cell.is_mine)
            return false;
    }

    return true;
}
