const std = @import("std");
const assert = std.debug.assert;

usingnamespace @import("event.zig");

pub const u16_2 = std.meta.Vector(2, u16);
pub const i16_2 = std.meta.Vector(2, i16);
pub const u32_2 = std.meta.Vector(2, u32);

const MineSweeperBoardExtentMin = u32_2{ 5, 5 };
const MineSweeperBoardExtentMax = u32_2{ 1024, 1024 };
const UncoverAllMinesAfterLosing = true;
const EnableGuessFlag = true;

const neighborhood_offset_table = [9]i16_2{
    i16_2{ -1, -1 },
    i16_2{ -1, 0 },
    i16_2{ -1, 1 },
    i16_2{ 0, -1 },
    i16_2{ 0, 1 },
    i16_2{ 1, -1 },
    i16_2{ 1, -0 },
    i16_2{ 1, 1 },
    i16_2{ 0, 0 }, // Center position at the end so we can easily ignore it
};

pub const Marking = enum {
    None,
    Flag,
    Guess,
};

pub const CellState = struct {
    is_mine: bool = false,
    is_covered: bool = true,
    marking: Marking = Marking.None,
    mine_neighbors: u4 = 0,
};

pub const GameState = struct {
    extent: u32_2,
    mine_count: u32,
    board: [][]CellState,
    rng: std.rand.Xoroshiro128, // Hardcode PRNG type for forward compatibility
    is_first_move: bool = true,
    is_ended: bool = false,
    flag_count: u32 = 0,

    // Storage for game events
    event_history: []GameEvent,
    event_history_index: usize = 0,
    children_array: []u16_2,
    children_array_index: usize = 0,
};

pub fn cell_at(game: *GameState, position: u32_2) *CellState {
    return &game.board[position[0]][position[1]];
}

// I borrowed this name from HLSL
fn all(vector: anytype) bool {
    const type_info = @typeInfo(@TypeOf(vector));
    assert(type_info.Vector.child == bool);
    assert(type_info.Vector.len > 1);

    return @reduce(.And, vector);
}

fn any(vector: anytype) bool {
    const type_info = @typeInfo(@TypeOf(vector));
    assert(type_info.Vector.child == bool);
    assert(type_info.Vector.len > 1);

    return @reduce(.Or, vector);
}

// Creates blank board without mines.
// Placement of mines is done on the first player input.
pub fn create_game_state(allocator: *std.mem.Allocator, extent: u32_2, mine_count: u32, seed: u64) !GameState {
    assert(all(extent >= MineSweeperBoardExtentMin));
    assert(all(extent <= MineSweeperBoardExtentMax));

    const cell_count = extent[0] * extent[1];
    assert(mine_count > 0);
    assert(mine_count <= (cell_count - 9) / 2); // 9 is to take into account the starting position that has no mines in the neighborhood

    // Allocate board
    const board = try allocator.alloc([]CellState, extent[0]);
    errdefer allocator.free(board);

    for (board) |*column| {
        column.* = try allocator.alloc(CellState, extent[1]);
        errdefer allocator.free(column);

        for (column.*) |*cell| {
            cell.* = .{};
        }
    }

    // Allocate array to hold events
    const max_events = cell_count + 2000;

    const event_history = try allocator.alloc(GameEvent, max_events);
    errdefer allocator.free(event_history);

    // Allocate array to hold cells discovered in events
    const children_array = try allocator.alloc(u16_2, cell_count);
    errdefer allocator.free(children_array);

    return GameState{
        .extent = extent,
        .mine_count = mine_count,
        .rng = std.rand.Xoroshiro128.init(seed),
        .board = board,
        .event_history = event_history,
        .children_array = children_array,
    };
}

pub fn destroy_game_state(allocator: *std.mem.Allocator, game: *GameState) void {
    allocator.free(game.children_array);
    allocator.free(game.event_history);

    for (game.board) |column| {
        allocator.free(column);
    }

    allocator.free(game.board);
}

