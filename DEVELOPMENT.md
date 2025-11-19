# FightBase Development Guide

## Quick Start

### Building the Project

```bash
# If you have Nim installed:
nim c -d:release src/fightBase.nim

# Or with nimble:
nimble build
```

### Running Your First Simulation

```bash
# Run a single test fight with verbose output
./fightBase test --verbose

# Run a batch of 1000 simulations
./fightBase batch 1000

# Check what was discovered
./fightBase stats
```

## Understanding the System

### State Flow

```
Initial State
    ↓
[Select Fighter A's move from legal moves]
    ↓
[Apply move → modify state]
    ↓
[Check if terminal]
    ↓
[Switch to Fighter B]
    ↓
[Repeat]
```

### Example State Progression

```
Move 1: A uses "left Jab (Boxing)"
  A[fat:0.05 dmg:0.0 bal:0.98] <-Medium-> B[fat:0.0 dmg:0.05 bal:0.95]

Move 2: B uses "Cross (Boxing/Karate)"
  A[fat:0.05 dmg:0.15 bal:0.88] <-Medium-> B[fat:0.12 dmg:0.05 bal:0.87]

Move 3: A uses "Teep (Muay Thai)"
  A[fat:0.20 dmg:0.15 bal:0.78] <-Long-> B[fat:0.12 dmg:0.05 bal:0.72]

... continues until terminal or max moves ...
```

## Adding New Moves

### Template for a Striking Move

```nim
proc createYourMove*(): Move =
  result = Move(
    id: "unique_move_id",
    name: "Move Name (Style)",
    category: Straight,  # or Arc, Whip, Push, etc.
    energyCost: 0.15,
    reach: 0.8,
    height: High,  # Low, Mid, High
    angleBias: 0.0,
    recoveryTime: 0.4,
    lethalPotential: 0.2,
    positionShift: PositionDelta(
      distanceChange: 0.0,
      angleChange: 0.0,
      balanceChange: -0.05,
      heightChange: 0.0
    ),
    styleOrigins: @["Your Style"],
    followups: @["other_move_ids"]
  )

  # Define when this move is legal
  result.prerequisites = proc(state: FightState, who: FighterID): bool =
    let fighter = if who == FighterA: state.a else: state.b
    # Your constraints here
    result = fighter.rightArm.free and
             fighter.fatigue < 0.85 and
             fighter.pos.balance >= 0.5

  # Define what this move does
  result.apply = proc(state: var FightState, who: FighterID) =
    var attacker = if who == FighterA: addr state.a else: addr state.b
    var defender = if who == FighterA: addr state.b else: addr state.a

    # Apply effects
    applyFatigue(attacker[], 0.15)

    # Check if it lands
    if rand(1.0) > defender[].pos.balance * 0.5:
      applyDamage(defender[], 0.15)
      applyBalanceChange(defender[], -0.1)

    state.sequenceLength += 1
```

### Template for a Grappling Move

```nim
proc createGrappleMove*(): Move =
  result = Move(
    id: "grapple_id",
    name: "Grapple Move (Judo)",
    category: Throw,  # or Clinch, Lock, Choke, Takedown
    energyCost: 0.3,
    reach: 0.4,
    height: Mid,
    angleBias: 0.0,
    recoveryTime: 0.7,
    lethalPotential: 0.6,
    positionShift: PositionDelta(
      distanceChange: -0.2,
      angleChange: 45.0,
      balanceChange: -0.25,
      heightChange: -0.5
    ),
    styleOrigins: @["Judo", "Wrestling"],
    followups: @["ground_moves"]
  )

  result.prerequisites = proc(state: FightState, who: FighterID): bool =
    let fighter = if who == FighterA: state.a else: state.b
    let opponent = if who == FighterA: state.b else: state.a
    result = state.distance == Contact and
             fighter.control in {Clinch, Underhook} and
             opponent.pos.balance < 0.6

  result.apply = proc(state: var FightState, who: FighterID) =
    var attacker = if who == FighterA: addr state.a else: addr state.b
    var defender = if who == FighterA: addr state.b else: addr state.a

    applyFatigue(attacker[], 0.3)

    # Success depends on opponent's balance
    if defender[].pos.balance < 0.4:
      # Successful throw
      defender[].pos.balance = 0.1
      applyDamage(defender[], 0.25)
      attacker[].control = SideControl
    else:
      # Partial success or failure
      applyBalanceChange(defender[], -0.2)
      applyFatigue(attacker[], 0.1)

    state.sequenceLength += 1
```

