# Internal Launch Plan

## Overview
Poker application ready for internal testing. Focus on core functionality over polish.

## Critical Bugs (Must Fix Before Launch)
- [ ] Fix all-in validation bug
  - Bob (1000 chips) all-in, Alice (2000 chips) shouldn't be able to all-in after
  - Likely side pot handling issue
  - **Priority: CRITICAL**
- [ ] Fix game continuation with single player
  - Game should end when only one player has chips
  - **Priority: CRITICAL**
- [ ] Remove debug card visibility
  - Currently shows both players' cards in debug mode
  - **Priority: CRITICAL** (anti-cheat)

## Essential Features (Launch Week)
- [ ] Add basic authentication
  - Simple email/password sufficient for internal users
  - Secure routes from unauthenticated access
  - **Priority: HIGH**
- [ ] Display game context information
  - All players and chip counts
  - Position from dealer
  - Small blind / big blind indicators
  - Current betting round action history
  - **Priority: HIGH**
- [ ] Improve showdown experience
  - Show non-folded players' cards
  - Display hand evaluator descriptions
  - Highlight winning hand
  - **Priority: MEDIUM**
- [ ] Player knockout announcements
  - Clear notification when player eliminated
  - **Priority: MEDIUM**

## Post-Launch Enhancements (Week 2-4)
- [ ] Four color deck option
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
- Core poker rules work correctly
- No obvious cheating vectors
- Basic auth prevents unauthorized access
- Stable hosting for internal team

✅ **Nice to Have:**
- Smooth user experience
- Clear game state visibility
- Crash recovery

## Risk Mitigation
- **Technical Risk:** Keep poker logic separate from data layer for easy iteration
- **Security Risk:** Start with basic auth, expand as needed
- **Performance Risk:** Test WebSocket stability under typical game loads
- **Timeline Risk:** Focus on core functionality, defer polish features

## Launch Checklist
- [ ] All critical bugs fixed
- [ ] Basic authentication implemented
- [ ] Debug features removed
- [ ] Deployed to hosting platform
- [ ] Internal team can access and play
- [ ] No obvious rule violations
- [ ] WebSocket connections stable during gameplay

---

**Note:** This is an internal launch focused on validating core functionality. Polish and advanced features can iterate based on user feedback.