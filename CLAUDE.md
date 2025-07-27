# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a mobile poker app project focused on short deck hold'em sit-n-go super-turbo tournaments for 6 players. The project prioritizes speed to MVP over UI polish and is built as a real-time multiplayer game with strict anti-cheat requirements.

## Architecture

The application follows a **WebSocket event-driven architecture** with two main components:

### Backend - Elixir/Phoenix
- **Server-authoritative game logic**: All game decisions happen on the server for anti-cheat protection
- **GenServer processes**: Each tournament runs as an isolated Elixir process for concurrency and fault tolerance
- **Phoenix Channels**: Handle WebSocket connections and real-time communication
- **Event broadcasting**: Server maintains authoritative game state and broadcasts events to clients
- **Target latency**: 100-200ms response time for real-time gameplay

### Frontend - React Native/Expo
- Client receives and displays game state updates via WebSocket events
- No client-side game logic or decision making
- Built with familiar React Native/Expo stack

## Key Requirements

- **Real-time multiplayer**: Support for 6-player concurrent games
- **Multiple simultaneous tournaments**: Architecture must support concurrent isolated games
- **Configurable tournaments**: Players, starting chips, and blind structure as variables
- **Default format**: 6 players, 15 big blinds starting, super-turbo blinds
- **Anti-cheat critical**: Server authoritative for all game logic

## Development Phases

1. **Game Server Foundation**: Build core Elixir poker logic, test with simple clients
2. **Mobile Integration**: Add type generation tooling, build React Native app

## Current Implementation Status

### ✅ Completed Modules

**Deck Module (100% Complete - 13 tests passing)**
- `create/0` - Creates 36-card short deck 
- `shuffle/1` - Shuffles deck with robust probabilistic testing
- `deal_card/1` - Deals single card with empty deck error handling
- `deal_cards/2` - Deals multiple cards with validation
- `cards_remaining/1` - Returns deck size

**GameState Module (Partial - 5 tests passing)**
- `new/1` - Initializes game with 6 players, random button position, creates deck
- `tournament_complete?/1` - Checks if only one player remains

**HandEvaluator Module (Partial - 6 tests passing)**
- `hand_rankings/0` - Returns short deck ranking order (flush beats full house)
- `compare_hands/2` - Compares hands based on ranking hierarchy
- `determine_winners/1` - Handles empty list edge case

**Supporting Structures**
- `Card` struct with rank and suit
- `Player` struct with id, chips, position, hole_cards
- `BettingRound` struct (defined, not implemented)
- `GameState` struct (partially implemented)

### 🚧 Remaining Complex Modules

The following modules require substantial poker game logic implementation:
- **HandEvaluator.evaluate_hand/2** - Complex poker hand detection algorithms
- **BettingRound** module - Blind posting, action validation, pot management
- **GameState** advanced functions - Hand progression, card dealing, player elimination
- **Real-time multiplayer integration** - WebSocket event handling, Phoenix Channels

### Development Approach

Project follows **test-driven development (TDD)** methodology:
- Tests written first to define behavioral requirements
- Minimal implementations to pass tests
- 21+ tests currently passing
- Clean, tested building blocks ready for complex poker logic