### Register Your Move

In `moves.nim`, add to `initializeMoves()`:

```nim
proc initializeMoves*() =
  # ... existing moves ...
  registerMove(createYourMove())
  registerMove(createGrappleMove())

  echo "Registered ", ALL_MOVES.len, " moves"
```

## Adding New Constraints

### In `constraints.nim`

```nim
proc canDoSpecialTechnique*(fighter: Fighter): bool =
  ## Custom constraint for your technique
  fighter.pos.balance >= 0.7 and
  fighter.fatigue < 0.5 and
  fighter.leftLeg.free and
  fighter.rightLeg.free

proc requiresFlankPosition*(fighter: Fighter): bool =
  ## Checks if fighter is on opponent's flank
  fighter.liveSide in {DeadSideLeft, DeadSideRight}
```

### Using in Move Prerequisites

```nim
result.prerequisites = proc(state: FightState, who: FighterID): bool =
  let fighter = if who == FighterA: state.a else: state.b
  result = canDoSpecialTechnique(fighter) and requiresFlankPosition(fighter)
```

## Working with Unknown States

### Workflow

1. **Run simulations:**
   ```bash
   ./fightBase batch 10000 --max 200
   ```

2. **Check for unknown states:**
   ```bash
   ./fightBase stats
   ```

   Output:
   ```
   State Database Statistics:
     Total unique states: 45234
     Unresolved unknown states: 127
     Terminal states: 3421
     Recorded transitions: 198543
   ```

3. **Export for review:**
   ```bash
   ./fightBase export
   ```

   Creates `fight_states.txt` with full descriptions.

4. **Review unknown states:**
   ```bash
   ./fightBase list
   ```

5. **Add missing moves or fix prerequisites**

6. **Mark resolved in database** (manual SQL or future UI)

7. **Re-run simulations**

### Example Unknown State

```
======================================================================
FIGHT STATE (Hash: a3f8b2c4...)
Sequence Length: 23 | Distance: Contact
======================================================================

Fighter A:
  Position: (-0.30, 0.00, 0.00)
  Facing: 90° | Stance: Orthodox | Balance: 0.45
  Fatigue: 0.65 | Damage: 0.30
  Side: LiveSideRight | Control: Clinch
  Left arm:  ready
  Right arm: ready
  Left leg:  ready
  Right leg: trapped

Fighter B:
  Position: (0.30, 0.00, 0.00)
  Facing: 270° | Stance: Southpaw | Balance: 0.35
  Fatigue: 0.70 | Damage: 0.40
  Side: Centerline | Control: Underhook
  Left arm:  ready
  Right arm: extended
  Left leg:  ready
  Right leg: ready
======================================================================
```

**Analysis:** Fighter A has clinch control but Fighter B has underhook. Both are fatigued. A's right leg is trapped. This is a realistic clinch battle position.

**Possible moves to add:**
- Break clinch attempt
- Knee strike from clinch
- Dirty boxing (short punches)
- Sweep attempt targeting trapped leg
- Control battle (improve position)

## Understanding the Data

### SQLite Database Structure

```sql
-- View all states
SELECT state_hash, sequence_length, is_terminal
FROM states
ORDER BY seen_count DESC
LIMIT 10;

-- Find common transitions
SELECT move_id, COUNT(*) as frequency
FROM state_transitions
GROUP BY move_id
ORDER BY frequency DESC;

-- Check unknown state patterns
SELECT
  json_extract(state_json, '$.distance') as distance,
  json_extract(state_json, '$.a.control') as a_control,
  COUNT(*) as occurrences
FROM unknown_states
WHERE resolved = 0
GROUP BY distance, a_control;
```

### Analyzing Move Effectiveness

After running simulations, you can analyze:

