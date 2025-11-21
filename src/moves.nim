## Move database and move definitions
## This is where we define all the martial arts techniques

import fight_types
import constraints
import std/[tables, options, math, random, strutils]

# Global move registry
var ALL_MOVES*: seq[Move] = @[]
var MOVE_INDEX*: Table[string, int] = initTable[string, int]()

# ============================================================================
# Move registration
# ============================================================================

proc registerMove*(move: Move) =
  ## Add a move to the global registry
  MOVE_INDEX[move.id] = ALL_MOVES.len
  ALL_MOVES.add(move)

proc getMoveById*(id: string): Option[Move] =
  ## Retrieve a move by ID
  if id in MOVE_INDEX:
    result = some(ALL_MOVES[MOVE_INDEX[id]])
  else:
    result = none(Move)

proc viableMoves*(state: FightState, who: FighterID): seq[Move] =
  ## Get all viable moves for a fighter in current state
  ## "Viable" = physically possible given physics, not sport rules
  result = @[]
  for move in ALL_MOVES:
    if move.prerequisites(state, who):
      result.add(move)

# ============================================================================
# Action sequence building
# ============================================================================

const MAX_TURN_TIME* = 0.6  # Maximum seconds per turn

proc canCombineMoveTypes*(existing: seq[MoveType], newType: MoveType): bool =
  ## Check if this move type can combine with existing move types in the sequence
  ## Different categories can combine, but with limits

  # Count how many of each type we already have
  var typeCounts: array[MoveType, int]
  for mt in existing:
    inc typeCounts[mt]

  # Check combination rules
  case newType:
  of mtPositional:
    # Can always add positional (footwork) unless already have 2+
    result = typeCounts[mtPositional] < 2

  of mtEvasion:
    # Can add evasion unless already have 2+ evasions
    result = typeCounts[mtEvasion] < 2

  of mtDeflection:
    # Can add deflection unless already have 2+ deflections
    result = typeCounts[mtDeflection] < 2

  of mtDefensive:
    # Can add defensive blocking unless already have 2+
    result = typeCounts[mtDefensive] < 2

  of mtOffensive:
    # Offensive moves are limited - only 1-2 per sequence
    # Can't add if already have 2 offensive moves
    result = typeCounts[mtOffensive] < 2

proc canAddToSequence*(sequence: ActionSequence, move: Move): bool =
  ## Check if a move can be added to the current action sequence
  ## Checks time, limbs, combination rules, and move type compatibility

  # Check time budget
  if sequence.totalTimeCost + move.timeCost > MAX_TURN_TIME:
    return false

  # Check limb conflicts
  if (move.limbsUsed * sequence.limbsUsed).card > 0:
    return false  # Limbs overlap

  # Check if either move cannot be combined
  if sequence.moves.len > 0 and (not move.canCombine or not sequence.moves[^1].canCombine):
    return false

  # Check move type compatibility (new rule for ply combinations)
  if sequence.moves.len > 0:
    var existingTypes: seq[MoveType] = @[]
    for m in sequence.moves:
      existingTypes.add(m.moveType)

    if not canCombineMoveTypes(existingTypes, move.moveType):
      return false

  result = true

proc addMoveToSequence*(sequence: var ActionSequence, move: Move) =
  ## Add a move to an action sequence
  sequence.moves.add(move)
  sequence.totalTimeCost += move.timeCost
  sequence.totalEnergyCost += move.energyCost
  sequence.limbsUsed = sequence.limbsUsed + move.limbsUsed

proc createEmptySequence*(): ActionSequence =
  ## Create an empty action sequence
  result = ActionSequence(
    moves: @[],
    totalTimeCost: 0.0,
    totalEnergyCost: 0.0,
    limbsUsed: {}
  )

# ============================================================================
# Helper functions for move application
# ============================================================================

proc applyBalanceChange*(fighter: var Fighter, change: float) =
  fighter.pos.balance = clamp(fighter.pos.balance + change, 0.0, 1.0)

proc changeDistance*(state: var FightState, delta: float) =
  ## Change distance between fighters
  let current = distanceInMeters(state.distance)
  let new = current + delta
  state.distance =
    if new < 0.3: Contact
    elif new < 0.8: Short
    elif new < 1.5: Medium
    elif new < 2.5: Long
    else: VeryLong

