# Game Tree Generator - Usage Guide

## Overview

The Game Tree Generator creates a chess-style tablebase for martial arts combat. It systematically explores all possible fight positions from an initial state, tracking which moves lead to winning positions. This allows analysis of thousands of generated fights to discover effective techniques and underlying martial arts principles.

## Core Concepts

### State Space Architecture

**Position State (in tree)**:
- 3D position, facing, stance, balance
- Posture level (standing, crouched, grounded, jumping, spinning)
- Limb positions (free/extended, angles)
- Momentum (linear, rotational)
- Biomechanical state (hip/torso rotation, weight distribution)

**Path Metadata (overlays)**:
- Accumulated damage per fighter
- Vulnerability hits along the path
- Critical hits (liver, jaw, temples)

This separation keeps the tree finite (same position = same node) while allowing realistic fight outcomes based on damage accumulated along different paths.

### Move Number Tracking

Each state records its `move_number` from the initial position:
- `move_number = 0`: Initial state
- `move_number = 1`: After first move
- `move_number = 2`: After second move
- etc.

This enables level-based (breadth-first) tree expansion.

## Basic Usage

### 1. Import and Initialize

```nim
import game_tree
import moves

# Initialize move registry
initializeMoves()

# Open/create database
let gtdb = openGameTreeDB("fight_tree.db")
defer: gtdb.close()
```

### 2. Generate the Tree

```nim
# Generate tree with batch expansion
let stats = gtdb.generateGameTree(
  batchSize = 100,      # Expand 100 leaf states per iteration
  maxIterations = 10000 # Maximum iterations
)

echo "Generated ", stats.totalStates, " unique states"
echo "Terminal states: ", stats.terminalStates
echo "Player1 wins: ", stats.player1Wins
echo "Player2 wins: ", stats.player2Wins
```

### 3. Expand Specific Levels

For more control, expand by level:

```nim
# Expand only states at move_number = 5
let query = sql"""
  SELECT state_hash, state_json, last_mover, sequence_length, move_number
  FROM states
  WHERE move_number = 5
    AND has_children = 0
    AND is_terminal = 0
  LIMIT 100
"""

# Then manually process each state...
```

## Database Schema

### States Table

```sql
CREATE TABLE states (
  state_hash TEXT PRIMARY KEY,           -- Unique position hash
  state_json TEXT NOT NULL,              -- Full state as JSON
  sequence_length INTEGER,               -- Total moves so far
  move_number INTEGER,                   -- Depth level (0, 1, 2, ...)
  last_mover TEXT,                       -- "Player1", "Player2", or NULL
  is_terminal INTEGER,                   -- 1 if game over
  terminal_reason TEXT,                  -- Why terminal (no_moves, damage, etc)
  winner TEXT,                           -- "Player1", "Player2", or NULL
  first_seen INTEGER,                    -- Unix timestamp
  has_children INTEGER DEFAULT 0         -- 1 if already expanded
)
```

### State Transitions Table

```sql
CREATE TABLE state_transitions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  from_hash TEXT NOT NULL,               -- Parent state
  to_hash TEXT NOT NULL,                 -- Child state
  move_id TEXT NOT NULL,                 -- Move that was applied
  mover TEXT NOT NULL,                   -- Who moved ("Player1"/"Player2")
  vulnerabilities_hit TEXT,              -- JSON array of zones hit
  damage_dealt REAL,                     -- Damage in this transition
  force_applied REAL,                    -- Force of strike (Newtons)
  hit_success INTEGER                    -- 1 if hit landed, 0 if missed
)
```

### Path Damage Table

```sql
CREATE TABLE path_damage (
  state_hash TEXT NOT NULL,
  from_hash TEXT NOT NULL,
  cumulative_damage_p1 REAL,             -- Total damage to Player1
  cumulative_damage_p2 REAL,             -- Total damage to Player2
  hit_count_p1 INTEGER,
  hit_count_p2 INTEGER,
  critical_hits TEXT,                    -- JSON of critical hits
  PRIMARY KEY (state_hash, from_hash)
)
```

