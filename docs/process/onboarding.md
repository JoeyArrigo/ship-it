# Developer Onboarding Guide

**Goal**: Get productive on the poker app in 3 hours

## Hour 1: Project Understanding (60 minutes)

### Architecture Overview (20 minutes)
Read these files in order:
1. `/docs/product/requirements.md` - Player segments and product goals
2. `/docs/technical/architecture.md` - System design and server behaviors  
3. `/CLAUDE.md` - Project instructions and current status

**Key Concepts**:
- **Server-authoritative**: All game logic runs server-side for anti-cheat
- **Real-time multiplayer**: WebSocket-based with Phoenix Channels
- **Short deck poker**: 36-card deck, flush beats full house
- **Mobile-first**: Targeting recreational mobile players primarily

### Codebase Structure (20 minutes)
```
lib/poker_server/           # Core game logic (business domain)
├── game_state.ex          # Hand progression, player elimination  
├── betting_round.ex       # Betting validation and pot calculation
├── hand_evaluator.ex      # Poker hand ranking (short deck rules)
├── game_server.ex         # Real-time multiplayer coordinator
└── tournament.ex          # Tournament structure and progression

lib/poker_server_web/      # Web interface (Phoenix LiveView)
├── live/game_live/        # Real-time game interface
├── router.ex              # URL routing
└── endpoint.ex            # WebSocket connections

test/                      # Comprehensive test suite (208+ tests)
├── concurrency/           # Multiplayer stress tests
└── security/              # Anti-cheat validation tests
```

### Test-Driven Development (20 minutes)
Run the test suite to understand current functionality:
```bash
mix test                   # Run all 208+ tests (should pass)
mix test test/game_state_test.exs  # Core poker logic tests
mix test test/concurrency/ # Real-time multiplayer tests
```

**Current Test Status**: All tests should pass. If not, consult `@test-suite-verifier` agent.

## Hour 2: Hands-On Development (60 minutes)

### Local Development Setup (15 minutes)
```bash
mix deps.get              # Install dependencies
mix phx.server           # Start Phoenix server
# Visit http://localhost:4000/game/test1 for game interface
```

**Expected Behavior**: You should see a functional poker game interface where 6 players can join and play hands.

### Code Reading Exercise (30 minutes)
Focus on understanding the core game flow by tracing through these files:

1. **Start Here**: `lib/poker_server/game_server.ex:88-121`
   - This is the preflop betting handler - shows the complete pattern for multiplayer poker

2. **Game State**: `lib/poker_server/game_state.ex:start_hand/1`
   - Shows how hands begin (dealing cards, posting blinds)

3. **Betting Logic**: `lib/poker_server/betting_round.ex:process_action/2`  
   - Core betting validation and pot calculation

4. **Hand Evaluation**: `lib/poker_server/hand_evaluator.ex:evaluate_hand/1`
   - Short deck poker hand ranking (different from regular hold'em)

### Live Development Exercise (15 minutes)
Make a small change to verify your development setup:

1. Open `lib/poker_server_web/live/game_live/show.ex`
2. Find the game state display section
3. Add a small visual change (e.g., add "(Live)" to the page title)
4. Refresh browser to see change
5. Revert the change

This confirms your Phoenix LiveView hot reloading is working.

## Hour 3: Product Context & Next Steps (60 minutes)

### Product Strategy Deep Dive (30 minutes)
Read `/docs/product/requirements.md` carefully, focusing on:

- **Player Segments**: 60% recreational mobile, 40% serious short deck
- **Success Metrics**: 7-day retention >40%, <30s per decision
- **Feature Tiers**: Current MVP status vs future enhancements
- **Monetization Philosophy**: Player-friendly, skill-based progression

**Critical Understanding**: Every technical decision should consider impact on both recreational and serious players.

### Current Development Priorities (20 minutes)
Based on `/docs/technical/implementation-notes.md`:

**Immediate Next Task**: Complete post-flop betting phases
- Current: Only preflop betting implemented  
- Missing: Flop, turn, river betting rounds
- Estimate: 2-3 hours to complete
- Complexity: Low (copy existing preflop pattern)

**After Post-Flop**: Mobile UI optimization for Tier 1 MVP completion

### Agent Usage Guidelines (10 minutes)
Know when to consult specialized agents:

**@poker-product-expert**: Required for
- Any player-facing feature decisions
- UI/UX changes affecting recreational players  
- Monetization or tournament structure decisions
- Feature prioritization questions

**@test-suite-verifier**: Required for
- Verifying test status after code changes
- Before committing changes to core poker logic
- When debugging test failures or flaky tests
- Performance testing of multiplayer components

## Verification Checklist

After 3 hours, you should be able to:

- [ ] Explain the difference between recreational and serious player needs
- [ ] Run the full test suite and understand what each module tests
- [ ] Navigate the codebase to find game logic vs web interface code
- [ ] Start local development server and see functional poker game
- [ ] Identify the current development bottleneck (post-flop betting)
- [ ] Know when to consult @poker-product-expert vs @test-suite-verifier

## Common Gotchas

### Phoenix/Elixir Specific
- **Hot reloading**: Code changes appear immediately, but GenServer state persists
- **Process isolation**: Each tournament runs in separate process for fault tolerance
- **Pattern matching**: Elixir uses pattern matching extensively in game logic

### Poker Domain Specific  
- **Short deck rules**: Only 36 cards, flush beats full house (different from regular hold'em)
- **Server authority**: Never trust client for game decisions - all validation server-side
- **Real-time constraints**: Target <200ms server response for good player experience

### Product Focus
- **Mobile first**: All UI decisions should consider touch interface and portrait mode
- **Speed emphasis**: Super-turbo format means fast decisions, minimize UI friction
- **Fair play critical**: Poker requires absolute game integrity for player trust

## Getting Help

- **Technical questions**: Search tests first (they document expected behavior)
- **Product questions**: Consult @poker-product-expert agent
- **Test issues**: Use @test-suite-verifier agent  
- **Architecture questions**: Reference `/docs/technical/architecture.md`
- **Code patterns**: Look for similar implementations in existing modules

---

**Next Steps After Onboarding**: 
1. Complete post-flop betting implementation (documented in `/docs/technical/implementation-notes.md`)
2. Run comprehensive test suite to verify no regressions
3. Consult @poker-product-expert for mobile UI optimization priorities