proc extendLimb*(limb: var LimbPosition) =
  limb.extended = true
  limb.free = false

proc retractLimb*(limb: var LimbPosition) =
  limb.extended = false
  limb.free = true

# ============================================================================
# Default viability checks
# ============================================================================

proc standardViability*(overlay: RuntimeOverlay, move: Move): float =
  ## Generic viability based on fatigue and damage
  # Can't perform if too damaged
  if overlay.damage > 0.9:
    return 0.0

  # Reduce effectiveness by fatigue
  let fatigueMultiplier = 1.0 - (overlay.fatigue * 0.6)

  # Reduce effectiveness by overall damage
  let damageMultiplier = 1.0 - (overlay.damage * 0.5)

  return max(0.0, fatigueMultiplier * damageMultiplier)

proc limbViability*(overlay: RuntimeOverlay, limb: LimbType): float =
  ## Check viability of specific limb
  case limb:
  of LeftArm: return 1.0 - overlay.leftArmDamage
  of RightArm: return 1.0 - overlay.rightArmDamage
  of LeftLeg: return 1.0 - overlay.leftLegDamage
  of RightLeg: return 1.0 - overlay.rightLegDamage

proc moveViability*(overlay: RuntimeOverlay, move: Move): float =
  ## Combine standard + limb viability
  let baseViability = standardViability(overlay, move)

  if baseViability == 0.0:
    return 0.0

  # Check limbs used
  var limbMultiplier = 1.0
  for limb in move.limbsUsed:
    limbMultiplier *= limbViability(overlay, limb)

  return baseViability * limbMultiplier

# ============================================================================
# STRIKING MOVES
# ============================================================================

proc createJab*(side: string = "left", origin: string = "Boxing"): Move =
  ## Lead hand straight punch
  let moveId = "jab_" & side & "_" & origin.toLowerAscii()
  let isLeft = side == "left"
  let limbUsed = if isLeft: {LeftArm} else: {RightArm}
  let targetLimb = if isLeft: some(LeftArm) else: some(RightArm)

  result = Move(
    id: moveId,
    name: side & " Jab (" & origin & ")",
    moveType: mtOffensive,
    category: mcStraightStrike,
    energyCost: 0.05,
    timeCost: 0.25,  # Fast punch
    reach: 0.7,
    height: High,
    angleBias: 0.0,
    recoveryTime: 0.3,
    lethalPotential: 0.1,
    positionShift: PositionDelta(
      distanceChange: 0.0,
      angleChange: 0.0,
      balanceChange: -0.02,
      heightChange: 0.0
    ),
    physicsEffect: PhysicsEffect(
      linearMomentum: 0.2,      # Small forward momentum
      rotationalMomentum: 0.0,  # No rotation
      hipRotationDelta: 5.0,    # Slight hip engagement
      torsoRotationDelta: 10.0, # Torso rotates into punch
      weightShift: 0.05,        # Slight weight forward
      commitmentLevel: 0.1,     # Low commitment
      recoveryFramesOnMiss: 1,  # Quick recovery
      recoveryFramesOnHit: 1
    ),
    damageEffect: DamageEffect(
      directDamage: 0.05,       # Small damage
      fatigueInflicted: 0.02,   # Slight fatigue to opponent
      targetLimb: none(LimbType),  # No specific limb targeted
      limbDamage: 0.0
    ),
    postureChange: none(PostureLevel),  # Jab doesn't change posture
    styleOrigins: @[origin],
    followups: @["cross_right", "hook_left", "step_back"],
    limbsUsed: limbUsed,
    canCombine: true  # Can be combined with other moves
  )

  # Set up prerequisite closure (position-based only)
  result.prerequisites = proc(state: FightState, who: FighterID): bool =
    let fighter = if who == FighterA: state.a else: state.b
    # Need free arm and sufficient balance
    let armFree = if isLeft: fighter.leftArm.free else: fighter.rightArm.free
    result = armFree and fighter.pos.balance >= 0.3

  # Set up viability check (overlay-based)
  result.viabilityCheck = moveViability

  # Set up application closure (position changes only, no overlay updates)
  result.apply = proc(state: var FightState, who: FighterID) =
    var attacker = if who == FighterA: addr state.a else: addr state.b
    var defender = if who == FighterA: addr state.b else: addr state.a

    # Calculate posture-dependent effectiveness
    let postureMultiplier = getPostureEffectMultiplier(attacker[].posture, result.category)

    # Extend arm temporarily (position change)
    if isLeft:
      extendLimb(attacker[].leftArm)
    else:
      extendLimb(attacker[].rightArm)

    # Apply balance change if hit lands (adjusted by posture)
    let effectiveBalance = -0.05 * postureMultiplier
    if rand(1.0) > defender[].pos.balance * 0.5:
      applyBalanceChange(defender[], effectiveBalance)

    # Retract
    if isLeft:
      retractLimb(attacker[].leftArm)
    else:
      retractLimb(attacker[].rightArm)

    # Update physics (position state) - scaled by posture
    attacker[].momentum.linear += result.physicsEffect.linearMomentum * postureMultiplier
    attacker[].biomech.hipRotation += result.physicsEffect.hipRotationDelta * postureMultiplier
    attacker[].biomech.torsoRotation += result.physicsEffect.torsoRotationDelta * postureMultiplier
    attacker[].biomech.weightDistribution += result.physicsEffect.weightShift * postureMultiplier

    # Apply posture change if specified (STATE TRANSITION!)
    if result.postureChange.isSome:
      attacker[].posture = result.postureChange.get()

    state.sequenceLength += 1

