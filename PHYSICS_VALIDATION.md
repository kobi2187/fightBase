# Physics-Based Move Validation System

## Overview

The engine now includes **realistic physics validation** that prevents impossible move sequences based on momentum, body rotation, and biomechanical constraints.

## Key Problem Solved

**Before:** After a fighter threw a big haymaker that missed, they could immediately perform any move - unrealistic!

**After:** Failed haymakers generate momentum and put the fighter in recovery, limiting what moves are possible next.

## New State Tracking

### Momentum
```nim
Momentum:
  linear: float          # forward/backward momentum (m/s)
  rotational: float      # rotational momentum (deg/s)
  decayRate: float       # how fast momentum dissipates
```

### Biomechanical State
```nim
BiomechanicalState:
  hipRotation: float           # degrees from neutral (-180 to +180)
  torsoRotation: float         # degrees from hips
  weightDistribution: float    # 0.0 (back) to 1.0 (front)
  recovering: bool             # in recovery from committed move
  recoveryFrames: int          # frames until fully recovered
```

## Physics Effects Per Move

Every move now specifies:

```nim
PhysicsEffect:
  linearMomentum: float        # momentum generated
  rotationalMomentum: float    # rotational momentum
  hipRotationDelta: float      # hip movement
  torsoRotationDelta: float    # torso movement
  weightShift: float           # weight transfer
  commitmentLevel: 0.0-1.0     # how committed (affects recovery)
  recoveryFramesOnMiss: int    # recovery if misses
  recoveryFramesOnHit: int     # recovery even if hits
```

## Example: Jab vs. Haymaker

### Jab (Low Commitment)
```nim
PhysicsEffect(
  linearMomentum: 0.2,         # Slight forward push
  rotationalMomentum: 0.0,     # No spinning
  hipRotationDelta: 5.0,       # Minor hip turn
  torsoRotationDelta: 10.0,    # Slight torso rotation
  weightShift: 0.05,           # Barely shifts weight
  commitmentLevel: 0.1,        # Low commitment - easy to recover
  recoveryFramesOnMiss: 1,     # Quick recovery
  recoveryFramesOnHit: 1
)
```

**Result:** Can be chained with other moves, minimal recovery needed.

### Haymaker (High Commitment)
```nim
PhysicsEffect(
  linearMomentum: 2.5,         # LOTS of forward momentum
  rotationalMomentum: 120.0,   # Big hip/torso rotation
  hipRotationDelta: 90.0,      # Hips rotate 90 degrees!
  torsoRotationDelta: 45.0,    # Torso whips around
  weightShift: 0.4,            # Major weight transfer
  commitmentLevel: 0.9,        # Almost fully committed
  recoveryFramesOnMiss: 8,     # Long recovery if misses
  recoveryFramesOnHit: 4       # Even hitting needs recovery
)
```

**Result:** If misses, fighter is spinning with momentum, off-balance, and in recovery for 8 frames. Very limited move options.

## Physics Validations

### 1. Momentum Redirection Check

**Question:** Can the fighter redirect their current momentum to perform this move?

```nim
proc canRedirectMomentum(fighter: Fighter, move: Move): bool
```

**Rules:**
- High linear momentum (>1.5 m/s) prevents:
  - Reversing direction
  - Big rotational moves
- High rotational momentum (>60 deg/s) prevents:
  - Rotating opposite direction
  - Precise techniques

**Example:**
```
Fighter has 2.5 m/s forward momentum (from haymaker)
→ Cannot do: Step back (reverses direction) ❌
→ Can do: Continue forward with jab ✅
→ Cannot do: Spinning kick (adds rotation) ❌
```

### 2. Biomechanical Viability Check

**Question:** Is the move physically possible given body configuration?

```nim
proc isBiomechanicallyViable(fighter: Fighter, move: Move): bool
```

**Rules:**
- **Heavy recovery** (>2 frames remaining):
  - Only light defensive moves allowed
  - No high-commitment moves
- **Hip rotation** (>60 degrees):
  - Cannot do opposite-side strikes
  - Must unwind hips first
  - Throws impossible
- **Extreme weight** distribution (<0.2 or >0.8):
  - Sweeps/trips impossible
  - Throws impossible

**Example:**
```
Fighter's hips rotated 90° right (from haymaker)
→ Cannot do: Left hook (opposite rotation) ❌
→ Can do: Right uppercut (same side) ✅
→ Cannot do: Hip throw (needs neutral hips) ❌
```

### 3. Recovery Feasibility Check

**Question:** Can the fighter recover from this move given current momentum?

```nim
proc canRecoverFromMomentum(fighter: Fighter, move: Move): bool
```

**Rules:**
- If already have momentum + adding high-commitment move:
  - Too risky - balance penalty too high
  - Move rejected

**Example:**
```
Fighter has 1.2 m/s momentum
Attempting haymaker (0.9 commitment)
→ Cannot do: Too risky, already off-balance ❌
```

