const std = @import("std");
const assert = std.debug.assert;

const MineSweeperBoardExtentMinX: u16 = 2;
const MineSweeperBoardExtentMinY: u16 = 2;
const MineSweeperBoardExtentMaxX: u16 = 1024;
const MineSweeperBoardExtentMaxY: u16 = 1024;

pub const CellState = struct {
    is_mine: bool,
    is_covered: bool,
    is_flagged: bool,
    mine_neighbors: u4,
};

pub const UncoverResult = enum { Continue, Win, Lose };

pub const GameState = struct {
    extent_x: u16,
    extent_y: u16,
    mine_count: u16,
    board: [][]CellState,
    last_move_result: UncoverResult,
    rng: *std.rand.Random,
    is_first_move: bool,
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
    game.last_move_result = UncoverResult.Continue;

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

    // Placement of mines is done on the first player input
    return game;
}

pub fn destroy_game_state(game: *GameState) void {
    const allocator: *std.mem.Allocator = std.heap.page_allocator;

    for (game.board) |column| {
        allocator.free(column);
    }

    allocator.free(game.board);
}

pub fn debug_print(game: *GameState) !void {
    const stdout = std.io.getStdOut().writer();

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

const i8_2 = struct {
    x: i8,
    y: i8,
};

// Feed a blank but initialized board and it will dart throw mines at it until it has the right
// number of mines.
pub fn fill_mines(game: *GameState, start_x: u16, start_y: u16) void {
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
        if (random_x == start_x and random_y == start_y)
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

pub fn is_board_won(board: [][]CellState) bool {
    for (board) |column| {
        for (column) |cell| {
            if (cell.is_covered and !cell.is_mine)
                return false;
        }
    }

    return true;
}

// Assumes the position to uncover is covered and has no neighbors
pub fn uncover_zero_neighbors(board: [][]CellState, uncover_x: u16, uncover_y: u16) void {
    const extent_x = @intCast(u16, board.len);
    const extent_y = @intCast(u16, board[0].len);

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

    var cell = &board[uncover_x][uncover_y];

    assert(cell.mine_neighbors == 0);

    cell.is_covered = false;

    for (offset_table) |offset| {
        const target_x = @intCast(i16, uncover_x) + offset.x;
        const target_y = @intCast(i16, uncover_y) + offset.y;

        // Out of bounds
        if (target_x < 0 or target_y < 0)
            continue;
        if (target_x >= extent_x or target_y >= extent_y)
            continue;

        const utarget_x = @intCast(u16, target_x);
        const utarget_y = @intCast(u16, target_y);

        var target_cell = &board[utarget_x][utarget_y];

        if (target_cell.mine_neighbors == 0 and target_cell.is_covered)
            uncover_zero_neighbors(board, utarget_x, utarget_y);

        target_cell.is_covered = false;
    }
}

// Process an oncover events and propagates the state on the board.
pub fn uncover(game: *GameState, uncover_x: u16, uncover_y: u16) void {
    assert(uncover_x < game.extent_x);
    assert(uncover_y < game.extent_y);

    if (game.is_first_move) {
        fill_mines(game, uncover_x, uncover_y);
        game.is_first_move = false;
    }

    // Game has ended?
    if (game.last_move_result != UncoverResult.Continue)
        return;

    var uncovered_cell = &game.board[uncover_x][uncover_y];

    if (!uncovered_cell.is_covered or uncovered_cell.is_flagged) {
        return; // Nothing to do!
    }

    // Uncover cell
    uncovered_cell.is_covered = false;

    if (uncovered_cell.mine_neighbors == 0) {
        uncover_zero_neighbors(game.board, uncover_x, uncover_y);
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

        game.last_move_result = UncoverResult.Lose;
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

        game.last_move_result = UncoverResult.Win;
        return;
    }

    game.last_move_result = UncoverResult.Continue;
}

pub fn toggle_flag(game: *GameState, x: u16, y: u16) void {
    assert(x < game.extent_x);
    assert(y < game.extent_y);

    if (game.last_move_result != UncoverResult.Continue)
        return;

    var cell = &game.board[x][y];

    if (!cell.is_covered)
        return;

    cell.is_flagged = !cell.is_flagged;
}
