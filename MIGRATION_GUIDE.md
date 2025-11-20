# Migration Guide: Overlay Architecture

## What Changed

**Before:** Fatigue and damage were part of `Fighter` state and included in tree hash.

**After:** Fatigue and damage are `RuntimeOverlay` fields, applied as filters at runtime.

## Files That Need Updates

The following files reference the old `.fatigue` or `.damage` fields:

1. `src/simulator.nim` - Main simulation loop
2. `src/moves.nim` - Move definitions
3. `src/general_moves.nim` - General move definitions
4. `src/fight_notation.nim` - FPN serialization
5. `src/fight_display.nim` - Display rendering
6. `src/state_storage.nim` - State persistence
7. `src/constraints.nim` - Move constraints
8. `src/tactical.nim` - Tactical evaluation
9. `src/combos.nim` - Combo system
10. `src/fpn_to_svg.nim` - SVG generation
11. `src/move_variants.nim` - Move variant comparison

## Migration Patterns

### Pattern 1: Reading Fatigue/Damage

**Before:**
```nim
proc canPerformMove(fighter: Fighter, move: Move): bool =
  if fighter.fatigue > 0.8:
    return false
  if fighter.damage > 0.5:
    return false
  return true
```

**After:**
```nim
# Option A: Use viability check in move definition
proc jabViability(overlay: RuntimeOverlay, move: Move): float =
  if overlay.fatigue > 0.8:
    return 0.0  # Can't perform
  if overlay.damage > 0.5:
    return 0.3  # Reduced effectiveness
  return 1.0 - (overlay.fatigue * 0.5)  # Scaled by fatigue

let jab = Move(
  name: "Jab",
  viabilityCheck: jabViability,
  ...
)

# Option B: Pass overlay separately
proc canPerformMove(fighter: Fighter, overlay: RuntimeOverlay, move: Move): bool =
  if overlay.fatigue > 0.8:
    return false
  if overlay.damage > 0.5:
    return false
  return true
```

### Pattern 2: Modifying Fatigue/Damage

**Before:**
```nim
proc applyMove(state: var FightState, move: Move, who: FighterID) =
  var fighter = state.getFighter(who)
  fighter.fatigue += move.energyCost

  var opponent = state.getOpponent(who)
  opponent.damage += move.damageDealt
```

**After:**
```nim
proc applyMove(state: var RuntimeFightState, move: Move, who: FighterID) =
  # Update position (tree state)
  move.apply(state.position, who)

  # Update overlays (runtime state)
  var attackerOverlay = state.getOverlay(who)
  attackerOverlay.fatigue += move.energyCost

  var defenderOverlay = state.getOpponent Overlay(who)
  defenderOverlay.damage += move.damageEffect.directDamage

  # Apply limb damage if applicable
  if move.damageEffect.targetLimb.isSome:
    let limb = move.damageEffect.targetLimb.get
    case limb:
    of LeftArm: defenderOverlay.leftArmDamage += move.damageEffect.limbDamage
    of RightArm: defenderOverlay.rightArmDamage += move.damageEffect.limbDamage
    of LeftLeg: defenderOverlay.leftLegDamage += move.damageEffect.limbDamage
    of RightLeg: defenderOverlay.rightLegDamage += move.damageEffect.limbDamage
```

### Pattern 3: FPN Serialization

**Before:**
```nim
proc fighterToFPN(fighter: Fighter): string =
  result = fmt"{fighter.pos.stance.ord}."
  result.add fmt"{int(fighter.pos.balance*100)}."
  result.add fmt"{int(fighter.fatigue*100)}."  # ❌ In tree hash
  result.add fmt"{int(fighter.damage*100)}."   # ❌ In tree hash
```

**After:**
```nim
# FPN should ONLY serialize position (for tree)
proc fighterToFPN(fighter: Fighter): string =
  result = fmt"{fighter.pos.stance.ord}."
  result.add fmt"{int(fighter.pos.balance*100)}."
  # NO fatigue, NO damage in FPN

# Separate overlay serialization
proc overlayToString(overlay: RuntimeOverlay): string =
  result = fmt"{int(overlay.fatigue*100)},"
  result.add fmt"{int(overlay.damage*100)},"
  result.add fmt"{int(overlay.leftArmDamage*100)},"
  result.add fmt"{int(overlay.rightArmDamage*100)},"
  result.add fmt"{int(overlay.leftLegDamage*100)},"
  result.add fmt"{int(overlay.rightLegDamage*100)}"

# Full state serialization (if needed)
proc runtimeStateToFPN(state: RuntimeFightState): string =
  result = fighterToFPN(state.position.a) & "/"
  result.add fighterToFPN(state.position.b) & "/"
  result.add overlayToString(state.overlayA) & "/"
  result.add overlayToString(state.overlayB)
```

### Pattern 4: State Display

**Before:**
```nim
proc displayFighter(fighter: Fighter) =
  echo "Stance: ", fighter.pos.stance
  echo "Balance: ", fighter.pos.balance
  echo "Fatigue: ", fighter.fatigue
  echo "Damage: ", fighter.damage
```

