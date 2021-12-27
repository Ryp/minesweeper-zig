const GameState = @import("game.zig").GameState;
const @"u16_2" = @import("game.zig").u16_2;

pub const DiscoverSingleEvent = struct {
    location: u16_2,
};

pub const DiscoverManyEvent = struct {
    location: u16_2,
    children: []u16_2,
};

pub const DiscoverNumberEvent = struct {
    location: u16_2,
    children: []u16_2,
};

pub const GameResult = enum {
    Win,
    Lose,
};

pub const GameEndEvent = struct {
    result: GameResult,
    exploded_mines: []u16_2,
};

pub const GameEventTag = enum {
    discover_single,
    discover_many,
    discover_number,
    game_end,
};

pub const GameEvent = union(GameEventTag) {
    discover_single: DiscoverSingleEvent,
    discover_many: DiscoverManyEvent,
    discover_number: DiscoverNumberEvent,
    game_end: GameEndEvent,
};

fn allocate_new_event(game: *GameState) *GameEvent {
    const new_event = &game.event_history[game.event_history_index];
    game.event_history_index += 1;

    return new_event;
}

pub fn append_discover_single_event(game: *GameState, location: u16_2) void {
    var new_event = allocate_new_event(game);
    new_event.* = GameEvent{
        .discover_single = DiscoverSingleEvent{
            .location = location,
        },
    };
}

pub fn append_discover_many_event(game: *GameState, location: u16_2, children: []u16_2) void {
    var new_event = allocate_new_event(game);
    new_event.* = GameEvent{
        .discover_many = DiscoverManyEvent{
            .location = location,
            .children = children,
        },
    };
}

pub fn append_discover_number_event(game: *GameState, location: u16_2, children: []u16_2) void {
    var new_event = allocate_new_event(game);
    new_event.* = GameEvent{
        .discover_number = DiscoverNumberEvent{
            .location = location,
            .children = children,
        },
    };
}

pub fn append_game_end_event(game: *GameState, result: GameResult, exploded_mines: []u16_2) void {
    var new_event = allocate_new_event(game);
    new_event.* = GameEvent{
        .game_end = GameEndEvent{
            .result = result,
            .exploded_mines = exploded_mines,
        },
    };
}
