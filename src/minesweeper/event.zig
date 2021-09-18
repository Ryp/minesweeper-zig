usingnamespace @import("game.zig");

pub const DiscoverSingleEvent = struct {
    location: u16_2,
};

pub const DiscoverManyEvent = struct {
    location: u16_2,
    children: []u16_2,
};

pub const GameResult = enum {
    Win,
    Lose,
};

pub const GameEndEvent = struct {
    result: GameResult,
};

pub const GameEventType = enum {
    DiscoverSingle,
    DiscoverMany,
    GameEnd,
};

pub const GameEventUnion = union {
    discover_single: DiscoverSingleEvent,
    discover_many: DiscoverManyEvent,
    game_end: GameEndEvent,
};

pub const GameEvent = struct {
    type: GameEventType,
    event: GameEventUnion,
};

fn allocate_new_event(game: *GameState) *GameEvent {
    const new_event = &game.event_history[game.event_history_index];
    game.event_history_index += 1;

    return new_event;
}

pub fn append_discover_single_event(game: *GameState, location: u16_2) void {
    var new_event = allocate_new_event(game);
    new_event.type = GameEventType.DiscoverSingle;
    new_event.event = GameEventUnion{
        .discover_single = DiscoverSingleEvent{
            .location = location,
        },
    };
}

pub fn append_discover_many_event(game: *GameState, location: u16_2, children: []u16_2) void {
    var new_event = allocate_new_event(game);
    new_event.type = GameEventType.DiscoverMany;
    new_event.event = GameEventUnion{
        .discover_many = DiscoverManyEvent{
            .location = location,
            .children = children,
        },
    };
}

pub fn append_game_end_event(game: *GameState, result: GameResult) void {
    var new_event = allocate_new_event(game);
    new_event.type = GameEventType.GameEnd;
    new_event.event = GameEventUnion{
        .game_end = GameEndEvent{
            .result = result,
        },
    };
}
