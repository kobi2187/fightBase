# Simultaneous Action System

## Overview

The martial arts simulation engine now supports **simultaneous and chained actions** per turn, modeling realistic combat where fighters can perform multiple moves at once.

## Key Concepts

### Turn-Based Action Budget

Each fighter's turn has a **time budget** of 0.6 seconds (`MAX_TURN_TIME`). They can perform multiple actions within this budget as long as:

1. **Time permits** - Total time cost ≤ 0.6s
2. **No limb conflicts** - Each limb used only once per turn
3. **Moves are combinable** - Some moves (kicks, throws) cannot be combined

### Move Properties

Every move now has:

```nim
timeCost: float         # How long the move takes (0.2-0.6s)
limbsUsed: set[LimbType]  # {LeftArm, RightArm, LeftLeg, RightLeg}
canCombine: bool        # Can be combined with other moves?
```

### Examples

#### Fast Combinations (Within Budget)

**Jab + Cross:**
- Jab (left arm, 0.25s) + Cross (right arm, 0.35s) = 0.6s
- ✅ Different arms, total time OK

**Step Back + Jab:**
- Step Back (legs, 0.2s) + Jab (arm, 0.25s) = 0.45s
- ✅ Different limbs, time permits

#### Cannot Combine

**Roundhouse Kick + Anything:**
- Roundhouse uses both legs (0.55s) and `canCombine = false`
- ❌ Too committed, cannot do anything else

**Two Punches Same Arm:**
- Jab (left arm, 0.25s) + another Jab (left arm, 0.25s)
- ❌ Limb conflict - can't use left arm twice

## Move Categories by Combinability

### Combinable Moves (canCombine = true)

Fast actions that can be chained:

| Move | Time | Limbs Used | Notes |
|------|------|------------|-------|
| Jab (left/right) | 0.25s | One arm | Fast setup strike |
| Cross | 0.35s | Right arm | Power punch |
| Step Back | 0.2s | Both legs | Quick retreat |
| Block-and-Counter | 0.3s | Both arms | Pre-built combo |
| Step-and-Jab | 0.35s | 1 arm + legs | Pre-built combo |

### Non-Combinable Moves (canCombine = false)

Full-commitment techniques:

| Move | Time | Limbs Used | Notes |
|------|------|------------|-------|
| Roundhouse Kick | 0.55s | Both legs | Too committed |
| Teep | 0.4s | Both legs | Push kick |
| Clinch Entry | 0.45s | Both arms | Grappling control |
| Hip Throw | 0.6s | All four limbs | Full commitment |

## Realistic Combat Patterns

### Wing Chun Style
```
Block-and-Counter (0.3s, both arms)
→ Simultaneous defense and offense
→ Common in close-range systems
```

### Boxing Combination
```
Step-and-Jab (0.35s, arm + legs)
→ Close distance while striking
→ Fundamental attacking pattern
```

### Muay Thai Approach
```
Teep (0.4s, both legs)
→ Cannot combine - single powerful action
→ Creates distance for next exchange
```

### Opportunistic Chain
```
Turn 1: Jab (0.25s) + Cross (0.35s) = 0.6s
→ Classic one-two combo
→ Maxes out time budget

Turn 2: Step Back (0.2s) alone
→ Defensive retreat
→ Only 0.2s used (could add more, but fighter chose to end turn)
```

## Simulation Behavior

### Turn Structure

```
1. Fighter A's turn begins
2. Build action sequence:
   - Check legal moves
   - Filter for compatible moves (time + limb availability)
   - Add random compatible move
   - 30% chance to end turn (or continue if time allows)
3. Repeat until:
   - No compatible moves left, OR
   - Time budget exhausted, OR
   - Random stop decision
4. Switch to Fighter B
```

### Example Turn Output

```
[5] A:
  → left Jab (Boxing) (time: 0.25s)
  → Cross (Boxing/Karate) (time: 0.35s)
  Total turn time: 0.60s, energy: 0.17
```

This shows Fighter A performed two moves in one turn, using 0.6s total (maxed out budget).

## Design Philosophy

### Why This System?

1. **Realistic** - Real fights have simultaneous actions (block + strike, step + punch)
2. **Style-Dependent** - Wing Chun emphasizes simultaneity; Karate less so
3. **Physically Constrained** - Can't use same limb twice
4. **Energy Economy** - Multiple actions drain more energy
5. **Tactical Depth** - Choosing when to commit fully vs. staying flexible

### What It Prevents

- ❌ Hollywood infinite combos (time budget limits)
- ❌ Physically impossible moves (limb tracking)
- ❌ Unrealistic multi-tasking (heavy kicks can't combine)

### What It Enables

- ✅ Defensive strike combinations (block-counter)
- ✅ Footwork integrated with attacks (step-jab)
- ✅ Rapid hand combinations (jab-cross-hook)
- ✅ Style-specific patterns (Wing Chun simultaneity)

## Adding New Simultaneous Moves

### Template for Combination Move

```nim
proc createYourCombo*(): Move =
  result = Move(
    id: "your_combo_id",
    name: "Your Combo Name (Style)",
    category: Counter,  # or appropriate category
    energyCost: 0.15,   # Combined energy
    timeCost: 0.3,      # Combined time
    reach: 0.7,
    height: Mid,
    limbsUsed: {LeftArm, RightArm},  # Multiple limbs
    canCombine: false,  # This IS the combination
    # ... rest of fields
  )
```

### Guidelines

**Pre-built combinations** (like Block-and-Counter):
- Set `canCombine = false`
- Set `limbsUsed` to all involved limbs
- Set `timeCost` to realistic combined duration

**Atomic moves** that CAN combine:
- Set `canCombine = true`
- Keep `timeCost` low (≤ 0.35s)
- Use minimal limbs

**Full-commitment moves** (kicks, throws):
- Set `canCombine = false`
- Use multiple limbs
- Higher time cost (0.4-0.6s)

## Future Enhancements

### Planned

- **Interrupt system** - Defender can interrupt attacker's sequence
- **Combination scoring** - Track effectiveness of multi-move sequences
- **Style profiles** - Some styles favor combinations more than others
- **Reaction moves** - Automatic defensive responses

### Advanced Concepts

- **Chain moves** - Certain moves automatically trigger followups
- **Combo multipliers** - Successful chains deal bonus damage/balance loss
- **Fatigue scaling** - Multiple moves in turn cost more energy
- **Risk-reward** - Longer sequences = more vulnerable to counter

## Summary

The system now models realistic martial arts combat where:

1. **You can do multiple things per turn** if physics allows
2. **Time is the limiting resource** (0.6s per turn)
3. **Limbs cannot be reused** in same turn
4. **Some moves preclude others** (kicks, throws are full-commitment)
5. **Pre-built combinations exist** for common patterns (block-counter, step-jab)

This creates a much more realistic simulation where fighters can:
- Block with one hand while striking with the other
- Step forward and punch simultaneously
- Chain fast strikes together
- Make tactical decisions about single powerful moves vs. multiple quick ones

The system naturally prevents unrealistic Hollywood-style infinite combos through time budget and limb tracking, while enabling the sophisticated simultaneous actions found in real martial arts.
