usingnamespace @import("game.zig");

pub const DiscoverSingleEvent = struct {
    location: u16_2,
};

pub const DiscoverManyEvent = struct {
    location: u16_2,
    children: []u16_2,
};

pub const DiscoverNumberEvent = struct {
    location: u16_2,
    is_valid_move: bool,
};

pub const GameResult = enum {
    Win,
    Lose,
};

pub const GameEndEvent = struct {
    result: GameResult,
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

pub fn append_discover_number_event(game: *GameState, location: u16_2, is_valid_move: bool) void {
    var new_event = allocate_new_event(game);
    new_event.* = GameEvent{
        .discover_number = DiscoverNumberEvent{
            .location = location,
            .is_valid_move = is_valid_move,
        },
    };
}

pub fn append_game_end_event(game: *GameState, result: GameResult) void {
    var new_event = allocate_new_event(game);
    new_event.* = GameEvent{
        .game_end = GameEndEvent{
            .result = result,
        },
    };
}