proc createCross*(): Move =
  ## Rear hand power punch
  result = Move(
    id: "cross_right",
    name: "Cross (Boxing/Karate)",
    moveType: mtOffensive,
    category: mcStraightStrike,
    energyCost: 0.12,
    timeCost: 0.35,  # Slower than jab, more power
    reach: 0.8,
    height: High,
    angleBias: 0.0,
    recoveryTime: 0.5,
    lethalPotential: 0.25,
    positionShift: PositionDelta(
      distanceChange: 0.1,
      angleChange: 15.0,
      balanceChange: -0.08,
      heightChange: 0.0
    ),
    physicsEffect: PhysicsEffect(
      linearMomentum: 0.4,
      rotationalMomentum: 0.0,
      hipRotationDelta: 15.0,
      torsoRotationDelta: 20.0,
      weightShift: 0.15,
      commitmentLevel: 0.3,
      recoveryFramesOnMiss: 2,
      recoveryFramesOnHit: 1
    ),
    damageEffect: DamageEffect(
      directDamage: 0.15,
      fatigueInflicted: 0.05,
      targetLimb: none(LimbType),
      limbDamage: 0.0
    ),
    postureChange: none(PostureLevel),
    styleOrigins: @["Boxing", "Karate", "MMA"],
    followups: @["hook_left", "step_back", "clinch_entry"],
    limbsUsed: {RightArm},
    canCombine: true
  )

  result.prerequisites = proc(state: FightState, who: FighterID): bool =
    let fighter = if who == FighterA: state.a else: state.b
    result = fighter.rightArm.free and fighter.pos.balance >= 0.3

  result.viabilityCheck = moveViability

  result.apply = proc(state: var FightState, who: FighterID) =
    var attacker = if who == FighterA: addr state.a else: addr state.b
    var defender = if who == FighterA: addr state.b else: addr state.a

    extendLimb(attacker[].rightArm)

    # More power, better hit chance
    if rand(1.0) > defender[].pos.balance * 0.4:
      applyBalanceChange(defender[], -0.15)

    retractLimb(attacker[].rightArm)

    # Update physics
    attacker[].momentum.linear += result.physicsEffect.linearMomentum
    attacker[].biomech.hipRotation += result.physicsEffect.hipRotationDelta
    attacker[].biomech.torsoRotation += result.physicsEffect.torsoRotationDelta

    state.sequenceLength += 1

