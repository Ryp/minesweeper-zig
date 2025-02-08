const std = @import("std");
const assert = std.debug.assert;

const c = @cImport({
    @cInclude("SDL3/SDL.h");
});

const game = @import("minesweeper/game.zig");
const event = @import("minesweeper/event.zig");

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

fn get_sprite_sheet_rect(position: [2]u8) c.SDL_FRect {
    return c.SDL_FRect{
        .x = @floatFromInt(position[0] * SpriteSheetTileExtent),
        .y = @floatFromInt(position[1] * SpriteSheetTileExtent),
        .w = @floatFromInt(SpriteSheetTileExtent),
        .h = @floatFromInt(SpriteSheetTileExtent),
    };
}

pub fn execute_main_loop(allocator: std.mem.Allocator, game_state: *game.GameState) !void {
    const width = game_state.extent[0] * SpriteScreenExtent;
    const height = game_state.extent[1] * SpriteScreenExtent;

    if (!c.SDL_Init(c.SDL_INIT_VIDEO | c.SDL_INIT_EVENTS)) {
        c.SDL_Log("Unable to initialize SDL: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    }
    defer c.SDL_Quit();

    const window = c.SDL_CreateWindow("Minesweeper", @as(c_int, @intCast(width)), @as(c_int, @intCast(height)), 0) orelse {
        c.SDL_Log("Unable to create window: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    };
    defer c.SDL_DestroyWindow(window);

    if (!c.SDL_SetHint(c.SDL_HINT_RENDER_VSYNC, "1")) {
        c.SDL_Log("Unable to set hint: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    }

    const ren = c.SDL_CreateRenderer(window, null) orelse {
        c.SDL_Log("Unable to create renderer: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    };
    defer c.SDL_DestroyRenderer(ren);

    // Create sprite sheet texture
    const sprite_sheet_buffer = @embedFile("sprite_sheet");
    const sprite_sheet_io = c.SDL_IOFromConstMem(sprite_sheet_buffer, sprite_sheet_buffer.len);
    const sprite_sheet_surface = c.SDL_LoadBMP_IO(sprite_sheet_io, true) orelse {
        c.SDL_Log("Unable to create BMP surface from file: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    };
    defer c.SDL_DestroySurface(sprite_sheet_surface);

    const sprite_sheet_texture = c.SDL_CreateTextureFromSurface(ren, sprite_sheet_surface) orelse {
        c.SDL_Log("Unable to create texture from surface: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    };
    defer c.SDL_DestroyTexture(sprite_sheet_texture);

    // FIXME Match SDL2 behavior
    _ = c.SDL_SetTextureScaleMode(sprite_sheet_texture, c.SDL_SCALEMODE_NEAREST);

    var shouldExit = false;

    const gfx_board = try allocator.alloc(GfxState, game_state.extent[0] * game_state.extent[1]);
    errdefer allocator.free(gfx_board);

    for (gfx_board) |*cell| {
        cell.* = .{};
    }

    var gfx_event_index: usize = 0;
    var last_frame_time_ms: u64 = c.SDL_GetTicks();

    while (!shouldExit) {
        const current_frame_time_ms: u64 = c.SDL_GetTicks();
        const frame_delta_secs = @as(f32, @floatFromInt(current_frame_time_ms - last_frame_time_ms)) * 0.001;

        // Poll events
        var sdlEvent: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&sdlEvent)) {
            switch (sdlEvent.type) {
                c.SDL_EVENT_QUIT => {
                    shouldExit = true;
                },
                c.SDL_EVENT_KEY_DOWN => {
                    if (sdlEvent.key.key == c.SDLK_ESCAPE)
                        shouldExit = true;
                },
                c.SDL_EVENT_MOUSE_BUTTON_UP => {
                    const x = @divTrunc(@as(u32, @intFromFloat(sdlEvent.button.x)), SpriteScreenExtent);
                    const y = @divTrunc(@as(u32, @intFromFloat(sdlEvent.button.y)), SpriteScreenExtent);
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

        // Get current state of Control key
        const is_ctrl_pressed = c.SDL_GetModState() & c.SDL_KMOD_CTRL != 0;

        const string = try std.fmt.allocPrintZ(allocator, "Minesweeper {d}x{d} with {d}/{d} mines", .{ game_state.extent[0], game_state.extent[1], game_state.flag_count, game_state.mine_count });
        defer allocator.free(string);

        _ = c.SDL_SetWindowTitle(window, string.ptr);

        var mouse_x: f32 = undefined;
        var mouse_y: f32 = undefined;
        _ = c.SDL_GetMouseState(&mouse_x, &mouse_y);

        const hovered_cell_x = @max(0, @min(game_state.extent[0], @divTrunc(@as(u32, @intFromFloat(mouse_x)), SpriteScreenExtent)));
        const hovered_cell_y = @max(0, @min(game_state.extent[1], @divTrunc(@as(u32, @intFromFloat(mouse_y)), SpriteScreenExtent)));
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

            const sprite_output_pos_rect = c.SDL_FRect{
                .x = @floatFromInt(cell_coords[0] * SpriteScreenExtent),
                .y = @floatFromInt(cell_coords[1] * SpriteScreenExtent),
                .w = @floatFromInt(SpriteScreenExtent),
                .h = @floatFromInt(SpriteScreenExtent),
            };

            const is_cheating = is_ctrl_pressed;

            // Draw base cell sprite
            {
                var modified_cell = cell;
                modified_cell.is_covered = if (is_cheating) false else cell.is_covered;

                const sprite_sheet_pos = get_tile_index(modified_cell, gfx_cell, game_state.is_ended);
                const sprite_sheet_rect = get_sprite_sheet_rect(sprite_sheet_pos);

                _ = c.SDL_RenderTexture(ren, sprite_sheet_texture, &sprite_sheet_rect, &sprite_output_pos_rect);
            }

            if (is_cheating and cell.is_covered) {
                const sprite_sheet_rect = get_sprite_sheet_rect(.{ 0, 1 });

                _ = c.SDL_SetTextureAlphaMod(sprite_sheet_texture, @intFromFloat(128.0));
                _ = c.SDL_RenderTexture(ren, sprite_sheet_texture, &sprite_sheet_rect, &sprite_output_pos_rect);
                _ = c.SDL_SetTextureAlphaMod(sprite_sheet_texture, 255);
            }

            // Draw overlay on invalid move
            if (gfx_cell.invalid_move_time_secs > 0.0) {
                const alpha = gfx_cell.invalid_move_time_secs / InvalidMoveTimeSecs;
                const sprite_sheet_rect = get_sprite_sheet_rect(.{ 8, 1 });

                _ = c.SDL_SetTextureAlphaMod(sprite_sheet_texture, @intFromFloat(alpha * 255.0));
                _ = c.SDL_RenderTexture(ren, sprite_sheet_texture, &sprite_sheet_rect, &sprite_output_pos_rect);
                _ = c.SDL_SetTextureAlphaMod(sprite_sheet_texture, 255);
            }
        }

        _ = c.SDL_RenderPresent(ren);

        last_frame_time_ms = current_frame_time_ms;
    }

    allocator.free(gfx_board);
}
