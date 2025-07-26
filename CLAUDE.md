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

## Current State

This appears to be an early-stage project with only documentation files present. No code has been implemented yet.