proc createRoundhouseKick*(): Move =
  ## Circular kick (Muay Thai, Karate, TKD)
  result = Move(
    id: "roundhouse_right",
    name: "Roundhouse Kick (Muay Thai)",
    moveType: mtOffensive,
    category: mcArcStrike,
    energyCost: 0.25,
    timeCost: 0.55,  # Takes time to chamber and execute
    reach: 1.0,
    height: Mid,
    angleBias: 45.0,
    recoveryTime: 0.7,
    lethalPotential: 0.4,
    positionShift: PositionDelta(
      distanceChange: 0.0,
      angleChange: 30.0,
      balanceChange: -0.2,
      heightChange: 0.0
    ),
    physicsEffect: PhysicsEffect(
      linearMomentum: 0.3,
      rotationalMomentum: 0.5,
      hipRotationDelta: 45.0,
      torsoRotationDelta: 30.0,
      weightShift: 0.2,
      commitmentLevel: 0.6,
      recoveryFramesOnMiss: 3,
      recoveryFramesOnHit: 2
    ),
    damageEffect: DamageEffect(
      directDamage: 0.25,
      fatigueInflicted: 0.08,
      targetLimb: none(LimbType),
      limbDamage: 0.0
    ),
    postureChange: none(PostureLevel),
    styleOrigins: @["Muay Thai", "Karate", "Taekwondo"],
    followups: @["step_back", "clinch_entry", "switch_stance"],
    limbsUsed: {RightLeg, LeftLeg},  # Uses both legs (standing leg + kicking leg)
    canCombine: false  # Cannot combine with other moves (too committed)
  )

  result.prerequisites = proc(state: FightState, who: FighterID): bool =
    let fighter = if who == FighterA: state.a else: state.b
    result = fighter.rightLeg.free and fighter.pos.balance >= 0.6

  result.viabilityCheck = moveViability

  result.apply = proc(state: var FightState, who: FighterID) =
    var attacker = if who == FighterA: addr state.a else: addr state.b
    var defender = if who == FighterA: addr state.b else: addr state.a

    applyBalanceChange(attacker[], -0.2)
    extendLimb(attacker[].rightLeg)

    # High damage if lands (position check only)
    if rand(1.0) > defender[].pos.balance * 0.6:
      applyBalanceChange(defender[], -0.2)

    retractLimb(attacker[].rightLeg)

    # Update physics
    attacker[].momentum.linear += result.physicsEffect.linearMomentum
    attacker[].momentum.rotational += result.physicsEffect.rotationalMomentum
    attacker[].biomech.hipRotation += result.physicsEffect.hipRotationDelta
    attacker[].biomech.torsoRotation += result.physicsEffect.torsoRotationDelta

    state.sequenceLength += 1

proc createTeep*(): Move =
  ## Front push kick (Muay Thai)
  result = Move(
    id: "teep_front",
    name: "Teep (Muay Thai)",
    moveType: mtOffensive,
    category: mcPushStrike,
    energyCost: 0.15,
    timeCost: 0.4,  # Moderately fast
    reach: 1.2,
    height: Mid,
    angleBias: 0.0,
    recoveryTime: 0.5,
    lethalPotential: 0.1,
    positionShift: PositionDelta(
      distanceChange: 0.4,  # Pushes opponent away
      angleChange: 0.0,
      balanceChange: -0.1,
      heightChange: 0.0
    ),
    physicsEffect: PhysicsEffect(
      linearMomentum: 0.25,
      rotationalMomentum: 0.0,
      hipRotationDelta: 5.0,
      torsoRotationDelta: 5.0,
      weightShift: 0.1,
      commitmentLevel: 0.3,
      recoveryFramesOnMiss: 2,
      recoveryFramesOnHit: 1
    ),
    damageEffect: DamageEffect(
      directDamage: 0.08,
      fatigueInflicted: 0.05,
      targetLimb: none(LimbType),
      limbDamage: 0.0
    ),
    postureChange: none(PostureLevel),
    styleOrigins: @["Muay Thai"],
    followups: @["step_forward", "roundhouse_right", "retreat"],
    limbsUsed: {LeftLeg, RightLeg},  # Uses both legs
    canCombine: false  # Cannot combine with other moves
  )

  result.prerequisites = proc(state: FightState, who: FighterID): bool =
    let fighter = if who == FighterA: state.a else: state.b
    result = fighter.leftLeg.free and fighter.pos.balance >= 0.5

  result.viabilityCheck = moveViability

  result.apply = proc(state: var FightState, who: FighterID) =
    var attacker = if who == FighterA: addr state.a else: addr state.b
    var defender = if who == FighterA: addr state.b else: addr state.a

    # Creates distance
    changeDistance(state, 0.4)
    applyBalanceChange(defender[], -0.15)

    # Update physics
    attacker[].momentum.linear += result.physicsEffect.linearMomentum
    attacker[].biomech.hipRotation += result.physicsEffect.hipRotationDelta

    state.sequenceLength += 1

# ============================================================================
# GRAPPLING MOVES
# ============================================================================

