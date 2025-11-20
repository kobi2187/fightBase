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

proc applyFatigue*(fighter: var Fighter, cost: float) =
  fighter.fatigue = min(1.0, fighter.fatigue + cost)

proc applyDamage*(fighter: var Fighter, amount: float) =
  fighter.damage = min(1.0, fighter.damage + amount)

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

proc extendLimb*(limb: var LimbStatus) =
  limb.extended = true
  limb.free = false

proc retractLimb*(limb: var LimbStatus) =
  limb.extended = false
  limb.free = true

# ============================================================================
# STRIKING MOVES
# ============================================================================

proc createJab*(side: string = "left", origin: string = "Boxing"): Move =
  ## Lead hand straight punch
  let moveId = "jab_" & side & "_" & origin.toLowerAscii()
  let isLeft = side == "left"
  let limbUsed = if isLeft: {LeftArm} else: {RightArm}

  result = Move(
    id: moveId,
    name: side & " Jab (" & origin & ")",
    category: Straight,
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
    styleOrigins: @[origin],
    followups: @["cross_right", "hook_left", "step_back"],
    limbsUsed: limbUsed,
    canCombine: true  # Can be combined with other moves
  )

  # Set up prerequisite closure
  result.prerequisites = proc(state: FightState, who: FighterID): bool =
    let fighter = if who == FighterA: state.a else: state.b
    # Need free arm
    let armFree = if isLeft: fighter.leftArm.free else: fighter.rightArm.free
    result = armFree and fighter.fatigue < 0.9 and fighter.pos.balance >= 0.3

  # Set up application closure
  result.apply = proc(state: var FightState, who: FighterID) =
    var attacker = if who == FighterA: addr state.a else: addr state.b
    var defender = if who == FighterA: addr state.b else: addr state.a

    # Apply fatigue
    applyFatigue(attacker[], 0.05)

    # Extend arm temporarily
    if isLeft:
      extendLimb(attacker[].leftArm)
    else:
      extendLimb(attacker[].rightArm)

    # Chance to land based on opponent state
    if rand(1.0) > defender[].pos.balance * 0.5:
      applyDamage(defender[], 0.05)
      applyBalanceChange(defender[], -0.05)

    # Retract
    if isLeft:
      retractLimb(attacker[].leftArm)
    else:
      retractLimb(attacker[].rightArm)

    state.sequenceLength += 1

proc createCross*(): Move =
  ## Rear hand power punch
  result = Move(
    id: "cross_right",
    name: "Cross (Boxing/Karate)",
    category: Straight,
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
    styleOrigins: @["Boxing", "Karate", "MMA"],
    followups: @["hook_left", "step_back", "clinch_entry"],
    limbsUsed: {RightArm},
    canCombine: true
  )

  result.prerequisites = proc(state: FightState, who: FighterID): bool =
    let fighter = if who == FighterA: state.a else: state.b
    result = fighter.rightArm.free and fighter.fatigue < 0.9 and fighter.pos.balance >= 0.3

  result.apply = proc(state: var FightState, who: FighterID) =
    var attacker = if who == FighterA: addr state.a else: addr state.b
    var defender = if who == FighterA: addr state.b else: addr state.a

    applyFatigue(attacker[], 0.12)
    extendLimb(attacker[].rightArm)

    # More power, better hit chance
    if rand(1.0) > defender[].pos.balance * 0.4:
      applyDamage(defender[], 0.15)
      applyBalanceChange(defender[], -0.15)

    retractLimb(attacker[].rightArm)
    state.sequenceLength += 1

