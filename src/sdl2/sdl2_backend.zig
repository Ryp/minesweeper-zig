const std = @import("std");
const assert = std.debug.assert;

const c = @cImport({
    @cInclude("SDL2/SDL.h");
});

const game = @import("../minesweeper/game.zig");
const event = @import("../minesweeper/event.zig");

const SpriteSheetTileExtent = 19;
const SpriteScreenExtent = 38;
const InvalidMoveTimeSecs: f32 = 0.6;

const GfxState = struct {
    invalid_move_time_secs: f32 = 0.0,
    is_hovered: bool = false,
    is_exploded: bool = false,
};

fn get_tile_index(cell: game.CellState, gfx_cell: GfxState, is_game_ended: bool) [2]u8 {
    if (cell.is_covered) {
        var index_x: u8 = 0;
        if (cell.marking == .Flag) {
            if (is_game_ended and !cell.is_mine) {
                index_x = 8;
            } else {
                index_x = 2;
            }
        } else if (cell.marking == .Guess) {
            index_x = 4;
        }

        if (gfx_cell.is_hovered and !is_game_ended)
            index_x += 1;
        return .{ index_x, 1 };
    } else {
        if (cell.is_mine) {
            if (gfx_cell.is_exploded) {
                return .{ 7, 1 };
            } else return .{ 6, 1 };
        }

        return .{ cell.mine_neighbors, 0 };
    }
}

fn get_sprite_sheet_rect(position: [2]u8) c.SDL_Rect {
    return c.SDL_Rect{
        .x = position[0] * SpriteSheetTileExtent,
        .y = position[1] * SpriteSheetTileExtent,
        .w = SpriteSheetTileExtent,
        .h = SpriteSheetTileExtent,
    };
}