proc createClinchEntry*(): Move =
  ## Enter clinch position
  result = Move(
    id: "clinch_entry",
    name: "Clinch Entry (Muay Thai/Wrestling)",
    moveType: mtOffensive,
    category: mcClinchEntry,
    energyCost: 0.2,
    timeCost: 0.45,
    reach: 0.5,
    height: Mid,
    angleBias: 0.0,
    recoveryTime: 0.4,
    lethalPotential: 0.0,
    positionShift: PositionDelta(
      distanceChange: -0.5,
      angleChange: 0.0,
      balanceChange: -0.05,
      heightChange: 0.0
    ),
    physicsEffect: PhysicsEffect(
      linearMomentum: 0.3,
      rotationalMomentum: 0.0,
      hipRotationDelta: 0.0,
      torsoRotationDelta: 0.0,
      weightShift: 0.1,
      commitmentLevel: 0.5,
      recoveryFramesOnMiss: 3,
      recoveryFramesOnHit: 1
    ),
    damageEffect: DamageEffect(
      directDamage: 0.0,
      fatigueInflicted: 0.05,
      targetLimb: none(LimbType),
      limbDamage: 0.0
    ),
    postureChange: none(PostureLevel),
    styleOrigins: @["Muay Thai", "Wrestling", "Judo"],
    followups: @["knee_strike", "throw_hip", "break_clinch"],
    limbsUsed: {LeftArm, RightArm},  # Uses both arms
    canCombine: false  # Cannot combine - full commitment
  )

  result.prerequisites = proc(state: FightState, who: FighterID): bool =
    let fighter = if who == FighterA: state.a else: state.b
    result = state.distance in {Short, Medium} and hasFreeLimbs(fighter, 2)

  result.viabilityCheck = moveViability

  result.apply = proc(state: var FightState, who: FighterID) =
    var attacker = if who == FighterA: addr state.a else: addr state.b

    attacker[].control = Clinch
    state.distance = Contact

    # Update physics
    attacker[].momentum.linear += result.physicsEffect.linearMomentum

    state.sequenceLength += 1

proc createHipThrow*(): Move =
  ## Basic hip throw (Judo/Wrestling)
  result = Move(
    id: "throw_hip",
    name: "Hip Throw (Judo)",
    moveType: mtOffensive,
    category: mcThrow,
    energyCost: 0.35,
    timeCost: 0.6,  # Takes significant time
    reach: 0.3,
    height: Mid,
    angleBias: 0.0,
    recoveryTime: 0.8,
    lethalPotential: 0.5,
    positionShift: PositionDelta(
      distanceChange: 0.0,
      angleChange: 180.0,
      balanceChange: -0.3,
      heightChange: -1.0
    ),
    physicsEffect: PhysicsEffect(
      linearMomentum: 0.1,
      rotationalMomentum: 0.8,
      hipRotationDelta: 90.0,
      torsoRotationDelta: 90.0,
      weightShift: 0.3,
      commitmentLevel: 0.8,
      recoveryFramesOnMiss: 5,
      recoveryFramesOnHit: 2
    ),
    damageEffect: DamageEffect(
      directDamage: 0.2,
      fatigueInflicted: 0.1,
      targetLimb: none(LimbType),
      limbDamage: 0.0
    ),
    postureChange: none(PostureLevel),
    styleOrigins: @["Judo", "Wrestling", "Aikido"],
    followups: @["mount", "side_control", "stand_up"],
    limbsUsed: {LeftArm, RightArm, LeftLeg, RightLeg},  # Uses everything
    canCombine: false  # Cannot combine - full commitment
  )

  result.prerequisites = proc(state: FightState, who: FighterID): bool =
    let fighter = if who == FighterA: state.a else: state.b
    let opponent = if who == FighterA: state.b else: state.a
    result = state.distance == Contact and
             fighter.control in {Clinch, Underhook} and
             opponent.pos.balance < 0.7

  result.viabilityCheck = moveViability

  result.apply = proc(state: var FightState, who: FighterID) =
    var attacker = if who == FighterA: addr state.a else: addr state.b
    var defender = if who == FighterA: addr state.b else: addr state.a

    # High success when opponent off-balance
    if defender[].pos.balance < 0.5 or rand(1.0) < 0.6:
      # Successful throw
      defender[].pos.balance = 0.1
      attacker[].control = Mount
    else:
      # Failed attempt
      applyBalanceChange(attacker[], -0.2)

    # Update physics
    attacker[].momentum.rotational += result.physicsEffect.rotationalMomentum
    attacker[].biomech.hipRotation += result.physicsEffect.hipRotationDelta
    attacker[].biomech.torsoRotation += result.physicsEffect.torsoRotationDelta

    state.sequenceLength += 1

