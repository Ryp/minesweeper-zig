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

    var board = try minesweeper.create_board(extent_x, extent_y);
    defer minesweeper.destroy_board(board);

    minesweeper.fill_mines(board, start_x, start_y, mine_count, &rng.random);

    var result = minesweeper.uncover(board, start_x, start_y);

    try expectEqual(result, minesweeper.UncoverResult.Continue);
    try expectEqual(board[start_x][start_y].is_covered, false);

    result = minesweeper.uncover(board, 0, 0);

    try expect(result != minesweeper.UncoverResult.Continue);
}
