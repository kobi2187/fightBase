# Martial Arts Simulation Engine – Full Design Document

## 1. Overview
This document outlines a complete design for a martial‑arts decision and simulation engine. The goal is to model realistic combat exchanges, simulate millions of fights, build an ever-expanding state graph, and eventually create a “martial arts tablebase” similar to endgame tablebases in chess. The system supports forward simulation, backward reasoning, human correction for unknown states, and optional visualization.

---

## 2. Core Architecture
The engine consists of:
- **State model** representing fighters, positions, limbs, fatigue, damage, orientation, balance, and distance.
- **Global move database** with actions that define prerequisites and effects.
- **Forward simulator** that explores possible sequences.
- **Unknown state handler** that halts sim and requests user input.
- **State storage** and hashing for fast comparison and deduplication.
- **Backward propagation engine** to compute win distances.
- **Optional visualization layer** for verifying physics.

---

## 3. State Specification
### FightState
```
type
  Position3D = object
    x, y, z: float
    facing: float
    stance: StanceKind
    balance: float

  LimbStatus = object
    free: bool
    extended: bool
    damaged: float
    angle: float

  Fighter = object
    pos: Position3D
    leftArm, rightArm: LimbStatus
    leftLeg, rightLeg: LimbStatus
    fatigue: float
    damage: float
    liveSide: SideKind
    control: ControlKind

  FightState = object
    A, B: Fighter
    distance: float
    sequenceLength: int
    terminal: bool
    winner: Option[FighterID]
```
This state is compact but expressive enough to describe most realistic fighting positions.

---

## 4. Move Representation
```
type
  Move = object
    name: string
    energy: float
    prerequisites: proc(state: FightState): bool
    apply: proc(state: var FightState)
    lethalPotential: float
    positionShift: PositionDelta
```
Moves are stateless objects driven by the global move list:
```
var ALL_MOVES: seq[Move]
```

---

## 5. Legal Move Filtering
A move is legal only if `prerequisites` returns true. This automatically resolves constraints like:
- Distance too large/small
- Incorrect side of opponent
- Fatigue threshold
- Limb free/busy
- Balance low/high
- Grappling control state

```
proc legalMoves(s: FightState, who: FighterID): seq[Move] =
  for m in ALL_MOVES:
    if m.prerequisites(s):
      result.add(m)
```

---

## 6. Terminal Conditions (Winning States)
A fight is over if:
- Opponent is immobilized
- Joint lock is fully secured
- Massive balance failure (fall)
- Takedown with dominant control
- Opponent unconscious
- Opponent has zero legal moves

```
proc evaluateTermination(s: FightState): Option[FighterID]
```

---

## 7. Fatigue and Damage Economy
Fatigue accumulates per move and restricts options over time.
Damage limits available moves and acts as another pruning mechanism.
Missed strikes cost more energy due to recovery.

This prevents unrealistic infinite combinations.

---

## 8. Forward Simulation Engine
Forward simulation:
- Randomly selects legal moves
- Applies fatigue/damage calculations
- Stores new states via hashing
- Limits sequences to a cap (e.g., 200 steps)
- Halts and requests human input when encountering unknown states

### Unknown State Callback
If a state has no legal moves:
- Engine pauses
- Displays visualization (optional)
- Asks the user to list valid moves
- Updates move prerequisites or adds a custom move

This gradually fills the system with realistic data.

---

## 9. State Hashing and Storage
Every FightState is hashed and stored.
```
stateHash = hash(FightState)
```
Serialized storage example:
```
{ stateHash: "...", legalMoves: ["jab", "pivot"], outcomes: [...] }
```
Over time this becomes a full library of reachable positions.

---

## 10. Backward Search (Win Distance Propagation)
Once enough states are mapped from forward simulation, a backward search assigns values:
- Terminal states = winDistance 0
- Their parents = winDistance 1
- Grandparents = winDistance 2
- And so on

Backward search cleans up:
- Impossible parent transitions
- States where fatigue/damage magically improve
- Physically inconsistent angles/distances

This produces:
```
(winProbability, winDistance)
```
for every known state.

---

## 11. Hybrid Method: Forward + Backward
The final engine works like this:
1. Forward simulation maps the continent of reachable states.
2. Unknown states are filled via human correction.
3. Backward propagation computes truth values.
4. Forward simulator uses these values to bias move selection toward high-percentage lines.

---

