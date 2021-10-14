const std = @import("std");
const assert = std.debug.assert;

usingnamespace @import("event.zig");

const MineSweeperBoardExtentMinX: u16 = 2;
const MineSweeperBoardExtentMinY: u16 = 2;
const MineSweeperBoardExtentMaxX: u16 = 1024;
const MineSweeperBoardExtentMaxY: u16 = 1024;

const i8_2 = struct {
    x: i8,
    y: i8,
};

pub const u16_2 = struct {
    x: u16,
    y: u16,
};

pub const CellState = struct {
    is_mine: bool,
    is_covered: bool,
    is_flagged: bool,
    mine_neighbors: u4,
};

pub const GameState = struct {
    extent_x: u16,
    extent_y: u16,
    mine_count: u16,
    board: [][]CellState,
    rng: *std.rand.Random,
    is_first_move: bool,
    is_ended: bool,

    // Storage for game events
    event_history: []GameEvent,
    event_history_index: usize,
    children_array: []u16_2,
    children_array_index: usize,
};

// Creates blank board without mines
pub fn create_game_state(extent_x: u16, extent_y: u16, mine_count: u16, rng: *std.rand.Random) !GameState {
    assert(extent_x >= MineSweeperBoardExtentMinX and extent_y >= MineSweeperBoardExtentMinY);
    assert(extent_x <= MineSweeperBoardExtentMaxX and extent_y <= MineSweeperBoardExtentMaxY);

    const cell_count = extent_x * extent_y;
    assert(mine_count > 0);
    assert(mine_count <= cell_count / 2);

    var game: GameState = undefined;
    game.extent_x = extent_x;
    game.extent_y = extent_y;
    game.mine_count = mine_count;
    game.rng = rng;
    game.is_first_move = true;
    game.is_ended = false;
    game.children_array_index = 0;
    game.event_history_index = 0;

    const allocator: *std.mem.Allocator = std.heap.page_allocator;

    game.board = try allocator.alloc([]CellState, extent_x);
    errdefer allocator.free(game.board);

    for (game.board) |*column| {
        column.* = try allocator.alloc(CellState, extent_y);
        errdefer allocator.free(column);

        for (column.*) |*cell| {
            cell.* = CellState{
                .is_mine = false,
                .is_covered = true,
                .is_flagged = false,
                .mine_neighbors = 0,
            };
        }
    }

    // Allocate array to hold events
    const max_events = extent_x * extent_y + 2000;

    game.event_history = try allocator.alloc(GameEvent, max_events);
    errdefer allocator.free(game.event_history);

    // Allocate array to hold children discovered in events
    game.children_array = try allocator.alloc(u16_2, extent_x * extent_y);
    errdefer allocator.free(game.children_array);

    // Placement of mines is done on the first player input
    return game;
}

pub fn destroy_game_state(game: *GameState) void {
    const allocator: *std.mem.Allocator = std.heap.page_allocator;

    allocator.free(game.children_array);
    allocator.free(game.event_history);

    for (game.board) |column| {
        allocator.free(column);
    }

    allocator.free(game.board);
}