## Querying the Tree

### Find All Positions at Depth 5

```sql
SELECT state_hash, state_json, winner
FROM states
WHERE move_number = 5
  AND is_terminal = 0
ORDER BY sequence_length;
```

### Find Winning Moves from a Position

```sql
-- From state X, which moves lead to Player1 winning?
SELECT
  t.move_id,
  t.to_hash,
  s.winner,
  s.terminal_reason
FROM state_transitions t
JOIN states s ON t.to_hash = s.state_hash
WHERE t.from_hash = 'state_hash_here'
  AND t.mover = 'Player1'
  AND s.winner = 'Player1';
```

### Find Most Common Terminal Reasons

```sql
SELECT terminal_reason, COUNT(*) as count
FROM states
WHERE is_terminal = 1
GROUP BY terminal_reason
ORDER BY count DESC;
```

### Analyze Damage Patterns

```sql
-- What's the average damage when Player1 wins?
SELECT
  AVG(pd.cumulative_damage_p2) as avg_damage_to_loser,
  AVG(pd.cumulative_damage_p1) as avg_damage_to_winner
FROM path_damage pd
JOIN states s ON pd.state_hash = s.state_hash
WHERE s.winner = 'Player1'
  AND s.is_terminal = 1;
```

### Find Effective Move Sequences

```sql
-- Which moves lead to the quickest wins?
SELECT
  t1.move_id as first_move,
  t2.move_id as second_move,
  s.sequence_length,
  s.winner
FROM state_transitions t1
JOIN state_transitions t2 ON t1.to_hash = t2.from_hash
JOIN states s ON t2.to_hash = s.state_hash
WHERE s.is_terminal = 1
  AND s.winner = 'Player1'
  AND s.sequence_length <= 5
ORDER BY s.sequence_length;
```

## Terminal Conditions

A fight ends when:

### Position-Based
- **Balance collapse**: Balance < 0.2 (falling)
- **No moves**: Fighter has no viable moves (trapped)

### Damage-Based
- **Cumulative damage**: Total damage > 0.8
- **Critical hits**: Liver/jaw/temples hit with sufficient force
  - Liver: > 800N
  - Jaw: > 900N
  - Temples: > 700N

### Length-Based
- **Stalemate**: 200 moves without conclusion (draw)

## Analysis Workflow

### 1. Generate Small Tree

```nim
# Start with limited depth to verify moves are reasonable
let stats = gtdb.generateGameTree(
  batchSize = 50,
  maxIterations = 100  # Only 100 iterations
)
```

### 2. Export Sample States

```nim
# Look at states at depth 3
let rows = gtdb.db.getAllRows(sql"""
  SELECT state_hash, state_json
  FROM states
  WHERE move_number = 3
  LIMIT 10
""")

for row in rows:
  let state = fromJson(parseJson(row[1]), FightState)
  echo toTextRepr(state)  # Human-readable output
```

### 3. Validate Move Realism

Check if the generated moves make sense:
- Do fighters in plCrouched have appropriate move options?
- Are momentum-based overcommitments realistic?
- Do posture transitions happen correctly?

### 4. Analyze Patterns

```sql
-- Which postures appear most in winning positions?
SELECT
  json_extract(state_json, '$.a.posture') as posture,
  COUNT(*) as count
FROM states
WHERE winner = 'Player1'
  AND is_terminal = 1
GROUP BY posture;
```

### 5. Extract Principles

Look for patterns like:
- "Crouched posture → takedown → ground control → win"
- "High momentum spinning attacks → overcommit → loss if missed"
- "Push kicks at medium distance → knock down → advantageous position"

## Performance Considerations

### Batch Size
- **Small (50-100)**: Better for debugging, frequent progress updates
- **Large (500-1000)**: Faster generation, less frequent updates

### Depth Limits
- **Early game (moves 0-5)**: Huge branching factor
- **Mid game (moves 6-15)**: Most interesting tactical positions
- **Late game (moves 16+)**: Many terminal states, less branching

### Database Size
- ~1KB per state (JSON)
- 10,000 states ≈ 10MB
- 100,000 states ≈ 100MB
- 1,000,000 states ≈ 1GB

Expect exponential growth in early moves, then tapering as terminal states accumulate.

## Advanced: Retrograde Analysis

Once the tree is complete, analyze backward from terminal states:

```sql
-- Mark all states that lead to Player1 win
WITH RECURSIVE winning_positions AS (
  -- Base: terminal winning states
  SELECT state_hash, 0 as distance_to_win
  FROM states
  WHERE winner = 'Player1' AND is_terminal = 1

  UNION

  -- Recursive: states that can reach winning states
  SELECT t.from_hash, wp.distance_to_win + 1
  FROM state_transitions t
  JOIN winning_positions wp ON t.to_hash = wp.state_hash
  WHERE t.mover = 'Player1'
)
SELECT * FROM winning_positions;
```

## Example: Complete Analysis Session

```nim
import game_tree, moves, state_storage
import std/[db_sqlite, json, strformat]

proc analyzeTree(dbPath: string) =
  let gtdb = openGameTreeDB(dbPath)
  defer: gtdb.close()

  # 1. Generate tree
  echo "Generating game tree..."
  let stats = gtdb.generateGameTree(batchSize = 100, maxIterations = 1000)

  echo fmt"""
Tree Statistics:
  Total states: {stats.totalStates}
  Terminal states: {stats.terminalStates}
  Player1 wins: {stats.player1Wins}
  Player2 wins: {stats.player2Wins}
  Draws: {stats.draws}
  Max depth: {stats.maxDepth}
  Avg game length: {stats.avgGameLength:.2f}
"""

  # 2. Find most effective opening moves
  echo "\nMost effective opening moves:"
  for row in gtdb.db.fastRows(sql"""
    SELECT
      t.move_id,
      COUNT(*) as usage,
      SUM(CASE WHEN s.winner = 'Player1' THEN 1 ELSE 0 END) as wins
    FROM state_transitions t
    JOIN states s ON t.to_hash = s.state_hash
    WHERE t.mover = 'Player1'
      AND EXISTS (
        SELECT 1 FROM states parent
        WHERE parent.state_hash = t.from_hash
        AND parent.move_number = 0
      )
    GROUP BY t.move_id
    ORDER BY wins DESC
    LIMIT 5
  """):
    echo fmt"  {row[0]}: {row[2]} wins / {row[1]} uses"

  # 3. Analyze posture effectiveness
  echo "\nPosture analysis for winners:"
  for row in gtdb.db.fastRows(sql"""
    SELECT
      json_extract(state_json, '$.a.posture') as final_posture,
      COUNT(*) as count
    FROM states
    WHERE winner = 'Player1' AND is_terminal = 1
    GROUP BY final_posture
    ORDER BY count DESC
  """):
    echo fmt"  {row[0]}: {row[1]} wins"

analyzeTree("fight_tree.db")
```

## Troubleshooting

### Tree Not Expanding
- Check if initial state was inserted: `SELECT * FROM states WHERE move_number = 0`
- Verify moves are registered: `echo ALL_MOVES.len`
- Check for terminal states blocking expansion: `SELECT COUNT(*) FROM states WHERE has_children = 0 AND is_terminal = 1`

### Too Many Duplicate States
- Verify state hashing includes all relevant fields
- Check if posture/momentum are being updated correctly

### Unrealistic Moves Generated
- Review move prerequisites in `moves.nim`
- Check posture-dependent effectiveness multipliers
- Adjust move commitment levels and overcommitment thresholds

## Next Steps

1. **Generate small tree** (100-1000 states) and manually inspect positions
2. **Validate move sequences** for realism
3. **Iterate on move definitions** based on findings
4. **Scale up** once confident in move realism
5. **Perform statistical analysis** to extract principles

The key insight should emerge from patterns: certain sequences, postures, or strategies that consistently lead to favorable positions.