# ============================================================================
# DEFENSIVE MOVES
# ============================================================================

proc createStepBack*(): Move =
  ## Create distance
  result = Move(
    id: "step_back",
    name: "Step Back",
    moveType: mtPositional,
    category: mcStep,
    energyCost: 0.08,
    timeCost: 0.2,  # Quick defensive movement
    reach: 0.0,
    height: Mid,
    angleBias: 0.0,
    recoveryTime: 0.2,
    lethalPotential: 0.0,
    positionShift: PositionDelta(
      distanceChange: 0.5,
      angleChange: 0.0,
      balanceChange: 0.05,
      heightChange: 0.0
    ),
    physicsEffect: PhysicsEffect(
      linearMomentum: -0.2,  # Negative = moving backward
      rotationalMomentum: 0.0,
      hipRotationDelta: 0.0,
      torsoRotationDelta: 0.0,
      weightShift: -0.05,
      commitmentLevel: 0.1,
      recoveryFramesOnMiss: 0,
      recoveryFramesOnHit: 0
    ),
    damageEffect: DamageEffect(
      directDamage: 0.0,
      fatigueInflicted: 0.0,
      targetLimb: none(LimbType),
      limbDamage: 0.0
    ),
    postureChange: none(PostureLevel),
    styleOrigins: @["Boxing", "Karate", "All"],
    followups: @["jab_left", "teep_front", "circle_left"],
    limbsUsed: {LeftLeg, RightLeg},  # Uses legs for movement
    canCombine: true  # Can step back while doing something else
  )

  result.prerequisites = proc(state: FightState, who: FighterID): bool =
    let fighter = if who == FighterA: state.a else: state.b
    result = fighter.pos.balance >= 0.4

  result.viabilityCheck = moveViability

  result.apply = proc(state: var FightState, who: FighterID) =
    var fighter = if who == FighterA: addr state.a else: addr state.b

    changeDistance(state, 0.5)
    applyBalanceChange(fighter[], 0.05)

    # Update physics
    fighter[].momentum.linear += result.physicsEffect.linearMomentum

    state.sequenceLength += 1

# ============================================================================
# COMBINATION MOVES (Simultaneous Actions)
# ============================================================================

proc createBlockAndCounter*(): Move =
  ## Block with left arm while counter-punching with right (Wing Chun / Krav Maga)
  result = Move(
    id: "block_counter_right",
    name: "Block-and-Counter (Wing Chun)",
    moveType: mtDefensive,
    category: mcCounter,
    energyCost: 0.15,
    timeCost: 0.3,  # Quick simultaneous action
    reach: 0.7,
    height: Mid,
    angleBias: 0.0,
    recoveryTime: 0.35,
    lethalPotential: 0.2,
    positionShift: PositionDelta(
      distanceChange: 0.0,
      angleChange: 0.0,
      balanceChange: 0.0,
      heightChange: 0.0
    ),
    physicsEffect: PhysicsEffect(
      linearMomentum: 0.15,
      rotationalMomentum: 0.0,
      hipRotationDelta: 10.0,
      torsoRotationDelta: 15.0,
      weightShift: 0.05,
      commitmentLevel: 0.25,
      recoveryFramesOnMiss: 1,
      recoveryFramesOnHit: 1
    ),
    damageEffect: DamageEffect(
      directDamage: 0.12,
      fatigueInflicted: 0.04,
      targetLimb: none(LimbType),
      limbDamage: 0.0
    ),
    postureChange: none(PostureLevel),
    styleOrigins: @["Wing Chun", "Krav Maga", "JKD"],
    followups: @["trap_strike", "step_back"],
    limbsUsed: {LeftArm, RightArm},  # Uses both arms simultaneously
    canCombine: false  # This IS the combination
  )

  result.prerequisites = proc(state: FightState, who: FighterID): bool =
    let fighter = if who == FighterA: state.a else: state.b
    result = fighter.leftArm.free and fighter.rightArm.free and fighter.pos.balance >= 0.5

  result.viabilityCheck = moveViability

  result.apply = proc(state: var FightState, who: FighterID) =
    var attacker = if who == FighterA: addr state.a else: addr state.b
    var defender = if who == FighterA: addr state.b else: addr state.a

    # Block reduces incoming damage (defensive benefit)
    # Counter punch has chance to land
    if rand(1.0) > defender[].pos.balance * 0.55:
      applyBalanceChange(defender[], -0.08)

    # Update physics
    attacker[].momentum.linear += result.physicsEffect.linearMomentum
    attacker[].biomech.hipRotation += result.physicsEffect.hipRotationDelta
    attacker[].biomech.torsoRotation += result.physicsEffect.torsoRotationDelta

    state.sequenceLength += 1

