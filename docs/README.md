# Documentation Index
## Mobile Short Deck Poker Project

This directory contains comprehensive documentation organized for efficient development and product decision-making.

## Quick Navigation

### 🎯 Product Strategy (`/docs/product/`)
- **[Product Requirements](./product/requirements.md)** - Target players, success metrics, feature tiers
- **[Product Decisions](./product/decisions/)** - Architecture Decision Records (ADRs) for significant choices

### 🔧 Technical Documentation (`/docs/technical/`)
- **[System Architecture](./technical/architecture.md)** - WebSocket event-driven design, anti-cheat patterns
- **[Edge Cases & Testing](./technical/edge-cases.md)** - Known issues, test coverage gaps, implementation priorities
- **[Implementation Notes](./technical/implementation-notes.md)** - Current development context and immediate tasks

### 🚀 Development Process (`/docs/process/`)
- **[Claude AI Instructions](./process/claude-instructions.md)** - AI assistant context and specialized agent usage
- **[Developer Onboarding](./process/onboarding.md)** - 3-hour guide for new team members

### 📡 API Reference (`/docs/api/`)
*Coming soon: WebSocket event documentation, client-server protocol specifications*

## Documentation Usage Patterns

### For Product Decisions
1. **Start with**: [Product Requirements](./product/requirements.md) - understand target players and success metrics
2. **Check history**: [Product Decisions](./product/decisions/) - review previous architectural choices
3. **Consider impact**: Use player segment framework from requirements
4. **Document decision**: Create new ADR in decisions/ directory

### For Technical Implementation  
1. **Understand system**: [System Architecture](./technical/architecture.md) - grasp design constraints
2. **Check known issues**: [Edge Cases](./technical/edge-cases.md) - avoid known problem areas
3. **Current context**: [Implementation Notes](./technical/implementation-notes.md) - understand current priorities
4. **Update documentation**: Keep technical docs current after changes

### For New Team Members
1. **Complete onboarding**: [Developer Onboarding](./process/onboarding.md) - 3-hour comprehensive guide
2. **Read product context**: [Product Requirements](./product/requirements.md) - understand business goals
3. **Study architecture**: [System Architecture](./technical/architecture.md) - grasp technical design
4. **Review AI context**: [Claude Instructions](./process/claude-instructions.md) - understand development workflow

## Key Principles

### Documentation-Driven Development
- **Read before coding**: Understand context from existing documentation
- **Update while coding**: Keep documentation current with implementation
- **Capture decisions**: Document significant choices for future reference
- **Enable others**: Write for team members joining 6 months from now

### Quality Standards
- **Accuracy**: All technical details verified against actual implementation
- **Relevance**: Focus on information needed for development and product decisions
- **Accessibility**: Written for developers with varying poker and Elixir experience
- **Currency**: Regular updates to maintain usefulness

## Maintenance Schedule

### Weekly Updates
- Update test counts and module completion status
- Review and categorize new session history
- Update implementation notes with current development priorities

### Monthly Reviews  
- Verify product requirements alignment with actual development
- Update architecture documentation for significant system changes
- Archive old session history (>30 days)
- Review and update developer onboarding for accuracy

### Release Updates
- Document new features in product requirements
- Update API documentation for client-server changes
- Create ADRs for significant architectural decisions
- Update success metrics and player segment analysis

## Contributing to Documentation

### Adding New Documentation
- **Product docs**: Focus on player impact and business justification
- **Technical docs**: Include code examples and implementation context
- **Process docs**: Write for team scalability and knowledge transfer

### Updating Existing Docs
- Verify accuracy against current implementation
- Maintain consistent formatting and structure
- Cross-reference related documents
- Update last-modified dates and changelog sections

---

*Last Updated: August 2025*  
*Next Review: Monthly architecture review cycle*