// Process an oncover events and propagates the state on the board.
pub fn uncover(game: *GameState, uncover_pos: u16_2) void {
    assert(all(uncover_pos < game.extent));

    if (game.is_first_move) {
        fill_mines(game, uncover_pos);
        game.is_first_move = false;
    }

    if (game.is_ended)
        return;

    var uncovered_cell = cell_at(game, uncover_pos);

    if (uncovered_cell.marking == Marking.Flag) {
        return; // Nothing happens!
    }

    if (!uncovered_cell.is_covered) {
        if (!uncovered_cell.is_mine and uncovered_cell.mine_neighbors > 0) {
            const start_children = game.children_array_index;

            uncover_from_number(game, uncover_pos, uncovered_cell);

            const end_children = game.children_array_index;

            append_discover_number_event(game, uncover_pos, game.children_array[start_children..end_children]);
        } else {
            return; // Nothing happens!
        }
    } else if (uncovered_cell.mine_neighbors == 0) {
        // Create new event
        const start_children = game.children_array_index;

        uncover_zero_neighbors(game, uncover_pos);

        const end_children = game.children_array_index;

        append_discover_many_event(game, uncover_pos, game.children_array[start_children..end_children]);
    } else {
        uncovered_cell.is_covered = false;
        append_discover_single_event(game, uncover_pos);
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
        for (game.board) |column, x| {
            for (column) |*cell, y| {
                // Oops!
                if (cell.is_mine and !cell.is_covered) {
                    game.is_ended = true;
                    game.children_array[game.children_array_index] = .{ @intCast(u16, x), @intCast(u16, y) };
                    game.children_array_index += 1;
                }

                if (cell.marking == Marking.Flag)
                    game.flag_count += 1;
            }
        }

        const end_children = game.children_array_index;

        if (game.is_ended) {
            assert(end_children > start_children);

            if (UncoverAllMinesAfterLosing) {
                for (game.board) |column| {
                    for (column) |*cell| {
                        if (cell.is_mine)
                            cell.is_covered = false;
                    }
                }
            }

            append_game_end_event(game, GameResult.Lose, game.children_array[start_children..end_children]);
        }
    }

    // Did we win?
    if (is_board_won(game.board)) {
        // Uncover the board and flag all mines
        for (game.board) |column| {
            for (column) |*cell| {
                if (cell.is_mine) {
                    // Here we should update the flag count but since we won there's no need
                    cell.marking = Marking.Flag;
                } else {
                    cell.is_covered = false;
                }
            }
        }

        game.is_ended = true;
        append_game_end_event(game, GameResult.Win, game.children_array[0..0]);
    }
}

fn is_neighbor(a: u32_2, b: u32_2) !bool {
    const dx = try std.math.absInt(@intCast(i32, a[0]) - @intCast(i32, b[0]));
    const dy = try std.math.absInt(@intCast(i32, a[1]) - @intCast(i32, b[1]));
    return dx <= 1 and dy <= 1;
}

// Feed a blank but initialized board and it will dart throw mines at it until it has the right
// number of mines.
// We make sure that no mines is placed in the startup location, including its immediate neighborhood.
// Often players restart the game until they land on this type of spots anyway, that removes the
// frustrating guessing part.
fn fill_mines(game: *GameState, start: u16_2) void {
    var remaining_mines = game.mine_count;

    // Randomly place the mines on the board
    while (remaining_mines > 0) {
        const random_pos = u32_2{ game.rng.random.uintLessThan(u32, game.extent[0]), game.rng.random.uintLessThan(u32, game.extent[1]) };

        // Do not generate mines where the player starts
        if (is_neighbor(random_pos, start) catch false)
            continue;

        var random_cell = cell_at(game, random_pos);

        if (random_cell.is_mine)
            continue;

        random_cell.is_mine = true;

        // Increment the counts for neighboring cells
        for (neighborhood_offset_table[0..9]) |offset| {
            const target = @intCast(i16_2, random_pos) + offset;

            // Out of bounds
            if (any(target < i16_2{ 0, 0 }) or any(target >= game.extent))
                continue;

            cell_at(game, @intCast(u16_2, target)).mine_neighbors += 1;
        }

        remaining_mines -= 1;
    }
}