## 12. Visualization Layer (Optional but Powerful)
A simple stick-figure or low-poly view:
- Ensures states look physically valid
- Helps humans fill missing transitions
- Builds intuitive understanding for training

Visualization is not required for the engine, but greatly helpful.

---

## 13. Full Data Flow
1. **Start with empty move list + a few basics.**
2. **Run forward simulation.**
3. **Engine halts on unknown states.**
4. **User defines the missing transitions.**
5. **State database grows.**
6. **Once enough terminal states exist, run backward search.**
7. **Assign win probabilities and win distances.**
8. **Store everything.**
9. **Rerun sim using new knowledge.**
10. **Iterate until stable.**

---

## 14. End Result: A Martial Arts Tablebase
After enough cycles you will have:
- Realistic reachable states
- Human-verified transitions
- Machine-discovered transitions
- Backward-derived win distances
- Probability maps over possible branches
- An engine that can evaluate a fight "position"

This system becomes a powerful research tool for:
- Self-defense strategy design
- Martial arts curriculum refinement
- Fight analysis and training
- Automated sequence generation

---

## 15. Next Steps
Further documents can define:
- Move templates for striking, grappling, throws
- Fatigue/damage modeling formulas
- Serialization formats
- Visualization code
- Hashing strategies
- Multi-threaded simulation

End of document.


---

## 16. Multi‑Art Move Integration Layer
### Goal
Include a very wide variety of striking, grappling, and off‑balancing techniques drawn from global martial arts traditions, while keeping the physics model unified and style‑agnostic.

### Approach
1. **Canonical Move Categories** — Normalize all techniques into core biomechanical classes: `straight`, `arc`, `whip`, `push`, `pull`, `sweep`, `trip`, `throw`, `takedown`, `clinch`, `lock`, `choke`, `displacement`, `feint`, `trap`, `followup`.
2. **Flavor Variants** — Store each named technique (e.g., `gyaku-zuki`, `rear cross`, `roundhouse`, `teep`, `sode-tsurikomi-goshi`) as a *flavor* of a canonical category with parameters:
   - reach, height, preferred angle
   - typical energy cost
   - typical recovery time
   - favored followups / probable transitions
3. **Move Normalization** — Every technique added is normalized to the canonical representation; the engine reasons about categories and parameters rather than art‑specific names.
4. **Extensibility** — New moves can be added with minimal effort by specifying parameters and the canonical class.

### Database Schema (conceptual)
```
MoveEntry:
  id: string
  name: string
  canonicalClass: string
  reach: float
  height: enum (low, mid, high)
  angleBias: float # degrees relative to centerline
  energyCost: float
  recoveryRange: (min,max)
  typicalSuccessRate: float (seeded or null)
  followups: seq[string] # ids of likely next moves
  styleOrigins: seq[string]
```

---

## 17. Style Profiles and Biasing Mechanism
### Profile Structure
```
StyleProfile:
  id: string
  name: string
  moveWeights: map[string,float] # per MoveEntry.id
  categoryBias: map[string,float] # per canonicalClass
  distanceBias: map[string,float] # e.g., {"clinch":+0.3, "long":-0.2}
  riskTolerance: float # -1..+1, negative avoids high-variance moves
  adaptability: float # 0..1 probability to override preference when meta-data suggests
```

### Applying a Profile
- When generating move score at a node:
  - baseScore = objectiveScore(state, move)
  - profileMultiplier = 1 + moveWeights[move.id] + categoryBias[move.canonicalClass] + distanceBias[currentDistance]
  - finalScore = baseScore * clamp(profileMultiplier, 0.1, 3.0)
- `adaptability` allows the engine to occasionally ignore the profile if `finalScore` < threshold and an objectively much better move exists.

---

## 18. Move Normalization Across Martial Systems
### Why
To compare styles and enable the engine to reason with a finite set of biomechanical primitives.

### Process
1. Author submits named move + parameters.
2. Normalizer assigns canonical class & computes parameter vector.
3. The move is inserted into `ALL_MOVES` with both raw name and normalized fields.

This preserves provenance (which art the technique came from) while keeping decision logic compact.

---

## 19. Statistical Analysis & Reporting
### Outputs
- Win probability heatmaps by state
- Move effectiveness ranked per canonical class and per named move
- Style comparison reports (win rates, average winDistance, fatigue efficiency)
- Confusion matrix of transitions (what move most commonly follows X)

### Tools
- Export to CSV / Parquet
- Use Python (pandas, networkx) or Nim bindings for analysis
- Visualization via D3.js or matplotlib for static reporting

