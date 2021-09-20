const std = @import("std");
const assert = std.debug.assert;

const c = @cImport({
    @cInclude("SDL2/SDL.h");
});

const minesweeper = @import("../minesweeper/game.zig");

fn get_tile_index(cell: minesweeper.CellState, is_hovered: bool) [2]u8 {
    if (cell.is_covered) {
        var index_x: u8 = 0;
        if (cell.is_flagged)
            index_x = 2;
        // FIXME implement '?'
        if (is_hovered)
            index_x += 1;
        return .{ index_x, 1 };
    } else {
        if (cell.is_mine)
            return .{ 6, 1 };

        return .{ cell.mine_neighbors, 0 };
    }
}

pub fn execute_main_loop(game_state: *minesweeper.GameState) !void {
    const scale = 38;
    const width = game_state.extent_x * scale;
    const height = game_state.extent_y * scale;

    if (c.SDL_Init(c.SDL_INIT_EVERYTHING) != 0) {
        c.SDL_Log("Unable to initialize SDL: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    }
    defer c.SDL_Quit();

    const window = c.SDL_CreateWindow("Minesweeper", c.SDL_WINDOWPOS_UNDEFINED, c.SDL_WINDOWPOS_UNDEFINED, @intCast(c_int, width), @intCast(c_int, height), c.SDL_WINDOW_SHOWN) orelse {
        c.SDL_Log("Unable to create window: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    };
    defer c.SDL_DestroyWindow(window);

    if (c.SDL_SetHint(c.SDL_HINT_RENDER_VSYNC, "1") == c.SDL_bool.SDL_FALSE) {
        c.SDL_Log("Unable to set hint: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    }

    const ren = c.SDL_CreateRenderer(window, -1, c.SDL_RENDERER_ACCELERATED) orelse {
        c.SDL_Log("Unable to create renderer: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    };
    defer c.SDL_DestroyRenderer(ren);

    // Create sprite sheet
    // FIXME Using relative path for now
    const sprite_sheet_tile_extent = 19;
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

    while (!shouldExit) {
        // Poll events
        var sdlEvent: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&sdlEvent) > 0) {
            switch (@intToEnum(c.SDL_EventType, @intCast(c_int, sdlEvent.type))) {
                .SDL_QUIT => {
                    shouldExit = true;
                },
                .SDL_KEYDOWN => {
                    if (sdlEvent.key.keysym.sym == c.SDLK_ESCAPE)
                        shouldExit = true;
                },
                .SDL_MOUSEBUTTONUP => {
                    const x = @intCast(u16, @divTrunc(sdlEvent.button.x, scale));
                    const y = @intCast(u16, @divTrunc(sdlEvent.button.y, scale));
                    if (sdlEvent.button.button == c.SDL_BUTTON_LEFT) {
                        minesweeper.uncover(game_state, .{ .x = x, .y = y });
                    } else if (sdlEvent.button.button == c.SDL_BUTTON_RIGHT) {
                        minesweeper.toggle_flag(game_state, x, y);
                    }
                },
                else => {},
            }
        }

        var mouse_x: c_int = undefined;
        var mouse_y: c_int = undefined;
        const mouse_button_state = c.SDL_GetMouseState(&mouse_x, &mouse_y);
        const hover_x = @intCast(u16, @divTrunc(mouse_x, scale));
        const hover_y = @intCast(u16, @divTrunc(mouse_y, scale));

        // Render game
        _ = c.SDL_RenderClear(ren);

        for (game_state.board) |column, i| {
            for (column) |cell, j| {
                const is_hovered = (i == hover_x) and (j == hover_y);

                const sprite_sheet_pos = get_tile_index(cell, is_hovered);

                const sprite_sheet_rect = c.SDL_Rect{
                    .x = sprite_sheet_pos[0] * sprite_sheet_tile_extent,
                    .y = sprite_sheet_pos[1] * sprite_sheet_tile_extent,
                    .w = sprite_sheet_tile_extent,
                    .h = sprite_sheet_tile_extent,
                };

                const sprite_pos_rect = c.SDL_Rect{
                    .x = @intCast(c_int, i * scale),
                    .y = @intCast(c_int, j * scale),
                    .w = scale,
                    .h = scale,
                };

                _ = c.SDL_RenderCopy(ren, sprite_sheet_texture, &sprite_sheet_rect, &sprite_pos_rect);
            }
        }

        // Present
        c.SDL_RenderPresent(ren);
    }
}