## Momentum Decay

Each turn, momentum naturally dissipates:

```nim
proc applyMomentumDecay(fighter: var Fighter)
```

- Linear momentum: × 0.7 each turn (30% lost)
- Rotational momentum: × 0.7 each turn
- Zeroed out below threshold

## Biomechanical Decay

Body naturally returns to neutral:

```nim
proc naturalBiomechanicalDecay(fighter: var Fighter)
```

- Hips drift back toward neutral: -10° per turn
- Torso returns toward neutral: -15° per turn
- Weight returns to 50/50: ±0.1 per turn

## Integration with Simulator

### Per Turn:
```
1. Check terminal conditions
2. Build action sequence (validates physics)
3. Apply moves (generates momentum/rotation)
4. Apply physics effects to fighter
5. Apply momentum decay
6. Apply biomechanical decay
7. Decrement recovery frames
8. Switch fighters
```

### Move Application:
```
1. Apply fatigue
2. Update limb states
3. Apply momentum from move
4. Update biomechanical state (hips, torso, weight)
5. Set recovery frames if miss/hit
6. Apply damage/balance to opponent
7. Check if move landed
```

## Realistic Scenarios

### Scenario 1: Failed Haymaker

```
Turn 1: Fighter A throws haymaker at Fighter B
  → Misses!
  → A now has:
    - 2.5 m/s forward momentum
    - 120 deg/s rotational momentum
    - Hips rotated 90°
    - Weight 90% on front foot
    - Recovering: 8 frames

Turn 2: Fighter A tries to throw left hook
  → Physics validation FAILS:
    - Hips rotated wrong direction ❌
    - Still in heavy recovery (8 frames) ❌
    - Too much momentum to control ❌
  → Move rejected

Turn 2 (revised): Fighter A can only:
  → Continue forward (momentum compatible)
  → Light defensive moves (low commitment)
  → Step to redirect momentum
  ```

### Scenario 2: Successful Jab Chain

```
Turn 1: Fighter A throws left jab
  → Lands!
  → A now has:
    - 0.2 m/s forward momentum (small)
    - Hips rotated 5° (minimal)
    - Recovering: 1 frame

Turn 2: Fighter A throws cross
  → Physics validation PASSES:
    - Momentum manageable ✅
    - Hips can rotate further ✅
    - Commitment level OK ✅
    - Recovery complete ✅
  → Move allowed

Result: Clean 1-2 combo works because jabs are low-commitment.
```

### Scenario 3: Spinning Back Kick

```
Turn 1: Fighter A throws spinning back kick
  → Generates 150 deg/s rotational momentum
  → Misses!
  → Recovering: 10 frames

Turn 2: Fighter A tries ANYTHING complex
  → Physics validation FAILS:
    - Still spinning (momentum) ❌
    - Heavy recovery (10 frames) ❌
    - Can only do defensive movements

Turns 2-4: Fighter gradually recovers
  → Momentum decays: 150 → 105 → 73 → 51 deg/s
  → Recovery: 10 → 9 → 8 → 7 frames
  → By turn 5, can fight again
```

## Benefits

1. **Realism** - Fighters cannot magically recover from committed moves
2. **Strategy** - Risk vs. reward for big techniques
3. **Style Differences** - Conservative styles avoid high-commitment moves
4. **Natural Flow** - Fights feel like real physics
5. **Punishes Mistakes** - Missing a haymaker is genuinely bad

## Move Design Guidelines

### Low-Risk Moves (Jab, Step)
- Low momentum generation (<0.5 m/s)
- Low commitment (<0.3)
- Quick recovery (1-2 frames)
- Small hip/torso rotation (<20°)

### Medium-Risk Moves (Cross, Low Kick)
- Moderate momentum (0.5-1.5 m/s)
- Medium commitment (0.3-0.6)
- Moderate recovery (2-4 frames)
- Moderate rotation (20-60°)

### High-Risk Moves (Haymaker, Spinning Kicks)
- High momentum (>1.5 m/s)
- High commitment (>0.7)
- Long recovery (5-10+ frames)
- Large rotation (>60°)

## Future Enhancements

- **Momentum-based damage** - Harder hits when moving fast
- **Counter-opportunity windows** - Opponents can counter during recovery
- **Fatigue affects recovery** - Tired fighters recover slower
- **Style-specific physics** - Some styles better at momentum management
- **Chain momentum** - Successfully chaining moves reduces commitment

## Summary

The physics system ensures that:
- **You cannot instantly change direction** after a committed strike
- **Missing big moves is punishing** (long recovery, momentum penalty)
- **Body configuration matters** (hip/torso rotation affects options)
- **Momentum must be managed** (cannot just spam techniques)
- **Natural decay occurs** (body returns to neutral over time)

This creates realistic martial arts simulation where physics actually matters, and fighters must think about consequences of commitment.
