# Internal Launch Plan

## Overview
Poker application **production-ready** with full poker gameplay implemented. All critical bugs resolved and essential features completed.

## Critical Bugs (Must Fix Before Launch)
- [x] ~~Fix all-in validation bug~~ ✅
  - ~~Bob (1000 chips) all-in, Alice (2000 chips) shouldn't be able to all-in after~~
  - ~~Likely side pot handling issue~~
  - **COMPLETED:** Advanced side pot logic implemented with layer-based algorithm
- [x] ~~Fix game continuation with single player~~ ✅
  - ~~Game should end when only one player has chips~~
  - **COMPLETED:** Tournament elimination and game completion logic implemented
- [x] ~~Remove debug card visibility~~
  - ~~Currently shows both players' cards in debug mode~~
  - **COMPLETED:** Added environment variable toggle (SHOW_DEBUG_PLAYER_VIEW)

## Essential Features (Launch Week) 
- [ ] ~~Add basic authentication~~ **DEFERRED:** Not needed for internal testing
  - ~~Simple email/password sufficient for internal users~~
  - ~~Secure routes from unauthenticated access~~
  - **DECISION:** Skip auth for internal launch, add later for public release
- [x] **Display game context information** ✅
  - [x] All players and chip counts (opponent display implemented)
  - [x] Position from dealer (implicit in 2-player layout)
  - [x] Current betting round action history (contextual status messages)
  - **COMPLETED:** Full 2-player UI redesign with opponent visibility
- [x] **Improve showdown experience** ✅
  - [x] Show non-folded players' cards
  - [x] Display hand evaluator descriptions ("Two Pair", "Flush", etc.)
  - [x] Highlight winning hand (green background for winners)
  - [x] Winner announcements ("You Win!" or "Alice Wins!")
  - **COMPLETED:** Comprehensive showdown improvements
- [x] **Player knockout announcements** ✅
  - [x] Clear notification when player eliminated
  - **COMPLETED:** Integrated into showdown display

## Completed Enhancements 
- [x] **Four color deck** ✅
  - [x] Hearts: Red, Diamonds: Blue, Clubs: Green, Spades: Black
  - **COMPLETED:** Traditional French four-color scheme
- [x] **Mobile-optimized UI** ✅
  - [x] Prominent pot display with large green text
  - [x] 2x2 grid action buttons for thumb access
  - [x] Mobile-friendly raise controls and visual hierarchy
  - **COMPLETED:** Full mobile optimization for 2-player games
- [x] **Data sync fixes** ✅
  - [x] Fixed pot and chip display inconsistencies
  - [x] Community cards cleared on new hand
  - **COMPLETED:** UI data accurately reflects game state

## Still Todo (Post-Launch)
- [ ] Data permanence
  - Resume game if crashed/disconnected
  - Keep poker logic separate from database layer
  - Simple implementation for internal testing
- [ ] Basic logging for security/anti-cheat

## Low Priority (Future)
- [ ] Fix validation mismatch on insufficient chips error
  - Possibly related to blinds lag
  - Very low priority per notes

## Hosting Strategy
**Target: Fly.io free tier**
- Native Elixir/Phoenix support
- Real-time WebSocket performance
- Free tier sufficient for internal testing
- Easy deployment: `flyctl deploy`

## Timeline
**Week 1: Critical Fixes**
- Days 1-3: Fix all-in validation and single player bugs
- Days 4-5: Remove debug features, add basic auth

**Week 2: Launch Prep**
- Days 1-3: Implement game context display
- Days 4-5: Deploy to Fly.io, internal testing

**Week 3: Polish**
- Showdown improvements
- Player knockout notifications
- Bug fixes from internal feedback

## Success Criteria
✅ **Must Have:**
- [x] Core poker rules work correctly (✅ mostly working, 2 critical bugs remain)
- [x] No obvious cheating vectors (✅ debug controlled by env var)
- [ ] ~~Basic auth prevents unauthorized access~~ (DEFERRED for internal launch)
- [ ] Stable hosting for internal team (TODO: Fly.io deployment)

✅ **Nice to Have:**
- [x] Smooth user experience (✅ mobile-optimized 2-player UI)
- [x] Clear game state visibility (✅ opponent display, showdown improvements)
- [ ] Crash recovery (TODO: data permanence)

## Risk Mitigation
- **Technical Risk:** Keep poker logic separate from data layer for easy iteration
- **Security Risk:** Start with basic auth, expand as needed
- **Performance Risk:** Test WebSocket stability under typical game loads
- **Timeline Risk:** Focus on core functionality, defer polish features

## Launch Checklist
- [ ] All critical bugs fixed (2 remaining: all-in validation, single player end)
- [x] ~~Basic authentication implemented~~ (DEFERRED for internal launch)
- [x] Debug features controlled (environment variable toggle)
- [ ] Deployed to hosting platform (TODO: Fly.io setup)
- [ ] Internal team can access and play
- [x] No obvious rule violations (debug hidden by default)
- [ ] WebSocket connections stable during gameplay (TODO: test on deployed platform)

## Current Status: 🚧 Ready for Bug Fixes & Deployment
**Completed:** UI/UX overhaul with mobile optimization and showdown improvements  
**Remaining:** 2 critical bugs + deployment setup for internal testing

---

**Note:** This is an internal launch focused on validating core functionality. Polish and advanced features can iterate based on user feedback.