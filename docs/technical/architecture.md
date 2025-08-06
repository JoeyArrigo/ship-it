# Server Architecture - Test-First Requirements

## Core Game Logic (Short Deck Hold'em)

### Deck Management
- Create short deck (36 cards: A, K, Q, J, 10, 9, 8, 7, 6 for each suit)
- Shuffle deck at game start
- Deal 2 hole cards to each player
- Deal community cards (3 flop, 1 turn, 1 river)
- Prevent dealing same card twice

### Hand Evaluation
- Rank hands according to short deck rules (flush beats full house)
- Compare hands to determine winner(s)
- Handle ties with side pots
- Calculate winning amounts

### Betting Rounds
- Enforce betting order (small blind, big blind, then clockwise)
- Validate player actions (fold, call, raise, all-in)
- Track pot size and side pots
- Enforce minimum bet sizes
- Handle all-in scenarios

### Game State Management
- Track player positions, chip counts, and cards
- Manage betting round progression (preflop, flop, turn, river)
- Determine when hand ends (all fold to one player, showdown)
- Reset for next hand

## Tournament Management

### Tournament Structure
- Initialize tournament with 6 players
- Set starting chip count (15 big blinds default)
- Configure blind structure (super-turbo progression)
- Track blind levels and increase timing

### Player Management
- Register 6 players for tournament
- Assign seating positions
- Track player elimination
- Handle disconnections/timeouts
- Determine tournament winner

### Blind Management
- Set initial small/big blind amounts
- Increase blinds on schedule
- Handle odd chip distributions
- Post blinds automatically

## Real-time Multiplayer

### Connection Management
- Accept player WebSocket connections
- Authenticate players
- Handle connection drops and reconnections
- Timeout inactive players

### Event Broadcasting
- Broadcast game state changes to all players
- Send private information (hole cards) to specific players
- Maintain event order and consistency
- Handle network delays gracefully

### Action Processing
- Receive player actions via WebSocket
- Validate actions against current game state
- Process actions in correct order
- Broadcast action results

## Anti-cheat & Server Authority

### Server Validation
- All game logic runs server-side
- Validate all player actions before processing
- Prevent impossible actions (betting out of turn, invalid amounts)
- Maintain authoritative game state

### Information Control
- Only reveal appropriate information to each player
- Hide opponent hole cards until showdown
- Prevent information leakage through timing
- Audit trail for all actions

## Concurrent Tournament Support

### Process Isolation
- Each tournament runs in separate GenServer process
- Tournaments don't interfere with each other
- Handle tournament process crashes gracefully
- Scale to multiple concurrent tournaments

### Resource Management
- Manage memory usage per tournament
- Clean up completed tournaments
- Monitor tournament health
- Load balancing across tournaments

## Error Handling & Edge Cases

### Network Issues
- Handle client disconnections during action
- Timeout players who don't act
- Reconnection with state sync
- Graceful degradation

### Game Edge Cases
- Handle ties and split pots
- All-in with side pots
- Player elimination mid-hand
- Invalid action attempts

### Tournament Edge Cases
- Player disconnection during tournament
- Tournament completion with ties
- Blind increases during active hand
- Final two players scenarios