# Claude Code Integration Guidelines

## Documentation-First Development Approach

### Before Starting Any Major Work
**Required Reading**: Always check these files before implementing significant changes:

1. **Product Impact**: `/docs/product/requirements.md` 
   - Player segment considerations (recreational vs serious)
   - Feature tier prioritization
   - Success metrics and product principles

2. **Technical Context**: `/docs/technical/architecture.md` & `/docs/technical/implementation-notes.md`
   - Server-authoritative patterns
   - Real-time multiplayer constraints  
   - Current implementation status and bottlenecks

3. **Historical Decisions**: `/docs/product/decisions/` (ADRs)
   - Past architecture choices and rationale
   - Failed approaches to avoid repeating
   - Decision patterns and criteria used

### Documentation Integration Workflow

#### For New Features
1. **Read** relevant existing documentation
2. **Consult** @poker-product-expert if feature affects player experience
3. **Document** significant decisions using ADR template
4. **Update** status in CLAUDE.md when milestones completed

#### For Bug Fixes
1. **Check** `/docs/technical/edge-cases.md` for known issues
2. **Verify** fix doesn't conflict with documented patterns
3. **Update** edge cases document if new scenarios discovered

#### For Refactoring
1. **Reference** `/docs/technical/architecture.md` for system design principles
2. **Ensure** changes maintain server-authoritative approach
3. **Consult** @test-suite-verifier for comprehensive regression testing

## Enhanced Agent Usage Guidelines

### @poker-product-expert Consultation (Mandatory)

**Required Scenarios:**
- Any feature affecting player-facing UI or gameplay experience
- Tournament structure or game format modifications
- Monetization feature implementation or pricing decisions
- Player onboarding flow or tutorial system changes
- Achievement, progression, or retention mechanic design
- Competitive balance changes (blind structure, hand evaluation, etc.)

**Optional But Recommended:**
- Technical architecture decisions with user experience implications
- Performance optimizations that might affect game feel or responsiveness
- Error handling approaches that impact player experience
- Feature prioritization or roadmap planning discussions

**Consultation Pattern:**
```markdown
Context: [Brief description of the decision or feature]
Player Impact: [How this affects recreational vs serious players]
Product Goals: [Alignment with speed, mobile-first, fair play principles]
Request: [Specific guidance needed from poker product perspective]
```

### @test-suite-verifier Consultation (Mandatory)

**Required Scenarios:**
- Before committing changes to core poker logic modules (GameState, BettingRound, HandEvaluator, Tournament)
- After implementing features with significant test count changes (>5 new tests)
- When experiencing flaky or intermittent test failures
- Before branch merges that affect real-time multiplayer functionality
- After performance-related changes to verify no regression

**Optional But Recommended:**  
- When adding complex concurrency tests
- After refactoring to verify test coverage remains comprehensive
- When debugging test suite performance issues

**Consultation Pattern:**
```markdown
Context: [What code was changed and why]
Test Scope: [Which test modules are likely affected]  
Verification Needed: [Specific test status confirmation required]
Risk Assessment: [Level of confidence needed before proceeding]
```

### Self-Sufficient Decisions (No Agent Consultation Required)

- Minor bug fixes with existing test coverage
- Code style improvements and refactoring within established patterns
- Documentation updates that don't change functionality
- Dependency updates and security patches
- Development tooling improvements (linting, formatting, etc.)

## Decision Documentation Requirements

### When to Create Architecture Decision Records (ADRs)

**Always Document:**
- Player-facing feature implementations
- Changes to tournament structure or poker rules
- Architecture modifications affecting scalability or performance
- Security or anti-cheat implementations
- Monetization feature additions
- Third-party service integrations

**Document Template**: Use `/docs/product/decisions/000-adr-template.md`

**ADR Lifecycle:**
1. **Draft**: Create ADR in "Proposed" status during planning
2. **Review**: Consult relevant agents and get team feedback  
3. **Decision**: Update to "Accepted" status with final rationale
4. **Implementation**: Reference ADR during implementation
5. **Retrospective**: Update with actual outcomes after completion

### Session History Organization

**Automatic Categorization**: Based on session content and decisions made
- **Product Decisions**: `/session_history/decisions/` - Strategy discussions, feature prioritization
- **Technical Explorations**: `/session_history/technical/` - Implementation attempts, architecture analysis
- **Archive**: `/session_history/archive/` - Sessions older than 30 days for reference only

**Session Capture Requirements:**
- Document significant decisions made during AI assistance sessions
- Create ADRs for any architectural or product choices
- Update CLAUDE.md status when major milestones achieved
- Note failed approaches to prevent repeating in future sessions

## Code Quality and Testing Integration

### Pre-Commit Requirements
- **Core poker logic changes**: Must consult @test-suite-verifier
- **Player-facing features**: Must consult @poker-product-expert  
- **Security-related changes**: Must verify against anti-cheat requirements in architecture docs
- **Performance changes**: Must verify against <200ms response time requirement

### Testing Philosophy Integration
- **Test-driven approach**: Write tests first for new poker logic
- **Edge case coverage**: Reference `/docs/technical/edge-cases.md` for known scenarios
- **Concurrency testing**: Required for all real-time multiplayer features
- **Security testing**: Validate all server-authoritative patterns

### Code Review Focus Areas (Based on Documentation)
- **Player psychology impact**: Does this change support both recreational and serious players?
- **Mobile usability**: Is this compatible with touch interface and portrait mode?
- **Anti-cheat compliance**: Maintains server-authoritative approach?
- **Performance impact**: Stays within real-time latency requirements?
- **Product tier alignment**: Appropriate priority level for current development phase?

## Maintenance and Evolution

### Weekly Documentation Review
- Update test counts and module completion status in CLAUDE.md
- Categorize recent session history into appropriate directories
- Review accuracy of product requirements and success metrics
- Archive old session files (>30 days) to maintain organization

### Monthly Documentation Audit  
- Verify accuracy of architectural documentation vs actual code
- Update onboarding guide with any new patterns or gotchas discovered
- Review ADR decisions for accuracy and lessons learned
- Update agent consultation guidelines based on experience

### Release Documentation Updates
- Document new features in appropriate product or technical docs
- Create ADRs for significant features or architectural changes
- Update feature tier status (Tier 1 MVP → Tier 2 Enhancement, etc.)
- Capture lessons learned and update development patterns

---

## Quick Reference

**Need product guidance?** → @poker-product-expert + `/docs/product/requirements.md`  
**Need test verification?** → @test-suite-verifier + comprehensive test run  
**Making architectural changes?** → Read `/docs/technical/architecture.md` first  
**Significant decision?** → Create ADR using template in `/docs/product/decisions/`  
**New team member?** → Follow `/docs/process/onboarding.md` 3-hour guide