# FightBase - Martial Arts Simulation Engine

A research-oriented combat simulation engine designed to model realistic fight sequences, analyze martial arts techniques, and build a comprehensive "tablebase" of fighting positions similar to chess endgame databases.

## Overview

FightBase simulates martial arts combat using:
- **Discrete biomechanical states** instead of full 3D physics
- **Constraint-based move validation** (fatigue, balance, limb availability)
- **Forward simulation** to explore millions of possible sequences
- **Backward propagation** to compute win distances from terminal states
- **Multi-art integration** supporting techniques from many martial systems
- **Unknown state logging** for human review and system improvement

## Architecture

### Core Components

```
src/
├── fight_types.nim      # Core type definitions (Fighter, FightState, Move)
├── constraints.nim      # Physical constraint checking
├── moves.nim           # Move database and definitions
├── state_storage.nim   # SQLite-based state persistence
├── simulator.nim       # Forward simulation engine
├── fight_display.nim   # Text representation of states
└── fightBase.nim       # Main CLI entry point
```

### State Model

Each `FightState` contains:
- **Two fighters** with positions, stances, balance
- **Limb status** (free, extended, damaged, angle)
- **Fatigue and damage** values (0.0-1.0)
- **Distance** between fighters (Contact, Short, Medium, Long, VeryLong)
- **Control state** (None, Clinch, Mount, BackControl, etc.)
- **Live/dead side positioning** (tactical angle relative to opponent)

### Move System

Moves are defined as objects with:
- **Prerequisites** (proc checking if move is legal in current state)
- **Application** (proc that modifies the state)
- **Energy cost**, reach, recovery time, lethality
- **Canonical category** (Straight, Arc, Throw, Clinch, etc.)
- **Style origins** (which martial arts the technique comes from)

## Installation

```bash
# Clone the repository
git clone <repo-url>
cd fightBase

# Build with Nim
nim c -d:release src/fightBase.nim

# Or use nimble
nimble build
```

## Usage

### Run a Single Test Fight

```bash
./fightBase test --verbose
```

This runs one fight with detailed output showing each move.

### Run Batch Simulations

```bash
# Simulate 10,000 fights
./fightBase batch 10000

# With custom settings
./fightBase batch 50000 --max 150 --db large_batch.db
```

This will:
1. Generate random initial positions
2. Simulate fights until terminal state or max moves
3. Record all states to SQLite database
4. Log states with no legal moves for review

### View Statistics

```bash
./fightBase stats --db fight_states.db
```

Shows:
- Total unique states discovered
- Unresolved unknown states (need human input)
- Terminal states (winning positions)
- Recorded transitions

### Export Unknown States

```bash
./fightBase export --db fight_states.db
```

Creates `fight_states.txt` with human-readable descriptions of all positions where the simulator couldn't find legal moves.

### List Unknown States

```bash
./fightBase list --db fight_states.db
```

Shows the first 20 unresolved unknown states in the terminal.

## Example Output

### Compact State Representation
```
A[fat:0.3 dmg:0.1 bal:0.9] <-Medium-> B[fat:0.4 dmg:0.2 bal:0.8]
```

### Full State Representation
```
======================================================================
FIGHT STATE (Hash: a3f8b2c4...)
Sequence Length: 15 | Distance: Short
======================================================================

Fighter A:
  Position: (-1.20, 0.00, 0.00)
  Facing: 90° | Stance: Orthodox | Balance: 0.85
  Fatigue: 0.25 | Damage: 0.10
  Side: Centerline | Control: None
  Left arm:  ready
  Right arm: extended
  Left leg:  ready
  Right leg: ready

Fighter B:
  Position: (1.20, 0.00, 0.00)
  Facing: 270° | Stance: Southpaw | Balance: 0.75
  Fatigue: 0.35 | Damage: 0.20
  Side: Centerline | Control: None
  Left arm:  ready
  Right arm: ready
  Left leg:  ready
  Right leg: damaged(0.4)
```

## Constraint System

The engine automatically filters legal moves based on:

### Physical Constraints
- **Distance**: Can the move reach at current distance?
- **Balance**: Does the fighter have enough stability?
- **Limbs**: Are required limbs free and undamaged?
- **Fatigue**: Does the fighter have energy for this move?
- **Stance**: Is the current stance compatible?

### Tactical Constraints
- **Angle**: Is the fighter positioned correctly?
- **Control**: Does grappling control allow striking?
- **Live/Dead Side**: Does position enable this technique?
- **Opponent State**: Is opponent vulnerable to this move?

### Terminal Conditions
Fight ends when:
- Balance < 0.2 (falling)
- Damage > 0.8 (incapacitated)
- Fatigue > 0.95 (exhausted)
- Dominant control with no escape (mount, back control, lock, choke)
- No legal moves available

## Move Categories

Moves are normalized into canonical categories:

**Striking:**
- Straight (jab, cross, front kick)
- Arc (hook, roundhouse, haymaker)
- Whip (backfist, snap kick)
- Push (teep, palm strike)

**Grappling:**
- Clinch (entries and control)
- Throw (hip throw, shoulder throw)
- Takedown (double leg, single leg)
- Sweep/Trip (off-balancing)
- Lock (armbars, kimuras)
- Choke (rear naked, guillotine)

