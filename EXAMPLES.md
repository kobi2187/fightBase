## FightBase Usage Examples

This document shows real examples of using the FightBase system.

## Example 1: Single Test Fight

### Command
```bash
./fightBase test --verbose
```

### Expected Output

```
Initializing move database...
Registered 8 moves

Running interactive test fight...

=== Starting fight simulation ===
A[fat:0.00 dmg:0.00 bal:1.00] <-Medium-> B[fat:0.00 dmg:0.00 bal:1.00]

[0] A uses left Jab (Boxing)
[1] B uses Cross (Boxing/Karate)
[2] A uses Step Back
  [10] A[fat:0.35 dmg:0.15 bal:0.82] <-Long-> B[fat:0.42 dmg:0.10 bal:0.78]

[11] B uses Teep (Muay Thai)
[12] A uses left Jab (Boxing)
[13] B uses Step Back
  [20] A[fat:0.62 dmg:0.25 bal:0.75] <-Medium-> B[fat:0.68 dmg:0.18 bal:0.72]

... continues ...

=== Fight ended ===
Moves: 47 | Reason: Terminal: A wins
Winner: A

Distance: Medium | Seq: 47
  B unstable | both stable | no control
  A has 4/4 limbs free | B has 4/4 limbs free
```

## Example 2: Batch Simulation

### Command
```bash
./fightBase batch 5000 --max 150 --db simulation_001.db
```

### Expected Output

```
Initializing move database...
Registered 8 moves

=== Running 5000 fight simulations ===
Config: maxLength=150, recordAll=true

[100/5000] States: 1247, Unknown: 3, Terminal: 12
[200/5000] States: 2891, Unknown: 7, Terminal: 31
[300/5000] States: 4223, Unknown: 12, Terminal: 54
...
[5000/5000] States: 48392, Unknown: 127, Terminal: 876

=== Batch simulation complete ===

State Database Statistics:
  Total unique states: 48392
  Unresolved unknown states: 127
  Terminal states: 876
  Recorded transitions: 234821

Batch Results:
  Completed: 5000
  Reached unknown states: 127
  Reached terminal states: 876
  Unknown rate: 2.5%
  Terminal rate: 17.5%
```

### Interpretation

- **48,392 unique states**: Good variety, system is exploring well
- **127 unknown states**: Need human review (2.5% encounter rate)
- **876 terminal states**: 17.5% of fights ended decisively
- **Remaining 82.5%**: Hit max length (150 moves) - may need more decisive moves

## Example 3: Viewing Statistics

### Command
```bash
./fightBase stats --db simulation_001.db
```

### Output

```
State Database Statistics:
  Total unique states: 48392
  Unresolved unknown states: 127
  Terminal states: 876
  Recorded transitions: 234821
```

## Example 4: Listing Unknown States

### Command
```bash
./fightBase list --db simulation_001.db
```

### Output

```
Found 20 unresolved unknown states:

[1] ID 15 | Hash: a3f8b2c478de9f1...
======================================================================
FIGHT STATE (Hash: a3f8b2c4...)
Sequence Length: 34 | Distance: Short
======================================================================

Fighter A:
  Position: (-0.80, 0.00, 0.00)
  Facing: 90° | Stance: Orthodox | Balance: 0.52
  Fatigue: 0.68 | Damage: 0.32
  Side: Centerline | Control: None
  Left arm:  ready
  Right arm: ready
  Left leg:  ready
  Right leg: ready

Fighter B:
  Position: (0.80, 0.00, 0.00)
  Facing: 270° | Stance: Southpaw | Balance: 0.48
  Fatigue: 0.72 | Damage: 0.38
  Side: Centerline | Control: None
  Left arm:  extended
  Right arm: ready
  Left leg:  ready
  Right leg: ready

======================================================================

[2] ID 23 | Hash: f7c2a1b5e8d4c9a...
======================================================================
...
```

## Example 5: Exporting Unknown States

### Command
```bash
./fightBase export --db simulation_001.db
```

### Output

```
Exported 127 unknown states to simulation_001.txt
```

### Contents of `simulation_001.txt`

```
================================================================================
UNRESOLVED UNKNOWN STATES
================================================================================

[1] ID: 15 | Hash: a3f8b2c478de9f1...
Timestamp: 1732045823 | Notes: No legal moves for A at move 34

======================================================================
FIGHT STATE (Hash: a3f8b2c4...)
Sequence Length: 34 | Distance: Short
======================================================================

Fighter A:
  Position: (-0.80, 0.00, 0.00)
  Facing: 90° | Stance: Orthodox | Balance: 0.52
  Fatigue: 0.68 | Damage: 0.32
  Side: Centerline | Control: None
  Left arm:  ready
  Right arm: ready
  Left leg:  ready
  Right leg: ready

Fighter B:
  Position: (0.80, 0.00, 0.00)
  Facing: 270° | Stance: Southpaw | Balance: 0.48
  Fatigue: 0.72 | Damage: 0.38
  Side: Centerline | Control: None
  Left arm:  extended
  Right arm: ready
  Left leg:  ready
  Right leg: ready

--------------------------------------------------------------------------------

[2] ID: 23 | Hash: f7c2a1b5e8d4c9a...
...
```

## Example 6: Overnight Large Batch

### Command
```bash
nohup ./fightBase batch 1000000 --max 200 --db large_run.db > large_run.log 2>&1 &
```

### Checking Progress

```bash
# Check log file
tail -f large_run.log

# Check database while running
./fightBase stats --db large_run.db

# Typical overnight run (8 hours, modern CPU):
# 1,000,000 simulations
# 500,000-800,000 unique states
# 1,000-5,000 unknown states
# 50,000-150,000 terminal states
```