proc createRoundhouseKick*(): Move =
  ## Circular kick (Muay Thai, Karate, TKD)
  result = Move(
    id: "roundhouse_right",
    name: "Roundhouse Kick (Muay Thai)",
    category: Arc,
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
    styleOrigins: @["Muay Thai", "Karate", "Taekwondo"],
    followups: @["step_back", "clinch_entry", "switch_stance"],
    limbsUsed: {RightLeg, LeftLeg},  # Uses both legs (standing leg + kicking leg)
    canCombine: false  # Cannot combine with other moves (too committed)
  )

  result.prerequisites = proc(state: FightState, who: FighterID): bool =
    let fighter = if who == FighterA: state.a else: state.b
    result = fighter.rightLeg.free and fighter.pos.balance >= 0.6 and fighter.fatigue < 0.8

  result.apply = proc(state: var FightState, who: FighterID) =
    var attacker = if who == FighterA: addr state.a else: addr state.b
    var defender = if who == FighterA: addr state.b else: addr state.a

    applyFatigue(attacker[], 0.25)
    applyBalanceChange(attacker[], -0.2)
    extendLimb(attacker[].rightLeg)

    # High damage if lands
    if rand(1.0) > defender[].pos.balance * 0.6:
      applyDamage(defender[], 0.25)
      applyBalanceChange(defender[], -0.2)
    else:
      # Miss costs more energy
      applyFatigue(attacker[], 0.1)

    retractLimb(attacker[].rightLeg)
    state.sequenceLength += 1

proc createTeep*(): Move =
  ## Front push kick (Muay Thai)
  result = Move(
    id: "teep_front",
    name: "Teep (Muay Thai)",
    category: Push,
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
    styleOrigins: @["Muay Thai"],
    followups: @["step_forward", "roundhouse_right", "retreat"],
    limbsUsed: {LeftLeg, RightLeg},  # Uses both legs
    canCombine: false  # Cannot combine with other moves
  )

  result.prerequisites = proc(state: FightState, who: FighterID): bool =
    let fighter = if who == FighterA: state.a else: state.b
    result = fighter.leftLeg.free and fighter.fatigue < 0.9 and fighter.pos.balance >= 0.5

  result.apply = proc(state: var FightState, who: FighterID) =
    var attacker = if who == FighterA: addr state.a else: addr state.b
    var defender = if who == FighterA: addr state.b else: addr state.a

    applyFatigue(attacker[], 0.15)

    # Creates distance
    changeDistance(state, 0.4)
    applyBalanceChange(defender[], -0.15)

    state.sequenceLength += 1

# ============================================================================
# GRAPPLING MOVES
# ============================================================================

proc createClinchEntry*(): Move =
  ## Enter clinch position
  result = Move(
    id: "clinch_entry",
    name: "Clinch Entry (Muay Thai/Wrestling)",
    category: Clinch,
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
    styleOrigins: @["Muay Thai", "Wrestling", "Judo"],
    followups: @["knee_strike", "throw_hip", "break_clinch"],
    limbsUsed: {LeftArm, RightArm},  # Uses both arms
    canCombine: false  # Cannot combine - full commitment
  )

  result.prerequisites = proc(state: FightState, who: FighterID): bool =
    let fighter = if who == FighterA: state.a else: state.b
    result = state.distance in {Short, Medium} and
             hasFreeLimbs(fighter, 2) and
             fighter.fatigue < 0.85

  result.apply = proc(state: var FightState, who: FighterID) =
    var attacker = if who == FighterA: addr state.a else: addr state.b

    applyFatigue(attacker[], 0.2)
    attacker[].control = Clinch
    state.distance = Contact

    state.sequenceLength += 1

proc createHipThrow*(): Move =
  ## Basic hip throw (Judo/Wrestling)
  result = Move(
    id: "throw_hip",
    name: "Hip Throw (Judo)",
    category: Throw,
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
             opponent.pos.balance < 0.7 and
             fighter.fatigue < 0.75

  result.apply = proc(state: var FightState, who: FighterID) =
    var attacker = if who == FighterA: addr state.a else: addr state.b
    var defender = if who == FighterA: addr state.b else: addr state.a

    applyFatigue(attacker[], 0.35)

    # High success when opponent off-balance
    if defender[].pos.balance < 0.5 or rand(1.0) < 0.6:
      # Successful throw
      defender[].pos.balance = 0.1
      applyDamage(defender[], 0.2)
      attacker[].control = Mount
    else:
      # Failed attempt
      applyFatigue(attacker[], 0.15)
      applyBalanceChange(attacker[], -0.2)

    state.sequenceLength += 1

# ============================================================================
# DEFENSIVE MOVES
# ============================================================================

proc createStepBack*(): Move =
  ## Create distance
  result = Move(
    id: "step_back",
    name: "Step Back",
    category: Displacement,
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
    styleOrigins: @["Boxing", "Karate", "All"],
    followups: @["jab_left", "teep_front", "circle_left"],
    limbsUsed: {LeftLeg, RightLeg},  # Uses legs for movement
    canCombine: true  # Can step back while doing something else
  )

  result.prerequisites = proc(state: FightState, who: FighterID): bool =
    let fighter = if who == FighterA: state.a else: state.b
    result = fighter.fatigue < 0.9 and fighter.pos.balance >= 0.4

  result.apply = proc(state: var FightState, who: FighterID) =
    var fighter = if who == FighterA: addr state.a else: addr state.b

    applyFatigue(fighter[], 0.08)
    changeDistance(state, 0.5)
    applyBalanceChange(fighter[], 0.05)

    state.sequenceLength += 1

# ============================================================================
# COMBINATION MOVES (Simultaneous Actions)
# ============================================================================

proc createBlockAndCounter*(): Move =
  ## Block with left arm while counter-punching with right (Wing Chun / Krav Maga)
  result = Move(
    id: "block_counter_right",
    name: "Block-and-Counter (Wing Chun)",
    category: Counter,
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
    styleOrigins: @["Wing Chun", "Krav Maga", "JKD"],
    followups: @["trap_strike", "step_back"],
    limbsUsed: {LeftArm, RightArm},  # Uses both arms simultaneously
    canCombine: false  # This IS the combination
  )

  result.prerequisites = proc(state: FightState, who: FighterID): bool =
    let fighter = if who == FighterA: state.a else: state.b
    result = fighter.leftArm.free and fighter.rightArm.free and
             fighter.fatigue < 0.85 and fighter.pos.balance >= 0.5

  result.apply = proc(state: var FightState, who: FighterID) =
    var attacker = if who == FighterA: addr state.a else: addr state.b
    var defender = if who == FighterA: addr state.b else: addr state.a

    applyFatigue(attacker[], 0.15)

    # Block reduces incoming damage (defensive benefit)
    # Counter punch has chance to land
    if rand(1.0) > defender[].pos.balance * 0.55:
      applyDamage(defender[], 0.12)
      applyBalanceChange(defender[], -0.08)

    state.sequenceLength += 1

proc createStepAndJab*(): Move =
  ## Step forward while jabbing (efficient combination)
  result = Move(
    id: "step_jab_combo",
    name: "Step-and-Jab",
    category: Straight,
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
    styleOrigins: @["Boxing", "Karate", "All"],
    followups: @["cross_right", "step_back"],
    limbsUsed: {LeftArm, LeftLeg, RightLeg},  # Arm + footwork
    canCombine: false  # This IS the combination
  )

  result.prerequisites = proc(state: FightState, who: FighterID): bool =
    let fighter = if who == FighterA: state.a else: state.b
    result = fighter.leftArm.free and
             fighter.fatigue < 0.85 and fighter.pos.balance >= 0.6

  result.apply = proc(state: var FightState, who: FighterID) =
    var attacker = if who == FighterA: addr state.a else: addr state.b
    var defender = if who == FighterA: addr state.b else: addr state.a

    applyFatigue(attacker[], 0.1)
    changeDistance(state, -0.3)  # Close distance

    # Better chance to land due to forward momentum
    if rand(1.0) > defender[].pos.balance * 0.45:
      applyDamage(defender[], 0.08)
      applyBalanceChange(defender[], -0.06)

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

  # Combination moves
  registerMove(createBlockAndCounter())
  registerMove(createStepAndJab())

  echo "Registered ", ALL_MOVES.len, " moves"