proc createStepAndJab*(): Move =
  ## Step forward while jabbing (efficient combination)
  result = Move(
    id: "step_jab_combo",
    name: "Step-and-Jab",
    moveType: mtOffensive,
    category: mcStraightStrike,
    energyCost: 0.1,
    timeCost: 0.35,  # Combined time
    reach: 0.9,  # Extended reach due to step
    height: High,
    angleBias: 0.0,
    recoveryTime: 0.3,
    lethalPotential: 0.12,
    positionShift: PositionDelta(
      distanceChange: -0.3,  # Closing distance
      angleChange: 0.0,
      balanceChange: -0.03,
      heightChange: 0.0
    ),
    physicsEffect: PhysicsEffect(
      linearMomentum: 0.3,
      rotationalMomentum: 0.0,
      hipRotationDelta: 8.0,
      torsoRotationDelta: 12.0,
      weightShift: 0.1,
      commitmentLevel: 0.2,
      recoveryFramesOnMiss: 2,
      recoveryFramesOnHit: 1
    ),
    damageEffect: DamageEffect(
      directDamage: 0.08,
      fatigueInflicted: 0.03,
      targetLimb: none(LimbType),
      limbDamage: 0.0
    ),
    postureChange: none(PostureLevel),
    styleOrigins: @["Boxing", "Karate", "All"],
    followups: @["cross_right", "step_back"],
    limbsUsed: {LeftArm, LeftLeg, RightLeg},  # Arm + footwork
    canCombine: false  # This IS the combination
  )

  result.prerequisites = proc(state: FightState, who: FighterID): bool =
    let fighter = if who == FighterA: state.a else: state.b
    result = fighter.leftArm.free and fighter.pos.balance >= 0.6

  result.viabilityCheck = moveViability

  result.apply = proc(state: var FightState, who: FighterID) =
    var attacker = if who == FighterA: addr state.a else: addr state.b
    var defender = if who == FighterA: addr state.b else: addr state.a

    changeDistance(state, -0.3)  # Close distance

    # Better chance to land due to forward momentum
    if rand(1.0) > defender[].pos.balance * 0.45:
      applyBalanceChange(defender[], -0.06)

    # Update physics
    attacker[].momentum.linear += result.physicsEffect.linearMomentum
    attacker[].biomech.hipRotation += result.physicsEffect.hipRotationDelta
    attacker[].biomech.torsoRotation += result.physicsEffect.torsoRotationDelta

    # Apply posture change if specified
    if result.postureChange.isSome:
      attacker[].posture = result.postureChange.get()

    state.sequenceLength += 1

# ============================================================================
# POSTURE-CHANGING MOVES (Examples of state transitions)
# ============================================================================