// Discovers all cells adjacents to a zero-neighbor cell.
// Assumes that the play is valid.
// Careful, this function is recursive! It WILL smash the stack on large boards
fn uncover_zero_neighbors(game: *GameState, uncover_pos: u16_2) void {
    var cell = cell_at(game, uncover_pos);

    assert(cell.mine_neighbors == 0);

    // If the user put an invalid flag there by mistake, we clear it for him
    // That can only happens in recursive calls.
    cell.marking = Marking.None;
    cell.is_covered = false;

    game.children_array[game.children_array_index] = uncover_pos;
    game.children_array_index += 1;

    for (neighborhood_offset_table[0..8]) |offset| {
        const target = @intCast(i16_2, uncover_pos) + offset;

        // Out of bounds
        if (any(target < i16_2{ 0, 0 }) or any(target >= game.extent))
            continue;

        const utarget = @intCast(u16_2, target);

        var target_cell = cell_at(game, utarget);

        if (!target_cell.is_covered)
            continue;

        if (target_cell.mine_neighbors > 0) {
            target_cell.is_covered = false;

            game.children_array[game.children_array_index] = utarget;
            game.children_array_index += 1;
        } else {
            uncover_zero_neighbors(game, utarget);
        }
    }
}

// Discovers all adjacent cells around a numbered cell,
// if the number of flags around it equals that number.
// This can make you lose if your flags aren't set properly.
fn uncover_from_number(game: *GameState, number_pos: u16_2, number_cell: *CellState) void {
    assert(number_cell.mine_neighbors > 0);
    assert(!number_cell.is_covered);
    assert(!number_cell.is_mine);

    var candidates: [8]u16_2 = undefined;
    var candidate_count: u32 = 0;
    var flag_count: u32 = 0;

    for (neighborhood_offset_table[0..8]) |offset| {
        const target = @intCast(i16_2, number_pos) + offset;

        // Out of bounds
        if (any(target < i16_2{ 0, 0 }) or any(target >= game.extent))
            continue;

        const utarget = @intCast(u16_2, target);
        var target_cell = cell_at(game, utarget);

        assert(target_cell.is_covered or target_cell.marking == Marking.None);

        if (target_cell.marking == Marking.Flag) {
            flag_count += 1;
        } else if (target_cell.is_covered) {
            candidates[candidate_count] = utarget;
            candidate_count += 1;
        }
    }

    if (number_cell.mine_neighbors == flag_count) {
        var candidate_index: u32 = 0;
        while (candidate_index < candidate_count) {
            const candidate_pos = candidates[candidate_index];
            var cell = cell_at(game, candidate_pos);

            assert(cell.marking != Marking.Flag);

            // We might trigger second-hand big uncovers!
            if (cell.mine_neighbors == 0) {
                uncover_zero_neighbors(game, candidate_pos);
            } else {
                cell.is_covered = false;
            }

            game.children_array[game.children_array_index] = candidate_pos;
            game.children_array_index += 1;

            candidate_index += 1;
        }
    }
}

pub fn toggle_flag(game: *GameState, flag_pos: u16_2) void {
    assert(all(flag_pos < game.extent));

    if (game.is_first_move or game.is_ended)
        return;

    var cell = cell_at(game, flag_pos);

    if (!cell.is_covered)
        return;

    switch (cell.marking) {
        Marking.None => {
            cell.marking = Marking.Flag;
            game.flag_count += 1;
        },
        Marking.Flag => {
            if (EnableGuessFlag) {
                cell.marking = Marking.Guess;
            } else cell.marking = Marking.None;
            game.flag_count -= 1;
        },
        Marking.Guess => {
            cell.marking = Marking.None;
        },
    }
}

fn is_board_won(board: [][]CellState) bool {
    for (board) |column| {
        for (column) |cell| {
            if (cell.is_covered and !cell.is_mine)
                return false;
        }
    }

    return true;
}