---

## 20. Style‑Profile Overlay: Runtime Guide
### Runtime Flow
1. Load core fight tree + ALL_MOVES.
2. Load selected StyleProfile into fighter A and optionally fighter B.
3. At each decision node compute weighted scores using profile multipliers.
4. Choose move via: softmax(finalScores / temperature) or argmax for deterministic guidance.
5. Log chosen line and present as human‑readable guidance: "Against KarateProfile, prefer X into Y when distance=short."

### Temporary Memory
- Profile multipliers are not saved into the core tree; they exist only in a runtime overlay to enable comparative drills (e.g., "what if I fight like Muay Thai?").

---

## 21. Detailed Implementation Plan (Nim‑centric)
### Milestones (high level)
1. **M1 — Core Types & Move Registry**
   - Implement `FightState`, `Fighter`, `LimbStatus`, `Move` types in Nim
   - Implement serialization (compact binary + JSON) and hashing for states
   - Implement ADD/LOAD APIs for moves
2. **M2 — Simple Forward Simulator**
   - Implement `legalMoves` filter using move prerequisites
   - Implement stochastic policy (random + fatigue heuristics)
   - State store + deduplication (hash table)
   - Unknown‑state callback that emits a human‑friendly summary
3. **M3 — Batch Simulation & Storage**
   - Run multi‑threaded simulations, produce serialized state DB
   - Implement efficient storage (LMDB or sqlite with blobs) + export to CSV
4. **M4 — Backward Propagation Engine**
   - Implement predecessor generation (reverse moves) with pruning rules
   - Implement winDistance propagation and winProbability estimation
5. **M5 — Move Normalizer & Style Profiles**
   - Implement canonical classes, normalizer utilities, and profile application code
6. **M6 — Visualization & Sanity UI**
   - Minimal 3D stick‑figure visualizer (WebGL or simple 2D) for quick checks
   - Unknown state inspector UI
7. **M7 — Analysis & Reports**
   - Implement analysis pipelines: aggregate statistics, style comparisons, CSV output
8. **M8 — Iteration & Expansion**
   - Add broad move library, integrate community contributed moves, harden heuristics

### Data Structures & Storage
- **State hashing**: SHA256 over a canonical binary encoding of FightState (ensure deterministic layout)
- **State DB**: use sqlite for portability; store (stateHash TEXT PRIMARY KEY, state BLOB, legalMoves JSON, metadata JSON)
- **Move registry**: JSON file + in‑memory map `HashTable[string, Move]`

### Concurrency & Performance
- Simulation workers (Nim threads / threadpools) pull seeds from a job queue
- Use lockless queues for state insertion, batch commits to DB
- Use memory LRU cache for frequent states to avoid DB hits

### Unknown State Handling
- When `legalMoves` returns empty, serialize state to `unknown_states` table and notify operator
- Create a CLI tool to load unknown states and interactively add legal moves (textual or via visualizer)

### Backward Search Implementation
- Keep `parents` mapping: for each stateHash, store `parents: seq[stateHash]` incrementally
- BFS from terminal states to propagate `winDistance` (use integer distances)
- Use fatigue/damage pruning: if a parent would imply negative fatigue, reject it

### APIs
- CLI: `simulate --runs N --threads T`, `inspect --state <hash>`, `fill --state <hash> --add-move <move-id>`
- HTTP: lightweight server to request state details and view visualizer snapshots

### Testing & Validation
- Unit tests for move prerequisites, application, and hash determinism
- Property tests: randomize small move sets and assert no cycles beyond reasonable depth
- Use a small seeded dataset to validate backward propagation correctness

---

## 22. Practical Next Steps (developer tasks)
1. Create Nim repo skeleton with modules: `state`, `moves`, `sim`, `storage`, `analysis`, `ui`.
2. Implement persisted move registry format and sample move set (20 basic moves).
3. Implement simple simulator with unknown‑state logging.
4. Run 100k simulations to gather initial state DB and iterate.
5. Implement backward propagation after enough terminal states exist.
6. Build visualizer for human corrections.

---

## 23. Closing Notes
This extended spec now covers multi‑art integration, style profiles, normalization, analysis, overlays, and a Nim‑oriented implementation plan with milestones and practical developer tasks. It’s deliberately modular: you can stop after M2 and still get useful results, or push through to M8 for a comprehensive tablebase.

When you’re ready I can:
