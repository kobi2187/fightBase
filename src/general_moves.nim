## General move definitions using the new categorical system
## Moves are GENERAL patterns, not specific martial art techniques

import fight_types
import constraints
import moves
import std/[sets]

# ============================================================================
# POSITIONAL MOVES
# ============================================================================

proc createStepForward*(): Move =
  ## General forward step - creates distance and angle options
  result = Move(
    id: "step_forward",
    name: "Step Forward",
    moveType: mtPositional,
    category: mcStep,
    targets: @[],  # No offensive targets
    energyCost: 0.05,  # Very low energy
    timeCost: 0.2,
    reach: 0.0,
    height: Mid,
    angleBias: 0.0,
    recoveryTime: 0.1,
    lethalPotential: 0.0,
    positionShift: PositionDelta(
      distanceChange: -0.3,  # Closer
      angleChange: 0.0,
      balanceChange: -0.05,  # Slight balance risk
      heightChange: 0.0
    ),
    physicsEffect: PhysicsEffect(
      linearMomentum: 0.5,  # Forward momentum
      rotationalMomentum: 0.0,
      hipRotationDelta: 0.0,
      torsoRotationDelta: 0.0,
      weightShift: 0.1,  # Weight shifts forward
      commitmentLevel: 0.1,  # Low commitment
      recoveryFramesOnMiss: 0,
      recoveryFramesOnHit: 0
    ),
    styleOrigins: @["Universal"],
    followups: @[],  # Will be populated later
    limbsUsed: {LeftLeg, RightLeg},
    canCombine: true,
    optionsCreated: 12,  # Creates many follow-up options
    exposureRisk: 0.15  # Some exposure from moving forward
  )

  result.prerequisites = proc(state: FightState, who: FighterID): bool =
    let fighter = if who == FighterA: state.a else: state.b
    # Can step if balanced and not too fatigued
    result = fighter.pos.balance > 0.4 and fighter.fatigue < 0.9

  result.apply = proc(state: var FightState, who: FighterID) =
    var fighter = if who == FighterA: addr state.a else: addr state.b
    # Shift position forward
    fighter.pos.x += (if who == FighterA: 0.3 else: -0.3)
    # Small balance adjustment
    fighter.pos.balance = max(0.3, fighter.pos.balance - 0.05)
    # Add momentum
    fighter.momentum.linear += 0.5
    # Minimal fatigue
    fighter.fatigue = min(1.0, fighter.fatigue + 0.01)

# ============================================================================
# EVASION MOVES
# ============================================================================

proc createSlipLeft*(): Move =
  ## Head movement to evade - minimal energy, maximum safety
  result = Move(
    id: "slip_left",
    name: "Slip Left",
    moveType: mtEvasion,
    category: mcSlip,
    targets: @[],
    energyCost: 0.03,  # Very efficient
    timeCost: 0.15,
    reach: 0.0,
    height: High,  # Head level
    angleBias: -15.0,  # Slight left
    recoveryTime: 0.1,
    lethalPotential: 0.0,
    positionShift: PositionDelta(
      distanceChange: 0.0,
      angleChange: -15.0,
      balanceChange: -0.02,
      heightChange: -0.05  # Slight duck
    ),
    physicsEffect: PhysicsEffect(
      linearMomentum: 0.0,
      rotationalMomentum: 10.0,  # Some rotation
      hipRotationDelta: -10.0,
      torsoRotationDelta: -15.0,
      weightShift: -0.1,  # Weight to left
      commitmentLevel: 0.05,
      recoveryFramesOnMiss: 0,
      recoveryFramesOnHit: 0
    ),
    styleOrigins: @["Boxing", "Muay Thai"],
    followups: @["counter_cross", "counter_hook"],
    limbsUsed: {},  # No limbs, just head/torso
    canCombine: true,
    optionsCreated: 8,  # Loaded for counters
    exposureRisk: 0.05  # Very safe
  )

  result.prerequisites = proc(state: FightState, who: FighterID): bool =
    let fighter = if who == FighterA: state.a else: state.b
    # Need decent balance and not recovering
    result = fighter.pos.balance > 0.5 and not fighter.biomech.recovering

  result.apply = proc(state: var FightState, who: FighterID) =
    var fighter = if who == FighterA: addr state.a else: addr state.b
    # Rotate torso
    fighter.biomech.torsoRotation -= 15.0
    fighter.biomech.hipRotation -= 10.0
    # Shift weight
    fighter.biomech.weightDistribution -= 0.1
    # Minimal fatigue
    fighter.fatigue = min(1.0, fighter.fatigue + 0.005)