// Process an oncover events and propagates the state on the board.
pub fn uncover(game: *GameState, uncover_pos: u16_2) void {
    assert(uncover_pos.x < game.extent_x);
    assert(uncover_pos.y < game.extent_y);

    if (game.is_first_move) {
        fill_mines(game, uncover_pos);
        game.is_first_move = false;
    }

    if (game.is_ended)
        return;

    var uncovered_cell = &game.board[uncover_pos.x][uncover_pos.y];

    if (uncovered_cell.is_flagged) {
        return; // Nothing to do!
    }

    if (!uncovered_cell.is_covered) {
        if (uncovered_cell.mine_neighbors > 0 and !uncovered_cell.is_mine) {
            uncover_from_number(game, uncover_pos, uncovered_cell);
        }

        return;
    }

    // Uncover cell
    if (uncovered_cell.mine_neighbors == 0) {
        // Create new event
        const start_children = game.children_array_index;

        uncover_zero_neighbors(game, uncover_pos);

        const end_children = game.children_array_index;

        append_discover_many_event(game, uncover_pos, game.children_array[start_children..end_children]);
    } else {
        uncovered_cell.is_covered = false;
        append_discover_single_event(game, uncover_pos);
    }

    // Did we lose?
    if (uncovered_cell.is_mine) {
        // Uncover all mines
        for (game.board) |column| {
            for (column) |*cell| {
                if (cell.is_mine)
                    cell.is_covered = false;
            }
        }

        game.is_ended = true;
        append_game_end_event(game, GameResult.Lose);
        return;
    }

    // Did we win?
    if (is_board_won(game.board)) {
        // Uncover the board and flag all mines
        for (game.board) |column| {
            for (column) |*cell| {
                if (cell.is_mine) {
                    cell.is_flagged = true;
                } else {
                    cell.is_covered = false;
                }
            }
        }

        game.is_ended = true;
        append_game_end_event(game, GameResult.Win);
        return;
    }
}

// Feed a blank but initialized board and it will dart throw mines at it until it has the right
// number of mines.
pub fn fill_mines(game: *GameState, start: u16_2) void {
    var neighbour_offset_table = [9]i8_2{
        i8_2{ .x = -1, .y = -1 },
        i8_2{ .x = -1, .y = 0 },
        i8_2{ .x = -1, .y = 1 },
        i8_2{ .x = 0, .y = -1 },
        i8_2{ .x = 0, .y = 0 },
        i8_2{ .x = 0, .y = 1 },
        i8_2{ .x = 1, .y = -1 },
        i8_2{ .x = 1, .y = -0 },
        i8_2{ .x = 1, .y = 1 },
    };

    var remaining_mines = game.mine_count;

    // Randomly place the mines on the board
    while (remaining_mines > 0) {
        const random_x = game.rng.uintLessThan(u16, game.extent_x);
        const random_y = game.rng.uintLessThan(u16, game.extent_y);

        // Do not generate mines where the player starts
        if (random_x == start.x and random_y == start.y)
            continue;

        var random_cell = &game.board[random_x][random_y];

        if (random_cell.is_mine)
            continue;

        random_cell.is_mine = true;

        // Increment the counts for neighboring cells
        for (neighbour_offset_table) |offset| {
            const target_x = @intCast(i16, random_x) + offset.x;
            const target_y = @intCast(i16, random_y) + offset.y;

            // Out of bounds
            if (target_x < 0 or target_y < 0)
                continue;
            if (target_x >= game.extent_x or target_y >= game.extent_y)
                continue;

            game.board[@intCast(u16, target_x)][@intCast(u16, target_y)].mine_neighbors += 1;
        }

        remaining_mines -= 1;
    }
}

