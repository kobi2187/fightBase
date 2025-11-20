# Overlay Architecture - Separating Position from Runtime State

## Problem: Tree Bloat

**Original approach:**
```nim
# Fighter has fatigue and damage as part of state
Fighter:
  stance, balance, fatigue, damage, ...

# Hash includes fatigue/damage
hash(fighter) = hash(stance + balance + fatigue + damage + ...)
```

**Result:** Tree explosion!
- Jab at 0% fatigue = different node
- Jab at 5% fatigue = different node
- Jab at 10% fatigue = different node
- ...100+ nodes for the same POSITION!

## Solution: Overlays

**New approach:**
```nim
# Fighter contains ONLY position state
Fighter:
  stance, balance, biomechanics, momentum, limb positions
  # NO fatigue, NO damage

# Overlays contain runtime modifiers
RuntimeOverlay:
  fatigue, damage, per-limb damage

# Hash ONLY includes position
hash(fighter) = hash(stance + balance + biomech + momentum + limbs)
```

**Result:** Compact tree!
- Jab from orthodox stance = ONE node
- Fatigue/damage applied as filters at runtime
- Tree represents pure positional chess, overlays represent fighter condition

## Architecture

### 1. Position State (Tree)

What goes in the **tablebase tree**:

```nim
Fighter = object
  pos: Position3D              # stance, balance, facing
  leftArm, rightArm: LimbPosition  # free, extended, angle (NOT damage)
  leftLeg, rightLeg: LimbPosition
  liveSide: SideKind          # which side of opponent
  control: ControlKind        # grappling control
  momentum: Momentum          # physical momentum
  biomech: BiomechanicalState # hip/torso rotation, weight distribution

FightState = object
  a, b: Fighter
  distance: DistanceKind
```

**Hash only includes these fields** - no overlays!

### 2. Runtime Overlays (Filters)

What gets applied **during actual fights**:

```nim
RuntimeOverlay = object
  fatigue: float              # 0.0 (fresh) to 1.0 (exhausted)
  damage: float               # 0.0 (unhurt) to 1.0 (incapacitated)
  leftArmDamage: float        # per-limb damage
  rightArmDamage: float
  leftLegDamage: float
  rightLegDamage: float

RuntimeFightState = object
  position: FightState        # The tree position
  overlayA: RuntimeOverlay    # Fighter A condition
  overlayB: RuntimeOverlay    # Fighter B condition
```

### 3. Move Viability Checks

Moves now have **viability checks** that consider overlays:

```nim
type MoveViabilityCheck* = proc(overlay: RuntimeOverlay, move: Move): float

# Returns effectiveness multiplier:
# 1.0 = full effectiveness
# 0.5 = half effectiveness (fatigued/damaged)
# 0.0 = can't perform (too damaged/exhausted)
```

**Example:**

```nim
proc roundKickViability(overlay: RuntimeOverlay, move: Move): float =
  # Can't perform if leg damaged > 50%
  if overlay.rightLegDamage > 0.5:
    return 0.0

  # Effectiveness reduced by fatigue
  let fatigueMultiplier = 1.0 - (overlay.fatigue * 0.7)

  # Effectiveness reduced by leg damage
  let damageMultiplier = 1.0 - overlay.rightLegDamage

  return fatigueMultiplier * damageMultiplier

# Usage in move definition:
Move(
  name: "Round Kick",
  energyCost: 0.6,
  viabilityCheck: roundKickViability,
  ...
)
```

## Usage Pattern

### Building the Tree

```nim
# Build tree with position states ONLY
proc buildTablebase(): Table[string, TreeNode] =
  var tree = initTable[string, TreeNode]()

  # Start from initial positions
  let startState = FightState(
    a: Fighter(pos: ..., biomech: ..., momentum: ...),  # NO fatigue/damage
    b: Fighter(pos: ..., biomech: ..., momentum: ...),
    distance: Medium
  )

  # Generate all possible moves from position
  let moves = getViableMoves(startState, FighterA)

  # Each move leads to new POSITION (no overlay changes)
  for move in moves:
    var newState = startState
    move.apply(newState, FighterA)

    # Hash is based on position only
    let hash = hash(newState)

    if hash notin tree:
      tree[hash] = expandNode(newState)  # Recursive expansion

  return tree
```

### Using the Tree in a Fight