proc createDuck*(): Move =
  ## Duck/slip - changes posture to crouched
  result = Move(
    id: "duck_evasion",
    name: "Duck (Boxing/Muay Thai)",
    moveType: mtEvasion,
    category: mcBob,
    energyCost: 0.08,
    timeCost: 0.2,  # Quick evasive movement
    reach: 0.0,
    height: Mid,
    angleBias: 0.0,
    recoveryTime: 0.25,
    lethalPotential: 0.0,
    positionShift: PositionDelta(
      distanceChange: 0.0,
      angleChange: 0.0,
      balanceChange: -0.05,  # Slightly less stable while ducking
      heightChange: -0.4     # Lower body position
    ),
    physicsEffect: PhysicsEffect(
      linearMomentum: 0.0,
      rotationalMomentum: 0.0,
      hipRotationDelta: 0.0,
      torsoRotationDelta: 0.0,
      weightShift: 0.0,
      commitmentLevel: 0.2,
      recoveryFramesOnMiss: 1,
      recoveryFramesOnHit: 1
    ),
    damageEffect: DamageEffect(
      directDamage: 0.0,
      fatigueInflicted: 0.0,
      targetLimb: none(LimbType),
      limbDamage: 0.0
    ),
    postureChange: some(plCrouched),  # KEY: Changes posture to crouched!
    styleOrigins: @["Boxing", "Muay Thai", "MMA"],
    followups: @["uppercut", "level_change", "takedown"],
    limbsUsed: {LeftLeg, RightLeg},  # Uses legs for level change
    canCombine: true  # Can duck while doing other moves
  )

  result.prerequisites = proc(state: FightState, who: FighterID): bool =
    let fighter = if who == FighterA: state.a else: state.b
    # Can duck from standing or crouched, not from ground/air
    result = fighter.posture in {plStanding, plCrouched} and fighter.pos.balance >= 0.4

  result.viabilityCheck = moveViability

  result.apply = proc(state: var FightState, who: FighterID) =
    var fighter = if who == FighterA: addr state.a else: addr state.b

    # Lower body position
    applyBalanceChange(fighter[], -0.05)

    # STATE TRANSITION: Change posture to crouched
    if result.postureChange.isSome:
      fighter[].posture = result.postureChange.get()

    state.sequenceLength += 1

proc createStandUp*(): Move =
  ## Stand up from crouched/ground - returns to standing posture
  result = Move(
    id: "stand_up",
    name: "Stand Up",
    moveType: mtPositional,
    category: mcLevelChange,
    energyCost: 0.1,
    timeCost: 0.3,  # Takes time to stand
    reach: 0.0,
    height: Mid,
    angleBias: 0.0,
    recoveryTime: 0.2,
    lethalPotential: 0.0,
    positionShift: PositionDelta(
      distanceChange: 0.0,
      angleChange: 0.0,
      balanceChange: 0.1,   # More stable when standing
      heightChange: 0.4      # Raise body position
    ),
    physicsEffect: PhysicsEffect(
      linearMomentum: 0.0,
      rotationalMomentum: 0.0,
      hipRotationDelta: 0.0,
      torsoRotationDelta: 0.0,
      weightShift: 0.0,
      commitmentLevel: 0.15,
      recoveryFramesOnMiss: 0,
      recoveryFramesOnHit: 0
    ),
    damageEffect: DamageEffect(
      directDamage: 0.0,
      fatigueInflicted: 0.0,
      targetLimb: none(LimbType),
      limbDamage: 0.0
    ),
    postureChange: some(plStanding),  # KEY: Changes posture to standing!
    styleOrigins: @["All"],
    followups: @["jab_left", "step_back", "teep_front"],
    limbsUsed: {LeftLeg, RightLeg},  # Uses legs to stand
    canCombine: false
  )

  result.prerequisites = proc(state: FightState, who: FighterID): bool =
    let fighter = if who == FighterA: state.a else: state.b
    # Can stand from crouched or grounded
    result = fighter.posture in {plCrouched, plGrounded} and fighter.pos.balance >= 0.3

  result.viabilityCheck = moveViability

  result.apply = proc(state: var FightState, who: FighterID) =
    var fighter = if who == FighterA: addr state.a else: addr state.b

    # Improve balance when standing
    applyBalanceChange(fighter[], 0.1)

    # STATE TRANSITION: Change posture to standing
    if result.postureChange.isSome:
      fighter[].posture = result.postureChange.get()

    state.sequenceLength += 1

# ============================================================================
# Initialization
# ============================================================================

proc initializeMoves*() =
  ## Register all basic moves
  registerMove(createJab("left", "Boxing"))
  registerMove(createJab("right", "Boxing"))
  registerMove(createCross())
  registerMove(createRoundhouseKick())
  registerMove(createTeep())
  registerMove(createClinchEntry())
  registerMove(createHipThrow())
  registerMove(createStepBack())
  registerMove(createBlockAndCounter())
  registerMove(createStepAndJab())

  # Posture-changing moves (state transitions)
  registerMove(createDuck())
  registerMove(createStandUp())

  echo "Registered ", ALL_MOVES.len, " moves"
