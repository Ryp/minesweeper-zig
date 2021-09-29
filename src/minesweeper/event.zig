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

pub const GameEventTag = enum {
    discover_single,
    discover_many,
    game_end,
};

pub const GameEvent = union(GameEventTag) {
    discover_single: DiscoverSingleEvent,
    discover_many: DiscoverManyEvent,
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

pub fn append_game_end_event(game: *GameState, result: GameResult) void {
    var new_event = allocate_new_event(game);
    new_event.* = GameEvent{
        .game_end = GameEndEvent{
            .result = result,
        },
    };
}