```nim
# Start with position + overlays
var fight = RuntimeFightState(
  position: lookupPosition(tree, currentStateHash),
  overlayA: RuntimeOverlay(fatigue: 0.0, damage: 0.0, ...),
  overlayB: RuntimeOverlay(fatigue: 0.0, damage: 0.0, ...)
)

# Get moves from tree (position-based)
let positionMoves = tree[hash(fight.position)].moves

# Filter by viability (overlay-based)
var viableMoves: seq[(Move, float)]
for move in positionMoves:
  let effectiveness = move.viabilityCheck(fight.overlayA, move)
  if effectiveness > 0.0:
    viableMoves.add((move, effectiveness))

# Choose move (weighted by effectiveness)
let chosenMove = selectMove(viableMoves)

# Apply move
chosenMove.apply(fight.position, FighterA)  # Updates position
applyDamage(fight.overlayB, chosenMove.damageEffect)  # Updates opponent overlay
applyFatigue(fight.overlayA, chosenMove.energyCost)  # Updates own overlay
```

## Benefits

### 1. Compact Tree
- Orthodox jab = 1 node (not 100+ with different fatigue levels)
- Roundhouse kick = 1 node (not 1000+ with all damage combinations)
- **Tree size reduced by ~100x**

### 2. Reusability
- Same position node used throughout fight
- Jab from orthodox is jab from orthodox, regardless of condition
- Overlays customize viability for specific fighter state

### 3. Clean Separation
- **Tree = positional chess** (stance, biomechanics, momentum)
- **Overlays = fighter condition** (fatigue, damage)
- **Viability = intersection** (can this damaged, fatigued fighter perform this move?)

### 4. Flexible Analysis
- Analyze positions independent of condition
- "From this position, what moves exist?" (tree query)
- "Can this damaged fighter perform those moves?" (overlay filter)
- Compare martial arts styles on pure position (no condition bias)

## Example: Complete Flow

### Position Analysis (Tree)
```nim
# Position: Orthodox stance, medium distance, balanced
let positionHash = "orthodox_medium_balanced_neutral"
let node = tree[positionHash]

echo "Available moves from position:"
for move in node.moves:
  echo "  - ", move.name
# Output:
#   - Jab
#   - Cross
#   - Front Kick
#   - Step Forward
#   - Slip Left
```

### Runtime Filtering (Overlays)
```nim
# Fighter condition: 60% fatigued, 30% damage, right arm damaged
let overlay = RuntimeOverlay(
  fatigue: 0.6,
  damage: 0.3,
  rightArmDamage: 0.5,
  leftArmDamage: 0.1,
  ...
)

echo "Viable moves for this damaged fighter:"
for move in node.moves:
  let effectiveness = move.viabilityCheck(overlay, move)
  if effectiveness > 0.0:
    echo "  - ", move.name, " (", (effectiveness * 100).int, "% effective)"
# Output:
#   - Jab (70% effective) - uses less damaged left arm
#   - Cross (30% effective) - right arm damaged, reduced power
#   - Front Kick (50% effective) - fatigued, harder to execute
#   - Step Forward (90% effective) - low energy, position move
#   - Slip Left (80% effective) - evasion less affected by damage
```

## Migration Notes

### Old Code (with fatigue/damage in state)
```nim
# DON'T DO THIS
var fighter = Fighter(
  stance: Orthodox,
  balance: 0.9,
  fatigue: 0.3,      # ❌ Not in position state
  damage: 0.2,       # ❌ Not in position state
  ...
)
```

### New Code (overlays separated)
```nim
# DO THIS
var position = Fighter(
  pos: Position3D(stance: Orthodox, balance: 0.9, ...),
  biomech: BiomechanicalState(...),
  momentum: Momentum(...),
  leftArm: LimbPosition(free: true, extended: false, ...),
  ...
  # NO fatigue, NO damage
)

var overlay = RuntimeOverlay(
  fatigue: 0.3,
  damage: 0.2,
  leftArmDamage: 0.1,
  ...
)

# Use together
var fight = RuntimeFightState(
  position: FightState(a: position, ...),
  overlayA: overlay,
  ...
)
```

## Key Insights

1. **Position = Legal moves** - What moves are geometrically/biomechanically possible
2. **Overlay = Viable moves** - What moves are actually performable given condition
3. **Tree stores positions** - Reusable across all fighters in all conditions
4. **Runtime applies overlays** - Customizes for specific fighter state

**Analogy:** Chess endgame tablebases
- Tablebase: "From this piece configuration, these moves are legal"
- Runtime: "Given time pressure, which moves are practical?"
- Same position, different viability based on context

---

**The tree is a map of positional possibilities. Overlays are the fighter's ability to navigate that map.** 🥋