## Example 7: Analyzing Fight Patterns

### Using SQLite Directly

```bash
sqlite3 simulation_001.db
```

```sql
-- Most common state sequence lengths
SELECT
  sequence_length,
  COUNT(*) as count,
  AVG(seen_count) as avg_encounters
FROM states
GROUP BY sequence_length
ORDER BY sequence_length;

-- Output:
-- sequence_length | count | avg_encounters
-- 5              | 147   | 142.3
-- 10             | 523   | 78.4
-- 15             | 1247  | 34.2
-- 20             | 2891  | 18.7
-- ...
```

```sql
-- Most used moves
SELECT
  move_id,
  SUM(count) as total_uses
FROM state_transitions
GROUP BY move_id
ORDER BY total_uses DESC
LIMIT 10;

-- Output:
-- move_id            | total_uses
-- jab_left_boxing   | 23841
-- step_back         | 18923
-- cross_right       | 15234
-- teep_front        | 8734
-- roundhouse_right  | 7621
-- ...
```

```sql
-- Terminal state winners
SELECT
  winner,
  COUNT(*) as wins
FROM terminal_states
GROUP BY winner;

-- Output:
-- winner | wins
-- A      | 451
-- B      | 425
```

```sql
-- States by distance
SELECT
  json_extract(state_json, '$.distance') as distance,
  COUNT(*) as count,
  AVG(json_extract(state_json, '$.sequenceLength')) as avg_move_num
FROM states
GROUP BY distance;

-- Output:
-- distance  | count  | avg_move_num
-- Medium    | 18234  | 15.3
-- Short     | 12847  | 23.8
-- Long      | 9821   | 12.1
-- Contact   | 4782   | 31.4
-- VeryLong  | 2708   | 8.7
```

## Example 8: Comparing Database Runs

### Run 1: Basic Moves Only
```bash
./fightBase batch 10000 --db run1_basic.db
```
Result: 35,000 states, 450 unknown (12.9%), 1200 terminal (12%)

### Run 2: After Adding 10 New Moves
```bash
./fightBase batch 10000 --db run2_expanded.db
```
Result: 82,000 states, 180 unknown (2.2%), 2400 terminal (24%)

**Analysis**: More moves → more state variety, fewer unknowns (better coverage), more terminal states (more decisive techniques).

## Example 9: Tracking Move Effectiveness

### Custom Analysis Script

```nim
# analyze_moves.nim
import db_sqlite, strformat, tables, strutils

let db = open("simulation_001.db", "", "", "")

type MoveStats = object
  uses: int
  leadsToTerminal: int
  avgFatigueCost: float

var stats = initTable[string, MoveStats]()

# Query transitions
for row in db.fastRows(sql"""
  SELECT
    st.move_id,
    COUNT(*) as uses,
    SUM(CASE WHEN s.is_terminal = 1 THEN 1 ELSE 0 END) as terminals
  FROM state_transitions st
  LEFT JOIN states s ON st.to_hash = s.state_hash
  GROUP BY st.move_id
"""):
  let moveId = row[0]
  stats[moveId] = MoveStats(
    uses: parseInt(row[1]),
    leadsToTerminal: parseInt(row[2])
  )

echo "Move Effectiveness Report"
echo "=" .repeat(60)

for moveId, stat in stats:
  let termRate = (stat.leadsToTerminal.float / stat.uses.float) * 100.0
  echo fmt"{moveId:25} Uses: {stat.uses:6}  Terminal: {termRate:5.1f}%"
```

### Output

```
Move Effectiveness Report
============================================================
jab_left_boxing           Uses:  23841  Terminal:   3.2%
step_back                 Uses:  18923  Terminal:   0.8%
cross_right               Uses:  15234  Terminal:   8.1%
teep_front                Uses:   8734  Terminal:   2.1%
roundhouse_right          Uses:   7621  Terminal:  14.3%
clinch_entry              Uses:   5234  Terminal:   5.7%
throw_hip                 Uses:   2847  Terminal:  42.8%
```

**Insights**:
- Jab used most but low finishing rate (setup move)
- Roundhouse kick moderate use, decent finishing
- Hip throw rare but very effective when possible (42.8% terminal rate)

## Example 10: Simulating Style Matchups (Future)

Once style profiles are implemented:

```bash
# Karate vs Muay Thai
./fightBase matchup --style-a karate --style-b muay_thai --runs 10000

# Output:
# Karate wins: 4,234 (42.3%)
# Muay Thai wins: 5,124 (51.2%)
# Draws: 642 (6.4%)
#
# Key patterns:
# - Muay Thai clinch entries: 3,821 successful
# - Karate counter kicks: 2,947 successful
# - Average fight length: 38 moves
```

## Workflow Summary

### Typical Research Cycle

1. **Initial run**: `batch 10000` with basic moves
2. **Review**: `stats` and `list` to find patterns
3. **Export**: `export` for detailed analysis
4. **Add moves**: Based on unknown states
5. **Re-run**: `batch 50000` with expanded move set
6. **Analyze**: SQLite queries for patterns
7. **Iterate**: Repeat until stable (few unknowns)

### Production Run

Once stable:
```bash
./fightBase batch 1000000 --max 200 --db production.db
```

Expected:
- 1-2M unique states
- < 0.5% unknown rate
- 30-50% terminal rate
- 5-10M transitions
- Database size: 1-2 GB

This becomes your martial arts tablebase for analysis, visualization, and curriculum design.