```sql
-- Most common successful transitions
SELECT
  move_id,
  COUNT(*) as uses,
  AVG(CAST(json_extract(to_json, '$.terminal') AS INTEGER)) as terminal_rate
FROM state_transitions st
JOIN states s ON st.to_hash = s.state_hash
GROUP BY move_id
ORDER BY uses DESC;
```

## Performance Considerations

### Optimization Tips

1. **Batch size**: Start with 1000, increase to 100,000 once stable
2. **Max sequence length**: 150-200 is realistic; 300+ rarely needed
3. **Database**: Use SSD for better I/O performance
4. **Move count**: 20-50 moves is good starting point; 100+ is fine

### Memory Usage

- Each state: ~500 bytes
- 1M states: ~500MB RAM
- Database: ~200MB per 1M states (compressed)

### Simulation Speed

- ~1000-5000 fights/second (single thread)
- Scales linearly with move count
- Terminal states found faster than max-length sequences

## Testing New Moves

### Interactive Testing

```nim
# Add to your move file or create test file
when isMainModule:
  import moves

  initializeMoves()

  # Create test state
  var state = createInitialState()

  # Check if your move is legal
  let legal = legalMoves(state, FighterA)
  echo "Legal moves: "
  for m in legal:
    echo "  - ", m.name

  # Apply a specific move
  let myMove = getMoveById("your_move_id")
  if myMove.isSome:
    myMove.get().apply(state, FighterA)
    echo "\nAfter move:"
    echo toTextRepr(state)
```

## Common Patterns

### Move Chains

Good moves enable followups:

```
Jab → Cross → Hook (boxing combo)
Teep → Roundhouse (Thai combo)
Clinch Entry → Knee → Throw (grappling sequence)
```

Encode this in `followups` field:

```nim
followups: @["cross_right", "hook_left", "step_back"]
```

### Fatigue Management

Realistic fights have fatigue curves:

```
Moves 0-10:   Low fatigue, full options
Moves 10-30:  Moderate fatigue, some limits
Moves 30-50:  High fatigue, defensive focus
Moves 50+:    Exhaustion, desperation
```

### Terminal Patterns

Common endings:

1. **Exhaustion**: Fatigue > 0.95
2. **Damage**: Cumulative hits > 0.8
3. **Balance failure**: Knockdown or fall
4. **Control dominance**: Mount + no escape
5. **Submission**: Joint lock or choke secured

## Next Steps

1. **Add 10-20 more moves** from different arts
2. **Run 100k simulations** overnight
3. **Review unknown states** and patterns
4. **Add missing techniques**
5. **Implement backward propagation** (future)
6. **Build visualization** (optional)
7. **Create style profiles** for martial arts comparison

## Troubleshooting

### "No legal moves found immediately"

- Check move prerequisites are not too restrictive
- Verify initial state allows at least some moves
- Add defensive/neutral moves (step back, guard, etc.)

### "All fights end at max length"

- Add more terminal conditions
- Increase damage from successful hits
- Make throws/locks more decisive
- Reduce starting balance/fatigue thresholds

### "Same states repeating"

- Normal! Fights have common positions
- Database deduplicates automatically
- Focus on transition variety, not state variety

### "Unknown states appearing frequently"

- Good sign! System is exploring edge cases
- Review and add appropriate moves
- Some unknown states reveal unrealistic positions (fix prerequisites)

## Contributing

When adding moves:

1. **Name clearly**: Include style origin
2. **Balance values**: Compare to existing moves
3. **Test interactively**: Verify it looks right
4. **Document**: Add comment explaining the technique
5. **Categorize properly**: Use correct canonical category

## Resources

- [Nim Documentation](https://nim-lang.org/docs/)
- [SQLite SQL Syntax](https://www.sqlite.org/lang.html)
- Martial arts references for technique details
- Biomechanics resources for realistic constraints

## Future Features

- [ ] Backward propagation engine
- [ ] Win distance computation
- [ ] Style profile system
- [ ] Multi-threaded simulation
- [ ] Web visualization
- [ ] Interactive state explorer
- [ ] Move effectiveness analytics
- [ ] Style comparison reports
- [ ] Training sequence generator
