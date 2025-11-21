# FightBase Documentation

## Overview

FightBase is a martial arts tablebase generator - a chess-style endgame database for hand-to-hand combat. It systematically explores all possible fight positions to discover effective techniques and underlying martial arts principles.

## Quick Start

1. **Read the usage guide**: [GAME_TREE_USAGE.md](./GAME_TREE_USAGE.md)
2. **Run the example**: `nim c -r examples/tree_generation_example.nim`
3. **Validate moves**: Manually inspect generated states to ensure realism
4. **Scale up**: Once confident, increase iterations for deeper analysis

## Core Features

### Context-Dependent State Transitions

Moves behave differently based on current posture:
- **Standing** → Normal effectiveness for most moves
- **Crouched** → Weak strikes, strong takedowns (1.3x multiplier)
- **Grounded** → Very limited options, defensive posture
- **Jumping** → Powerful attacks (1.4x), terrible defense (0.3x)
- **Spinning** → Devastating strikes (1.5-1.6x), very vulnerable (0.2x defense)

Example: A jab from crouched = 60% effectiveness, but takedowns = 130%

### Bidirectional State Changes

Moves can affect both fighters' states:
- Attacker changes posture (duck → crouched, spin → spinning)
- Defender changes posture if hit (push kick → grounded, throw → grounded)
- Momentum transfers between fighters
- Overcommitment on missed high-commitment moves

### Chess-Style Tablebase Architecture

**Position-only state space**:
- Same position = same node (finite tree)
- States identified by hash of position state
- No damage/fatigue in state (keeps tree tractable)

**Path-dependent overlays**:
- Damage accumulated along paths
- Critical hits tracked (liver, jaw, temples)
- Terminal evaluation considers position + damage

**Turn-based expansion**:
- Player1 (white) always moves first
- Alternating turns like chess
- Systematic exploration of all branches

### Move Number Tracking

Each state records its depth from initial position:
```sql
SELECT * FROM states WHERE move_number = 5
```

Enables level-based (breadth-first) expansion:
- Depth 0-2: Initial exchanges
- Depth 3-5: Early game positioning
- Depth 6-15: Mid-game tactics
- Depth 16+: Late game, many terminal states

## Documentation

- **[GAME_TREE_USAGE.md](./GAME_TREE_USAGE.md)**: Complete usage guide
  - Database schema
  - Query examples
  - Analysis workflow
  - Performance considerations
  - Troubleshooting

## Examples

- **[tree_generation_example.nim](../examples/tree_generation_example.nim)**: Basic generation and analysis
  - Generate small test tree
  - Inspect sample states
  - Analyze move effectiveness
  - Validate realism

## Database Schema

### States Table
- `state_hash`: Unique position identifier
- `move_number`: Depth level (0, 1, 2, ...)
- `last_mover`: "Player1" or "Player2"
- `is_terminal`: 1 if game over
- `winner`: "Player1", "Player2", or NULL

### State Transitions Table
- `from_hash` → `to_hash`: Parent to child
- `move_id`: Move that was applied
- `damage_dealt`: Damage in this transition
- `vulnerabilities_hit`: Zones hit (JSON)

### Path Damage Table
- `cumulative_damage_p1`: Total damage to Player1
- `cumulative_damage_p2`: Total damage to Player2
- `critical_hits`: Liver/jaw/temples (JSON)

## Terminal Conditions

Fights end when:

1. **Position-based**:
   - Balance < 0.2 (falling)
   - No viable moves (trapped)

2. **Damage-based**:
   - Cumulative damage > 0.8
   - Critical hit with sufficient force:
     - Liver: > 800N
     - Jaw: > 900N
     - Temples: > 700N

3. **Length-based**:
   - 200 moves without conclusion (stalemate/draw)

## Analysis Workflow

1. **Generate small tree** (100-1000 states)
2. **Manually inspect** 5-10 random positions
3. **Validate moves** are realistic for each posture
4. **Check patterns**:
   - Do crouched fighters mostly use takedowns?
   - Do spinning attacks overcommit when missed?
   - Do push kicks lead to knockdowns?
5. **Iterate on move definitions** if needed
6. **Scale up** once confident
7. **Extract principles** from patterns in winning fights

## Expected Insights

After generating and analyzing thousands of fights, patterns should emerge:

- **Effective sequences**: "Jab → Cross → Clinch → Throw → Ground control"
- **Posture transitions**: "Duck → Takedown → Ground → Win"
- **Momentum traps**: "Spinning backfist miss → Overcommit → Fall → Lose"
- **Distance management**: "Push kick → Create space → Advantage"
- **Style effectiveness**: Which martial arts moves appear in winning sequences

These patterns reveal the underlying principles of effective martial arts.

## Performance

### Expected Tree Size
- **1,000 states**: ~1MB, quick test run
- **10,000 states**: ~10MB, early game coverage
- **100,000 states**: ~100MB, good mid-game depth
- **1,000,000 states**: ~1GB, comprehensive analysis

### Generation Time
- **Small tree (1K states)**: ~10 seconds
- **Medium tree (10K states)**: ~2 minutes
- **Large tree (100K states)**: ~30 minutes
- **Very large (1M states)**: Several hours

Time depends on:
- Batch size (larger = faster but less granular progress)
- CPU speed
- Number of viable moves per state
- Terminal state frequency

## Architecture Notes

### Why Separate State from Damage?

**Problem**: Same position with different accumulated damage are different game states. Including damage in state → infinite tree (damage is continuous).

**Solution**:
- **State** = position only (discrete, finite)
- **Damage** = path metadata (continuous, stored per transition)

This keeps the tree finite while allowing realistic damage-based outcomes.

### Why Move Number?

Level-based expansion allows:
- Breadth-first tree generation (all depth N before depth N+1)
- Easy analysis by game phase (opening/mid-game/endgame)
- Efficient querying: `WHERE move_number = X`
- Retrograde analysis (work backward from terminal states)

## Future Enhancements

Potential additions:
- **Move prediction**: Given position, suggest best move
- **Style analysis**: Which martial art is most effective?
- **Combo discovery**: Find effective move combinations
- **Weakness detection**: Identify vulnerable positions
- **Training mode**: Practice against optimal play

## References

- Chess endgame tablebases (inspiration)
- Martial arts biomechanics
- Fight game state machines
- Minimax/alpha-beta pruning (future)

## License

MIT
