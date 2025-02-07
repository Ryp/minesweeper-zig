const GameState = @import("game.zig").GameState;

pub const DiscoverSingleEvent = struct {
    location: u32,
};

pub const DiscoverManyEvent = struct {
    location: u32,
    children: []u32,
};

pub const DiscoverNumberEvent = struct {
    location: u32,
    children: []u32,
};

pub const GameResult = enum {
    Win,
    Lose,
};

pub const GameEndEvent = struct {
    result: GameResult,
    exploded_mines: []u32,
};

pub const GameEvent = union(enum) {
    discover_single: DiscoverSingleEvent,
    discover_many: DiscoverManyEvent,
    discover_number: DiscoverNumberEvent,
    game_end: GameEndEvent,
};

pub fn allocate_new_event(game: *GameState) *GameEvent {
    const new_event = &game.event_history[game.event_history_index];
    game.event_history_index += 1;

    return new_event;
}