**Defensive:**
- Displacement (footwork, pivots)
- Evade (slips, rolls)
- Block (parries, checks)
- Counter (counter strikes)

**Tactical:**
- Feint (deceptive movements)
- Trap (limb trapping and control)

## Current Move Database

Initial moves included:
- **Jab** (Boxing) - lead hand straight
- **Cross** (Boxing/Karate) - rear hand power
- **Roundhouse Kick** (Muay Thai/Karate/TKD) - circular kick
- **Teep** (Muay Thai) - front push kick
- **Clinch Entry** (Muay Thai/Wrestling) - close distance
- **Hip Throw** (Judo) - leverage throw
- **Step Back** (Universal) - create distance

*More moves will be added incrementally*

## Database Schema

### states
Stores all unique fight positions
- `state_hash`: Unique identifier
- `state_json`: Full serialized state
- `sequence_length`: How many moves into fight
- `is_terminal`: Boolean flag
- `seen_count`: How often this state occurred

### unknown_states
Logs positions with no legal moves
- `state_hash`: Reference to state
- `text_repr`: Human-readable description
- `timestamp`: When discovered
- `resolved`: Boolean flag for human review
- `notes`: Context and resolution notes

### state_transitions
Records move applications
- `from_hash` → `to_hash`
- `move_id`: Which move was used
- `who`: Which fighter (A or B)
- `count`: Frequency of this transition

### terminal_states
Winning/losing positions
- `state_hash`: Reference
- `winner`: FighterA or FighterB
- `win_distance`: Ply count to win (computed via backward search)
- `reason`: Why this is terminal

## Workflow

### Phase 1: Forward Exploration (Current)
1. Run millions of simulations
2. Randomly select legal moves
3. Record all states to database
4. Log unknown states for review
5. Build comprehensive state graph

### Phase 2: Human Correction (Next)
1. Review unknown states
2. Add missing moves or fix prerequisites
3. Mark states as resolved
4. Re-run simulations
5. Iterate until stable

### Phase 3: Backward Propagation (Future)
1. Mark all terminal states with winDistance=0
2. Find parent states (reverse moves)
3. Propagate winDistance+1 to parents
4. Build complete tablebase with win probabilities
5. Prune physically impossible backward transitions

### Phase 4: Style Profiling (Future)
1. Define style profiles (Karate, Muay Thai, Wrestling, etc.)
2. Apply move preference weights
3. Generate style-specific guidance
4. Compare effectiveness across styles
5. Optimize for self-defense scenarios

## Extending the System

### Adding New Moves

```nim
proc createNewMove(): Move =
  result = Move(
    id: "unique_id",
    name: "Move Name (Origin)",
    category: Straight,
    energyCost: 0.15,
    reach: 0.8,
    height: High,
    # ... other fields

    prerequisites: proc(state: FightState, who: FighterID): bool =
      let fighter = if who == FighterA: state.a else: state.b
      # Your constraint checks here
      checkBasicPrerequisites(state, who, result) and
      fighter.leftArm.free,

    apply: proc(state: var FightState, who: FighterID) =
      var attacker = if who == FighterA: addr state.a else: addr state.b
      var defender = if who == FighterA: addr state.b else: addr state.a
      # Your state modifications here
      applyFatigue(attacker[], 0.15)
      # ...
  )

# Register it
registerMove(createNewMove())
```

### Adding New Constraints

Edit `constraints.nim` to add domain-specific checks:

```nim
proc canDoSomething*(fighter: Fighter): bool =
  fighter.someCondition and fighter.someOtherCondition

# Use in move prerequisites
if not canDoSomething(fighter): return false
```

## Design Philosophy

1. **Biomechanics over aesthetics** - States represent physical reality, not visual appeal
2. **Constraints prune complexity** - Physics naturally limits options
3. **Fatigue prevents Hollywood sequences** - Energy economy keeps fights realistic
4. **Unknown states are features** - They guide system improvement
5. **Forward maps, backward evaluates** - Exploration before optimization
6. **Multi-art synthesis** - No style bias, only biomechanical truth
7. **Data over tradition** - Simulation reveals what actually works

## Roadmap

- [x] Core type system
- [x] Constraint framework
- [x] Move database
- [x] Forward simulator
- [x] State storage (SQLite)
- [x] Unknown state logging
- [x] Text representation
- [x] Batch simulation
- [ ] Visualization layer (stick figures)
- [ ] Backward propagation engine
- [ ] Win distance computation
- [ ] Style profile system
- [ ] Move library expansion (100+ techniques)
- [ ] Multi-threaded simulation
- [ ] Analysis tools (heatmaps, charts)
- [ ] Interactive state explorer
- [ ] Human correction interface

## Research Applications

- **Self-defense optimization** - Find highest-percentage sequences
- **Martial arts curriculum design** - Identify core vs. peripheral techniques
- **Style comparison** - Objective effectiveness analysis
- **Fight analysis** - Position evaluation like chess engines
- **Training systems** - Generate drilling sequences
- **Intuition building** - Pattern recognition from tablebase

## Contributing

Contributions welcome, especially:
- New move definitions from various martial arts
- Constraint refinements
- Terminal state detection improvements
- Visualization tools
- Analysis scripts

## License

MIT

## References

Based on research conversation exploring chess-like decision trees applied to martial arts, combining forward simulation with backward propagation to build a comprehensive fighting tablebase.