# ============================================================================
# DEFLECTION MOVES
# ============================================================================

proc createParryLeft*(): Move =
  ## Deflect attack with minimal force - Wing Chun/Boxing principle
  result = Move(
    id: "parry_left",
    name: "Left Parry",
    moveType: mtDeflection,
    category: mcParry,
    targets: @[],
    energyCost: 0.04,
    timeCost: 0.12,  # Very fast
    reach: 0.4,  # Reach of arm
    height: High,
    angleBias: -15.0,
    recoveryTime: 0.08,
    lethalPotential: 0.0,
    positionShift: PositionDelta(
      distanceChange: 0.0,
      angleChange: -10.0,
      balanceChange: 0.0,  # No balance loss
      heightChange: 0.0
    ),
    physicsEffect: PhysicsEffect(
      linearMomentum: 0.0,
      rotationalMomentum: 5.0,
      hipRotationDelta: 0.0,
      torsoRotationDelta: -10.0,
      weightShift: 0.0,
      commitmentLevel: 0.02,  # Almost no commitment
      recoveryFramesOnMiss: 0,
      recoveryFramesOnHit: 0
    ),
    styleOrigins: @["Boxing", "Wing Chun", "Savate"],
    followups: @["cross", "hook", "straight_strike"],
    limbsUsed: {LeftArm},
    canCombine: true,
    optionsCreated: 15,  # Creates huge options (counter window)
    exposureRisk: 0.02  # Very safe, uses structure
  )

  result.prerequisites = proc(state: FightState, who: FighterID): bool =
    let fighter = if who == FighterA: state.a else: state.b
    # Just need free left arm
    result = fighter.leftArm.free and not fighter.leftArm.damaged > 0.5

  result.apply = proc(state: var FightState, who: FighterID) =
    var fighter = if who == FighterA: addr state.a else: addr state.b
    # Rotate slightly
    fighter.biomech.torsoRotation -= 10.0
    # Almost no fatigue (efficient)
    fighter.fatigue = min(1.0, fighter.fatigue + 0.003)

# ============================================================================
# OFFENSIVE MOVES (GENERAL CATEGORIES)
# ============================================================================

proc createStraightStrike*(): Move =
  ## General straight strike - jab, cross, teep, etc are all variations
  ## Targets: nose, throat, solar plexus
  result = Move(
    id: "straight_strike",
    name: "Straight Strike",
    moveType: mtOffensive,
    category: mcStraightStrike,
    targets: @["vzNose", "vzThroat", "vzSolarPlexus", "vzEyes"],
    energyCost: 0.12,
    timeCost: 0.18,
    reach: 0.7,  # Arm reach
    height: High,
    angleBias: 0.0,  # Centerline
    recoveryTime: 0.15,
    lethalPotential: 0.3,
    positionShift: PositionDelta(
      distanceChange: -0.1,  # Slight forward
      angleChange: 0.0,
      balanceChange: -0.05,
      heightChange: 0.0
    ),
    physicsEffect: PhysicsEffect(
      linearMomentum: 0.3,
      rotationalMomentum: 0.0,
      hipRotationDelta: 5.0,
      torsoRotationDelta: 10.0,
      weightShift: 0.08,
      commitmentLevel: 0.15,
      recoveryFramesOnMiss: 2,
      recoveryFramesOnHit: 1
    ),
    styleOrigins: @["Boxing", "Karate", "JKD", "Muay Thai"],
    followups: @["straight_strike", "arc_strike", "step_back"],
    limbsUsed: {RightArm},  # Can be either, this is generic
    canCombine: true,
    optionsCreated: 10,
    exposureRisk: 0.25  # Some exposure from extending
  )

  result.prerequisites = proc(state: FightState, who: FighterID): bool =
    let fighter = if who == FighterA: state.a else: state.b
    # Need arm free, in range, balanced
    result = fighter.rightArm.free and
             state.distance in [Short, Medium] and
             fighter.pos.balance > 0.4 and
             fighter.fatigue < 0.85

  result.apply = proc(state: var FightState, who: FighterID) =
    var fighter = if who == FighterA: addr state.a else: addr state.b
    var opponent = if who == FighterA: addr state.b else: addr state.a

    # Add momentum
    fighter.momentum.linear += 0.3
    fighter.biomech.hipRotation += 5.0
    fighter.biomech.torsoRotation += 10.0
    fighter.biomech.weightDistribution += 0.08

    # Fatigue cost
    fighter.fatigue = min(1.0, fighter.fatigue + 0.08)

    # Damage opponent (simplified - would check vulnerability system)
    # For now, small chance of effect
    if fighter.pos.balance > 0.7:  # Good strike
      opponent.damage += 0.02
      opponent.pos.balance -= 0.05

