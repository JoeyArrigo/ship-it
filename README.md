# Ship It Poker
## Project Status
Functional poker game server with web interface. Core game mechanics work, 282 tests passing. Ready for internal testing.
## Current Implementation

- **Real-time multiplayer**: Phoenix LiveView with PubSub for state synchronization
- **Server authoritative**: All game logic runs server-side, clients receive state updates
- **Tournament support**: Player elimination, button advancement, chip tracking
- **Short deck poker**: 36-card deck (6-A) with adjusted hand rankings
- **Complete betting system**: All phases implemented (preflop/flop/turn/river/showdown)
- **Side pot handling**: Multi-player all-in scenarios with proper pot distribution
- **Web interface**: Functional UI for 2-player games, mobile responsive

## Technology Decisions

- **Backend**: Elixir/Phoenix with WebSocket-based event-driven architecture
  - GenServer processes for game isolation
  - Phoenix Channels for WebSocket management
  - Natural fit for concurrent, fault-tolerant real-time systems

- **Frontend**: React Native/Expo (familiar stack)

## Development Status

1. **✅ Game Server Foundation**: Core poker logic implemented, tested
2. **🚧 Mobile Integration**: Web interface working, React Native planned

## Future Features (Post-MVP)
- Crypto buy-ins/payouts
- Novel flexible player matching (stake range preferences vs fixed tables)
- Multiple tournament formats
- Player registration and matching system

## Architecture Pattern
WebSocket event-driven with server maintaining authoritative game state, broadcasting events to clients. Each tournament runs as isolated Elixir process.
