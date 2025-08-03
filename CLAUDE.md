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

**Test Status**: 208 tests passing (verified via `mix test`)
**Last Status Update**: Use `@test-suite-verifier` agent to get current test status

### ✅ Core Poker Engine (Substantially Complete)
- **Deck Module**: 36-card short deck with shuffle/deal functionality
- **GameState Module**: Game initialization, hand progression, player elimination
- **HandEvaluator Module**: Complete short deck hand evaluation and winner determination
- **BettingRound Module**: Comprehensive betting logic with blinds, raises, all-in handling
- **Tournament Module**: Multi-player tournament structure and progression
- **GameServer/GameManager**: Real-time multiplayer game coordination via GenServer
- **InputValidator**: Anti-cheat input validation and sanitization

### ✅ Real-Time Web Interface (Functional)
- **Phoenix LiveView**: Working game interface at `/game/:game_id`
- **UIAdapter**: Server-to-client state transformation for secure display
- **WebSocket Integration**: Real-time game updates via Phoenix Channels
- **Game Actions**: Player actions (fold/call/check/raise) fully implemented

### 🚧 Product Enhancement Opportunities
- **Mobile-first UI polish**: Current interface is functional but basic
- **Player onboarding and tutorials**: No guided experience for new players
- **Tournament lobby and matchmaking**: Basic lobby exists but needs UX improvements
- **Player progression and achievements**: No retention mechanics implemented
- **Monetization infrastructure**: No payment processing or tournament fees
- **Social features**: No chat, friends, or community elements

## Specialized Agent Usage Guidelines

### When to Consult @poker-product-expert
**Mandatory Consultation Scenarios:**
- Adding new game formats or tournament structures
- Implementing monetization features (buy-ins, rake, premium features)  
- Designing player progression systems or achievements
- Planning mobile app user experience and onboarding flows
- Making decisions about anti-cheat measures that affect gameplay
- Evaluating feature requests against real poker player needs
- Strategic decisions about target player segments (recreational vs serious)

**Consultation Triggers:**
- Any feature that affects game balance or player psychology
- UI/UX changes that impact speed of play or decision-making
- Business model or pricing strategy discussions
- Regulatory compliance questions for real-money poker
- Competitive analysis or market positioning decisions

### When to Consult @test-suite-verifier  
**Pre-Commit Requirements:**
- Before any commit that modifies core poker logic (GameState, BettingRound, HandEvaluator)
- When test count changes significantly (>10 tests added/removed)
- Before merging branches that affect game server stability

**Debugging Scenarios:**
- When tests are failing but the cause is unclear
- Performance issues with the test suite (>5 seconds runtime)
- Flaky tests that pass/fail inconsistently
- Integration test failures involving real-time multiplayer logic

## Development Approach

**Test-Driven Development (TDD)**:
- Comprehensive test coverage for all poker logic (208 tests currently passing)
- Anti-cheat validation through server-authoritative testing
- Real-time multiplayer concurrency testing
- Security-focused input validation testing

**Product-Led Engineering**:
- Consult @poker-product-expert before implementing player-facing features
- Prioritize features that improve player retention over flashy additions
- Balance recreational player accessibility with serious player depth
- Consider mobile-first interaction patterns for all UI development

## Poker-Specific Product Guidelines

### Target Player Segments
**Primary**: Recreational mobile players seeking quick, fun poker sessions
**Secondary**: Serious players looking for skill-based short deck tournaments
**Anti-Pattern**: Avoid features that only appeal to hardcore grinders or pros

### Core Product Principles
1. **Speed Over Complexity**: Super-turbo format prioritizes quick decisions and fast games
2. **Mobile-First Interaction**: Touch-friendly betting controls, portrait mode optimization
3. **Fair Play Integrity**: Server-authoritative logic prevents any client-side manipulation
4. **Skill-Based Progression**: Short deck format rewards post-flop skill over pre-flop tight play

### Feature Prioritization Framework
**Tier 1 (MVP Critical)**:
- Functional 6-player short deck tournaments
- Basic UI for betting actions and game state
- Secure real-time multiplayer without disconnection issues

**Tier 2 (Early Enhancement)**:
- Tournament lobby with join/spectate options
- Basic player statistics (hands played, tournaments won)
- Mobile app deployment with push notifications

**Tier 3 (Growth Features)**:
- Player progression system with achievements
- Social features (friends, chat during hands)
- Multiple tournament formats and buy-in levels

**Tier 4 (Monetization)**:
- Real-money tournament entry fees
- Subscription model for premium features
- Rake structure for cash games (if added later)

### Key Success Metrics
- **Player Retention**: 7-day return rate >40% (industry benchmark for poker apps)
- **Game Completion**: >90% of tournaments complete without player abandonment  
- **Speed of Play**: Average hand completion <30 seconds
- **Fair Play**: Zero successful cheating attempts in audit logs

## Maintaining Project Accuracy

### Status Updates
- **Test Count**: Run `mix test` to get current test status before making status claims
- **Module Completion**: Use `@test-suite-verifier` for definitive module completion status
- **Feature Status**: Update this file when major features are completed or deprecated

### Quick Reference Commands
```bash
# Get current test status
mix test

# Check server startup
iex -S mix phx.server

# Access game interface
http://localhost:4000/game/test-game?player=Player1

# Run specific test modules
mix test test/game_state_test.exs
mix test test/betting_round_test.exs
```

### Documentation Maintenance
- Update completion percentages based on actual test results
- Remove outdated "Remaining Complex Modules" when implemented
- Add new modules to appropriate completion sections
- Consult @poker-product-expert before claiming features are "complete" vs "functional"

## Development Decision Framework

**Before Any Major Change:**
1. Check current test status with `@test-suite-verifier`
2. Consult `@poker-product-expert` for player-facing features
3. Verify change aligns with product tier priorities above
4. Consider mobile-first implications for all UI changes
5. Ensure server-authoritative approach is maintained for game logic