**After:**
```nim
proc displayFighter(fighter: Fighter, overlay: RuntimeOverlay) =
  echo "Stance: ", fighter.pos.stance
  echo "Balance: ", fighter.pos.balance
  echo "Fatigue: ", overlay.fatigue
  echo "Damage: ", overlay.damage
  echo "Limb Damage:"
  echo "  Left Arm: ", overlay.leftArmDamage
  echo "  Right Arm: ", overlay.rightArmDamage
  echo "  Left Leg: ", overlay.leftLegDamage
  echo "  Right Leg: ", overlay.rightLegDamage
```

### Pattern 5: Simulator Main Loop

**Before:**
```nim
proc simulate(state: var FightState) =
  while not state.terminal:
    let moves = getViableMoves(state, FighterA)
    let chosen = selectMove(moves, state)
    chosen.apply(state, FighterA)

    state.a.fatigue += chosen.energyCost
```

**After:**
```nim
proc simulate(state: var RuntimeFightState) =
  while not state.position.terminal:
    # Get moves from position
    let allMoves = getPositionMoves(state.position, FighterA)

    # Filter by viability
    var viableMoves: seq[(Move, float)]
    for move in allMoves:
      let effectiveness = move.viabilityCheck(state.overlayA, move)
      if effectiveness > 0.0:
        viableMoves.add((move, effectiveness))

    # Select and apply
    let (chosen, effectiveness) = selectMove(viableMoves, state)
    chosen.apply(state.position, FighterA)

    # Update overlays
    state.overlayA.fatigue += chosen.energyCost
    if chosen.damageEffect.directDamage > 0:
      state.overlayB.damage += chosen.damageEffect.directDamage
```

## Helper Functions to Add

```nim
# Get overlay for fighter
proc getOverlay*(state: RuntimeFightState, who: FighterID): var RuntimeOverlay =
  if who == FighterA:
    return state.overlayA
  else:
    return state.overlayB

# Get opponent overlay
proc getOpponentOverlay*(state: RuntimeFightState, who: FighterID): var RuntimeOverlay =
  if who == FighterA:
    return state.overlayB
  else:
    return state.overlayA

# Check if move is viable given overlay
proc isViable*(move: Move, overlay: RuntimeOverlay): bool =
  if move.viabilityCheck.isNil:
    return true  # No check = always viable
  return move.viabilityCheck(overlay, move) > 0.0

# Get effective power of move given overlay
proc effectivePower*(move: Move, overlay: RuntimeOverlay): float =
  if move.viabilityCheck.isNil:
    return 1.0
  return move.viabilityCheck(overlay, move)
```

## Default Viability Checks

```nim
# Generic viability based on fatigue
proc standardViability*(overlay: RuntimeOverlay, move: Move): float =
  # Can't perform if too damaged
  if overlay.damage > 0.9:
    return 0.0

  # Reduce effectiveness by fatigue
  let fatigueMultiplier = 1.0 - (overlay.fatigue * 0.6)

  # Reduce effectiveness by overall damage
  let damageMultiplier = 1.0 - (overlay.damage * 0.5)

  return max(0.0, fatigueMultiplier * damageMultiplier)

# Limb-specific viability
proc limbViability*(overlay: RuntimeOverlay, limb: LimbType): float =
  case limb:
  of LeftArm: return 1.0 - overlay.leftArmDamage
  of RightArm: return 1.0 - overlay.rightArmDamage
  of LeftLeg: return 1.0 - overlay.leftLegDamage
  of RightLeg: return 1.0 - overlay.rightLegDamage

# Combine standard + limb viability
proc moveViability*(overlay: RuntimeOverlay, move: Move): float =
  let baseViability = standardViability(overlay, move)

  if baseViability == 0.0:
    return 0.0

  # Check limbs used
  var limbMultiplier = 1.0
  for limb in move.limbsUsed:
    limbMultiplier *= limbViability(overlay, limb)

  return baseViability * limbMultiplier
```

## Testing Strategy

1. **Unit tests:** Test overlay application separately from position changes
2. **Integration tests:** Test RuntimeFightState with both position + overlay updates
3. **Regression tests:** Ensure tree hash is position-only (no overlay influence)
4. **Performance tests:** Measure tree size reduction (should be ~100x smaller)

## Rollout Plan

1. ✅ Update `fight_types.nim` (done)
2. Update `simulator.nim` - main loop
3. Update move definitions (`moves.nim`, `general_moves.nim`)
4. Update notation (`fight_notation.nim`)
5. Update display (`fight_display.nim`)
6. Update storage (`state_storage.nim`)
7. Update constraints/tactical (`constraints.nim`, `tactical.nim`)
8. Update combos (`combos.nim`)
9. Update visualization (`fpn_to_svg.nim`)
10. Update analysis (`move_variants.nim`)

---

**Key Principle:** Position = what's possible. Overlay = what's viable.