pub fn execute_main_loop(allocator: std.mem.Allocator, game_state: *game.GameState) !void {
    const width = game_state.extent[0] * SpriteScreenExtent;
    const height = game_state.extent[1] * SpriteScreenExtent;

    if (c.SDL_Init(c.SDL_INIT_EVERYTHING) != 0) {
        c.SDL_Log("Unable to initialize SDL: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    }
    defer c.SDL_Quit();

    const window = c.SDL_CreateWindow("Minesweeper", c.SDL_WINDOWPOS_UNDEFINED, c.SDL_WINDOWPOS_UNDEFINED, @as(c_int, @intCast(width)), @as(c_int, @intCast(height)), c.SDL_WINDOW_SHOWN) orelse {
        c.SDL_Log("Unable to create window: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    };
    defer c.SDL_DestroyWindow(window);

    if (c.SDL_SetHint(c.SDL_HINT_RENDER_VSYNC, "1") == c.SDL_FALSE) {
        c.SDL_Log("Unable to set hint: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    }

    const ren = c.SDL_CreateRenderer(window, -1, c.SDL_RENDERER_ACCELERATED) orelse {
        c.SDL_Log("Unable to create renderer: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    };
    defer c.SDL_DestroyRenderer(ren);

    // Create sprite sheet
    // Using relative path for now
    const sprite_sheet_surface = c.SDL_LoadBMP("res/tile.bmp") orelse {
        c.SDL_Log("Unable to create BMP surface from file: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    };

    defer c.SDL_FreeSurface(sprite_sheet_surface);

    const sprite_sheet_texture = c.SDL_CreateTextureFromSurface(ren, sprite_sheet_surface) orelse {
        c.SDL_Log("Unable to create texture from surface: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    };
    defer c.SDL_DestroyTexture(sprite_sheet_texture);

    var shouldExit = false;

    const gfx_board = try allocator.alloc(GfxState, game_state.extent[0] * game_state.extent[1]);
    errdefer allocator.free(gfx_board);

    for (gfx_board) |*cell| {
        cell.* = .{};
    }

    var gfx_event_index: usize = 0;
    var last_frame_time_ms: u32 = c.SDL_GetTicks();

    while (!shouldExit) {
        const current_frame_time_ms: u32 = c.SDL_GetTicks();
        const frame_delta_secs = @as(f32, @floatFromInt(current_frame_time_ms - last_frame_time_ms)) * 0.001;

        // Poll events
        var sdlEvent: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&sdlEvent) > 0) {
            switch (sdlEvent.type) {
                c.SDL_QUIT => {
                    shouldExit = true;
                },
                c.SDL_KEYDOWN => {
                    if (sdlEvent.key.keysym.sym == c.SDLK_ESCAPE)
                        shouldExit = true;
                },
                c.SDL_MOUSEBUTTONUP => {
                    const x = @as(u32, @intCast(@divTrunc(sdlEvent.button.x, SpriteScreenExtent)));
                    const y = @as(u32, @intCast(@divTrunc(sdlEvent.button.y, SpriteScreenExtent)));
                    const mouse_cell_index = game.cell_coords_to_flat_index(game_state.extent, .{ x, y });

                    if (sdlEvent.button.button == c.SDL_BUTTON_LEFT) {
                        game.uncover(game_state, mouse_cell_index);
                    } else if (sdlEvent.button.button == c.SDL_BUTTON_RIGHT) {
                        game.toggle_flag(game_state, mouse_cell_index);
                    }
                },
                else => {},
            }
        }

        const string = try std.fmt.allocPrintZ(allocator, "Minesweeper {d}x{d} with {d}/{d} mines", .{ game_state.extent[0], game_state.extent[1], game_state.flag_count, game_state.mine_count });
        defer allocator.free(string);

        c.SDL_SetWindowTitle(window, string.ptr);

        var mouse_x: c_int = undefined;
        var mouse_y: c_int = undefined;
        _ = c.SDL_GetMouseState(&mouse_x, &mouse_y);

        const hovered_cell_x = @max(0, @min(game_state.extent[0], @as(u32, @intCast(@divTrunc(mouse_x, SpriteScreenExtent)))));
        const hovered_cell_y = @max(0, @min(game_state.extent[1], @as(u32, @intCast(@divTrunc(mouse_y, SpriteScreenExtent)))));
        const hovered_cell_index = game.cell_coords_to_flat_index(game_state.extent, .{ hovered_cell_x, hovered_cell_y });

        for (gfx_board) |*cell| {
            cell.is_hovered = false;
            cell.invalid_move_time_secs = @max(0.0, cell.invalid_move_time_secs - frame_delta_secs);
        }

        gfx_board[hovered_cell_index].is_hovered = true;

        // Process game events for the gfx side
        for (game_state.event_history[gfx_event_index..game_state.event_history_index]) |game_event| {
            switch (game_event) {
                .discover_number => |e| {
                    if (e.children.len == 0) {
                        gfx_board[e.location].invalid_move_time_secs = InvalidMoveTimeSecs;
                    }
                },
                .game_end => |e| {
                    for (e.exploded_mines) |mine_location| {
                        gfx_board[mine_location].is_exploded = true;
                    }
                },
                else => {},
            }
        }

        // Advance event index since we processed the rest
        gfx_event_index = game_state.event_history_index;

        _ = c.SDL_RenderClear(ren);

        for (game_state.board, 0..) |cell, flat_index| {
            const gfx_cell = gfx_board[flat_index];
            const cell_coords = game.cell_flat_index_to_coords(game_state.extent, @intCast(flat_index));

            const sprite_output_pos_rect = c.SDL_Rect{
                .x = @intCast(cell_coords[0] * SpriteScreenExtent),
                .y = @intCast(cell_coords[1] * SpriteScreenExtent),
                .w = SpriteScreenExtent,
                .h = SpriteScreenExtent,
            };

            // Draw base cell sprite
            {
                const sprite_sheet_pos = get_tile_index(cell, gfx_cell, game_state.is_ended);
                const sprite_sheet_rect = get_sprite_sheet_rect(sprite_sheet_pos);

                _ = c.SDL_RenderCopy(ren, sprite_sheet_texture, &sprite_sheet_rect, &sprite_output_pos_rect);
            }

            // Draw overlay on invalid move
            if (gfx_cell.invalid_move_time_secs > 0.0) {
                const alpha = gfx_cell.invalid_move_time_secs / InvalidMoveTimeSecs;
                const sprite_sheet_rect = get_sprite_sheet_rect(.{ 8, 1 });

                _ = c.SDL_SetTextureAlphaMod(sprite_sheet_texture, @intFromFloat(alpha * 255.0));
                _ = c.SDL_RenderCopy(ren, sprite_sheet_texture, &sprite_sheet_rect, &sprite_output_pos_rect);
                _ = c.SDL_SetTextureAlphaMod(sprite_sheet_texture, 255);
            }
        }

        c.SDL_RenderPresent(ren);

        last_frame_time_ms = current_frame_time_ms;
    }

    allocator.free(gfx_board);
}
