# Hand Evaluation Test Bug: Incorrect Hand Type Labeling

## Issue Summary

A critical bug has been identified in the hand evaluator test suite where a valid straight (A-K-Q-J-10) is incorrectly labeled as a high card hand, potentially masking underlying issues with hand evaluation logic.

## Location

**File:** `/Users/y/Apps/ship-it/test/hand_evaluator_test.exs`  
**Line:** 499-520  
**Test:** `"A-6-7-8-9 straight beats no straight"`

## Detailed Description

### The Problem

The test constructs two hands manually:

1. **wheel_straight**: Correctly labeled as `:straight` with cards A-6-7-8-9
2. **high_card**: **Incorrectly labeled** as `:high_card` with cards A-K-Q-J-10

### Why This Is Wrong

The second hand (A-K-Q-J-10) is actually a **straight** - specifically the highest possible straight in short deck poker (10-J-Q-K-A). According to poker rules, this should be labeled as `:straight`, not `:high_card`.

### Current Test Behavior

The test currently:
- Expects the A-6-7-8-9 straight to beat the "high card" A-K-Q-J-10
- Passes successfully, returning `:greater`

### What Should Happen

In correct poker logic:
- Both hands should be labeled as `:straight`  
- The A-K-Q-J-10 straight should beat the A-6-7-8-9 wheel straight
- The comparison should return `:less` (wheel straight loses to ace-high straight)

## Scope of Investigation Required

### 1. Test Suite Integrity
- Verify if other tests have similar mislabeling issues
- Check if this is an isolated incident or part of a pattern

### 2. Hand Evaluation Logic
- Determine if `HandEvaluator.evaluate_hand/2` correctly identifies A-K-Q-J-10 as a straight
- Test whether the bug is only in manual test construction or also in the core evaluation logic

### 3. Card Representation Consistency
- Confirm that `:ten` atom usage is consistent throughout the codebase
- Verify no conflicts between different card representations (10 vs :ten)

### 4. Short Deck Poker Rules Compliance
- Validate that all straight detection logic follows short deck poker rules
- Ensure wheel straight (A-6-7-8-9) is properly handled as the lowest straight
- Confirm ace-high straight (10-J-Q-K-A) is properly handled as the highest straight

## Impact Assessment

### Immediate Impact
- Test suite provides false confidence about hand comparison logic
- Potential masking of bugs in core hand evaluation functionality

### Potential Broader Impact
- If the bug extends beyond tests into core logic, game outcomes could be incorrect
- Players could experience unexpected hand rankings in actual gameplay
- Tournament integrity could be compromised if hand evaluation is faulty

## Test Cases to Validate

1. `HandEvaluator.evaluate_hand/2` with hole cards and community cards that should form A-K-Q-J-10 straight
2. Direct comparison between properly labeled A-6-7-8-9 and A-K-Q-J-10 straights
3. Edge cases around straight detection in short deck format
4. Verification that all valid 5-card straights in short deck are correctly identified

## Evidence

```elixir
# Current (incorrect) test code:
high_card =
  {:high_card,          # <- This label is wrong
   [
     card(:ace, :clubs),
     card(:king, :diamonds),
     card(:queen, :hearts),
     card(:jack, :spades),
     card(:ten, :clubs)   # <- This is A-K-Q-J-10, which IS a straight
   ]}
```

## Priority

**High** - This affects core game logic validation and could indicate broader issues with hand evaluation functionality that directly impacts gameplay fairness.