// Discovers all cells adjacents to a zero-neighbor cell
// Careful, this function is recursive.
pub fn uncover_zero_neighbors(game: *GameState, uncover_pos: u16_2) void {
    var offset_table = [8]i8_2{
        i8_2{ .x = -1, .y = -1 },
        i8_2{ .x = -1, .y = 0 },
        i8_2{ .x = -1, .y = 1 },
        i8_2{ .x = 0, .y = -1 },
        i8_2{ .x = 0, .y = 1 },
        i8_2{ .x = 1, .y = -1 },
        i8_2{ .x = 1, .y = -0 },
        i8_2{ .x = 1, .y = 1 },
    };

    var cell = &game.board[uncover_pos.x][uncover_pos.y];

    assert(cell.mine_neighbors == 0);

    cell.is_covered = false;

    game.children_array[game.children_array_index] = uncover_pos;
    game.children_array_index += 1;

    for (offset_table) |offset| {
        const target_x = @intCast(i16, uncover_pos.x) + offset.x;
        const target_y = @intCast(i16, uncover_pos.y) + offset.y;

        // Out of bounds
        if (target_x < 0 or target_y < 0)
            continue;
        if (target_x >= game.extent_x or target_y >= game.extent_y)
            continue;

        const utarget = u16_2{
            .x = @intCast(u16, target_x),
            .y = @intCast(u16, target_y),
        };

        var target_cell = &game.board[utarget.x][utarget.y];

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
pub fn uncover_from_number(game: *GameState, number_pos: u16_2, number_cell: *CellState) void {
    assert(number_cell.mine_neighbors > 0);
    assert(!number_cell.is_covered);
    assert(!number_cell.is_mine);

    var offset_table = [8]i8_2{
        i8_2{ .x = -1, .y = -1 },
        i8_2{ .x = -1, .y = 0 },
        i8_2{ .x = -1, .y = 1 },
        i8_2{ .x = 0, .y = -1 },
        i8_2{ .x = 0, .y = 1 },
        i8_2{ .x = 1, .y = -1 },
        i8_2{ .x = 1, .y = -0 },
        i8_2{ .x = 1, .y = 1 },
    };

    var candidates: [8]u16_2 = undefined;
    var candidate_count: u32 = 0;
    var flag_count: u32 = 0;

    for (offset_table) |offset| {
        const target_x = @intCast(i16, number_pos.x) + offset.x;
        const target_y = @intCast(i16, number_pos.y) + offset.y;

        // Out of bounds
        if (target_x < 0 or target_y < 0)
            continue;
        if (target_x >= game.extent_x or target_y >= game.extent_y)
            continue;

        const utarget = u16_2{
            .x = @intCast(u16, target_x),
            .y = @intCast(u16, target_y),
        };

        var target_cell = &game.board[utarget.x][utarget.y];

        assert(!(!target_cell.is_covered and target_cell.is_flagged));

        if (target_cell.is_flagged) {
            flag_count += 1;
        } else if (target_cell.is_covered) {
            candidates[candidate_count] = utarget;
            candidate_count += 1;
        }
    }

    if (number_cell.mine_neighbors == flag_count) {
        append_discover_number_event(game, number_pos, true);

        var candidate_index: u32 = 0;
        while (candidate_index < candidate_count) {
            uncover(game, candidates[candidate_index]);
            candidate_index += 1;
        }
    } else {
        append_discover_number_event(game, number_pos, false);
    }
}

pub fn toggle_flag(game: *GameState, flag_pos: u16_2) void {
    assert(flag_pos.x < game.extent_x);
    assert(flag_pos.y < game.extent_y);

    if (game.is_first_move or game.is_ended)
        return;

    var cell = &game.board[flag_pos.x][flag_pos.y];

    if (!cell.is_covered)
        return;

    cell.is_flagged = !cell.is_flagged;
}

pub fn is_board_won(board: [][]CellState) bool {
    for (board) |column| {
        for (column) |cell| {
            if (cell.is_covered and !cell.is_mine)
                return false;
        }
    }

    return true;
}

pub fn debug_print(game: *GameState) !void {
    var y: u16 = 0;
    while (y < game.extent_y) {
        var x: u16 = 0;
        while (x < game.extent_x) {
            const cell = game.board[x][y];

            if (cell.is_covered) {
                if (cell.is_flagged) {
                    std.debug.print("F", .{});
                } else {
                    std.debug.print("-", .{});
                }
            } else if (cell.mine_neighbors > 0) {
                const c: u8 = '0' + @intCast(u8, cell.mine_neighbors);
                const str = [_]u8{ c, 0 };
                std.debug.print("{s}", .{&str});
            } else if (cell.is_mine) {
                std.debug.print("x", .{});
            } else std.debug.print(" ", .{});

            std.debug.print(" ", .{});
            x += 1;
        }

        std.debug.print("\n", .{});
        y += 1;
    }
}