proc createLowKick*(): Move =
  ## Low kick targeting thigh/knee
  result = Move(
    id: "low_kick",
    name: "Low Kick",
    moveType: mtOffensive,
    category: mcArcStrike,
    targets: @["vzThighMuscle", "vzKneeLateral", "vzCalf"],
    energyCost: 0.18,
    timeCost: 0.35,
    reach: 0.9,
    height: Low,
    angleBias: 45.0,  # Comes from angle
    recoveryTime: 0.25,
    lethalPotential: 0.4,  # Can disable mobility
    positionShift: PositionDelta(
      distanceChange: 0.0,
      angleChange: 20.0,
      balanceChange: -0.15,  # Riskier
      heightChange: 0.0
    ),
    physicsEffect: PhysicsEffect(
      linearMomentum: 0.2,
      rotationalMomentum: 45.0,  # Heavy rotation
      hipRotationDelta: 60.0,
      torsoRotationDelta: 30.0,
      weightShift: -0.3,  # Weight to standing leg
      commitmentLevel: 0.4,  # Fairly committed
      recoveryFramesOnMiss: 4,
      recoveryFramesOnHit: 2
    ),
    styleOrigins: @["Muay Thai", "Kickboxing", "Kyokushin"],
    followups: @["straight_strike", "clinch_entry"],
    limbsUsed: {RightLeg},
    canCombine: false,  # Can't really combine a kick easily
    optionsCreated: 6,
    exposureRisk: 0.45  # Significant exposure
  )

  result.prerequisites = proc(state: FightState, who: FighterID): bool =
    let fighter = if who == FighterA: state.a else: state.b
    # Need leg free, medium-close range, good balance
    result = fighter.rightLeg.free and
             state.distance in [Short, Medium] and
             fighter.pos.balance > 0.6 and
             fighter.fatigue < 0.8 and
             fighter.momentum.rotational.abs < 30.0  # Not already spinning

  result.apply = proc(state: var FightState, who: FighterID) =
    var fighter = if who == FighterA: addr state.a else: addr state.b
    var opponent = if who == FighterA: addr state.b else: addr state.a

    # Heavy rotation
    fighter.momentum.rotational += 45.0
    fighter.biomech.hipRotation += 60.0
    fighter.biomech.torsoRotation += 30.0
    fighter.biomech.weightDistribution -= 0.3

    # Set recovering
    fighter.biomech.recovering = true
    fighter.biomech.recoveryFrames = 4

    # Fatigue
    fighter.fatigue = min(1.0, fighter.fatigue + 0.12)

    # If hits, affects opponent's leg/mobility
    if fighter.pos.balance > 0.6:
      opponent.damage += 0.04
      opponent.pos.balance -= 0.1
      # Could set opponent's leg as damaged

# Register all moves
proc registerGeneralMoves*() =
  ## Register all general moves to the global database
  registerMove(createStepForward())
  registerMove(createSlipLeft())
  registerMove(createParryLeft())
  registerMove(createStraightStrike())
  registerMove(createLowKick())
