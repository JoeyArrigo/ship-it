# Poker App Project Summary
## Project Goal
Mobile poker app focused on short deck hold'em sit-n-go super-turbo tournaments (6 players). Prioritizing speed to MVP over UI polish.
## Key Requirements

- **Real-time multiplayer**: 6 players, ~100-200ms response time
- **Anti-cheat critical**: Server authoritative for all game logic, no client-side game decisions
- **Configurable tournaments**: Players, starting chips, blind structure as variables
- **Default format**: 6 players, 15 big blinds starting, super-turbo blinds
- **Multiple simultaneous games**: Architecture must support concurrent isolated tournaments

## Technology Decisions

- **Backend**: Elixir/Phoenix with WebSocket-based event-driven architecture
  - GenServer processes for game isolation
  - Phoenix Channels for WebSocket management
  - Natural fit for concurrent, fault-tolerant real-time systems

- **Frontend**: React Native/Expo (familiar stack)

## Development Phases

1. **Game Server Foundation**: Build core Elixir poker logic, test with simple clients
1. **Mobile Integration**: Add type generation tooling, build React Native app

## Future Features (Post-MVP)
- Crypto buy-ins/payouts
- Novel flexible player matching (stake range preferences vs fixed tables)
- Multiple tournament formats
- Player registration and matching system

## Architecture Pattern
WebSocket event-driven with server maintaining authoritative game state, broadcasting events to clients. Each tournament runs as isolated Elixir process.
