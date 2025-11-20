## Move Variants - Compare different martial art implementations of similar techniques
## Example: Wing Chun straight punch vs Boxing jab vs Karate gyaku-zuki
## All are "straight strikes" but differ in physics, efficiency, and tactical characteristics

import fight_types
import constraints
import moves
import tactical
import std/[tables, strformat, algorithm]

type
  MoveVariant* = object
    ## Tracks performance of a move variant across different scenarios
    move*: Move
    avgScore*: float
    bestScenarios*: seq[string]   # Where this variant excels
    worstScenarios*: seq[string]  # Where this variant fails

  VariantComparison* = object
    ## Comparison results for move variants
    category*: MoveCategory
    variants*: seq[MoveVariant]
    scenarios*: Table[string, seq[tuple[moveId: string, score: float]]]

# ============================================================================
# Example: Straight Strike Variants (3 martial arts)
# ============================================================================

proc createWingChunStraightPunch*(): Move =
  ## Wing Chun chain punch - minimal rotation, centerline focused
  ## Characteristics: Low energy, fast recovery, low commitment, repeatable
  result = Move(
    id: "wc_straight_punch",
    name: "Wing Chun Straight Punch",
    moveType: mtOffensive,
    category: mcStraightStrike,
    targets: @["vzNose", "vzThroat", "vzSolarPlexus"],
    energyCost: 0.08,      # Very efficient (structure-based)
    timeCost: 0.15,         # Fast
    reach: 0.65,
    height: High,
    angleBias: 0.0,         # Strictly centerline
    recoveryTime: 0.10,     # Quick recovery
    lethalPotential: 0.25,  # Not a knockout strike
    positionShift: PositionDelta(
      distanceChange: -0.05,  # Minimal forward
      angleChange: 0.0,
      balanceChange: 0.0,     # Maintains balance
      heightChange: 0.0
    ),
    physicsEffect: PhysicsEffect(
      linearMomentum: 0.15,        # Low momentum (structure, not muscle)
      rotationalMomentum: 0.0,     # NO rotation (key difference!)
      hipRotationDelta: 0.0,       # Hips stay square
      torsoRotationDelta: 5.0,     # Minimal torso
      weightShift: 0.03,           # Very little weight shift
      commitmentLevel: 0.08,       # Almost no commitment
      recoveryFramesOnMiss: 1,
      recoveryFramesOnHit: 1
    ),
    styleOrigins: @["Wing Chun"],
    followups: @["wc_straight_punch", "wc_straight_punch"],  # Can chain rapidly
    limbsUsed: {RightArm},
    canCombine: true,
    optionsCreated: 15,      # High options (can immediately continue)
    exposureRisk: 0.12       # Very safe
  )

  result.prerequisites = proc(state: FightState, who: FighterID): bool =
    let fighter = if who == FighterA: state.a else: state.b
    result = fighter.rightArm.free and
             state.distance in [Short, Medium] and
             fighter.pos.balance > 0.3 and
             fighter.fatigue < 0.9

  result.apply = proc(state: var FightState, who: FighterID) =
    var fighter = if who == FighterA: addr state.a else: addr state.b
    var opponent = if who == FighterA: addr state.b else: addr state.a

    fighter.momentum.linear += 0.15
    fighter.biomech.torsoRotation += 5.0
    fighter.biomech.weightDistribution += 0.03
    fighter.fatigue = min(1.0, fighter.fatigue + 0.05)

    if fighter.pos.balance > 0.6:
      opponent.damage += 0.015
      opponent.pos.balance -= 0.03

proc createBoxingJab*(): Move =
  ## Boxing jab - moderate rotation, footwork integrated
  ## Characteristics: Balanced energy/power, good setup, moderate commitment
  result = Move(
    id: "boxing_jab",
    name: "Boxing Jab",
    moveType: mtOffensive,
    category: mcStraightStrike,
    targets: @["vzNose", "vzJaw", "vzEyes"],
    energyCost: 0.12,       # More energy than WC (uses legs/hips)
    timeCost: 0.18,         # Slightly slower (footwork involved)
    reach: 0.75,            # Longer reach (step included)
    height: High,
    angleBias: 0.0,
    recoveryTime: 0.12,
    lethalPotential: 0.30,  # Can set up KO
    positionShift: PositionDelta(
      distanceChange: -0.12,  # More forward motion
      angleChange: 0.0,
      balanceChange: -0.03,
      heightChange: 0.0
    ),
    physicsEffect: PhysicsEffect(
      linearMomentum: 0.25,        # More momentum
      rotationalMomentum: 0.0,
      hipRotationDelta: 8.0,       # Some hip rotation
      torsoRotationDelta: 12.0,    # More torso
      weightShift: 0.08,           # Weight shifts forward
      commitmentLevel: 0.15,       # Moderate commitment
      recoveryFramesOnMiss: 2,
      recoveryFramesOnHit: 1
    ),
    styleOrigins: @["Boxing"],
    followups: @["boxing_cross", "boxing_hook", "boxing_jab"],
    limbsUsed: {LeftArm},
    canCombine: true,
    optionsCreated: 12,
    exposureRisk: 0.18
  )

  result.prerequisites = proc(state: FightState, who: FighterID): bool =
    let fighter = if who == FighterA: state.a else: state.b
    result = fighter.leftArm.free and
             state.distance in [Short, Medium] and
             fighter.pos.balance > 0.4 and
             fighter.fatigue < 0.85

  result.apply = proc(state: var FightState, who: FighterID) =
    var fighter = if who == FighterA: addr state.a else: addr state.b
    var opponent = if who == FighterA: addr state.b else: addr state.a

    fighter.momentum.linear += 0.25
    fighter.biomech.hipRotation += 8.0
    fighter.biomech.torsoRotation += 12.0
    fighter.biomech.weightDistribution += 0.08
    fighter.fatigue = min(1.0, fighter.fatigue + 0.08)

    if fighter.pos.balance > 0.6:
      opponent.damage += 0.02
      opponent.pos.balance -= 0.04

proc createKarateGyakuZuki*(): Move =
  ## Karate reverse punch - maximum rotation, full body commitment
  ## Characteristics: High power, high commitment, longer recovery
  result = Move(
    id: "karate_gyaku_zuki",
    name: "Karate Gyaku-Zuki (Reverse Punch)",
    moveType: mtOffensive,
    category: mcStraightStrike,
    targets: @["vzSolarPlexus", "vzJaw", "vzNose"],
    energyCost: 0.18,       # Most energy (full body)
    timeCost: 0.22,         # Slowest (chamber + thrust)
    reach: 0.70,
    height: High,
    angleBias: 0.0,
    recoveryTime: 0.18,     # Longest recovery
    lethalPotential: 0.45,  # Highest power
    positionShift: PositionDelta(
      distanceChange: -0.15,  # Most forward
      angleChange: 0.0,
      balanceChange: -0.08,   # Most balance risk
      heightChange: 0.0
    ),
    physicsEffect: PhysicsEffect(
      linearMomentum: 0.40,        # Maximum momentum
      rotationalMomentum: 0.0,
      hipRotationDelta: 45.0,      # FULL hip rotation (key difference!)
      torsoRotationDelta: 35.0,    # Maximum torso
      weightShift: 0.25,           # Significant weight transfer
      commitmentLevel: 0.40,       # High commitment
      recoveryFramesOnMiss: 4,     # Bad if misses
      recoveryFramesOnHit: 2
    ),
    styleOrigins: @["Karate", "Taekwondo"],
    followups: @["karate_front_kick"],  # Fewer options after
    limbsUsed: {RightArm},
    canCombine: false,       # Too committed to combine
    optionsCreated: 6,       # Lower options (committed)
    exposureRisk: 0.35       # Significant exposure
  )

  result.prerequisites = proc(state: FightState, who: FighterID): bool =
    let fighter = if who == FighterA: state.a else: state.b
    result = fighter.rightArm.free and
             state.distance in [Short, Medium] and
             fighter.pos.balance > 0.6 and    # Needs good balance
             fighter.fatigue < 0.7 and         # Can't be too tired
             fighter.momentum.rotational.abs < 20.0  # Can't already be rotating

  result.apply = proc(state: var FightState, who: FighterID) =
    var fighter = if who == FighterA: addr state.a else: addr state.b
    var opponent = if who == FighterA: addr state.b else: addr state.a

    fighter.momentum.linear += 0.40
    fighter.biomech.hipRotation += 45.0
    fighter.biomech.torsoRotation += 35.0
    fighter.biomech.weightDistribution += 0.25
    fighter.biomech.recovering = true
    fighter.biomech.recoveryFrames = 4
    fighter.fatigue = min(1.0, fighter.fatigue + 0.12)

    if fighter.pos.balance > 0.7:
      opponent.damage += 0.04  # Highest damage
      opponent.pos.balance -= 0.08

# ============================================================================
# Arc Strike Variants (Round Kick)
# ============================================================================

proc createMuayThaiRoundKick*(): Move =
  ## Muay Thai round kick - hip rotation first, shin contact
  ## Characteristics: Maximum power, baseball bat swing, high commitment
  result = Move(
    id: "muay_thai_round_kick",
    name: "Muay Thai Round Kick",
    moveType: mtOffensive,
    category: mcArcStrike,
    targets: @["vzThighMuscle", "vzFloatingRibs", "vzLiver"],
    energyCost: 0.25,
    timeCost: 0.40,
    reach: 0.95,
    height: Mid,
    angleBias: 45.0,
    recoveryTime: 0.30,
    lethalPotential: 0.60,  # Can finish fight
    positionShift: PositionDelta(
      distanceChange: 0.0,
      angleChange: 30.0,
      balanceChange: -0.20,
      heightChange: 0.0
    ),
    physicsEffect: PhysicsEffect(
      linearMomentum: 0.15,
      rotationalMomentum: 60.0,    # Maximum rotation
      hipRotationDelta: 90.0,      # Full hip turn
      torsoRotationDelta: 45.0,
      weightShift: -0.40,
      commitmentLevel: 0.60,       # Very committed
      recoveryFramesOnMiss: 6,
      recoveryFramesOnHit: 3
    ),
    styleOrigins: @["Muay Thai"],
    followups: @["clinch_entry"],
    limbsUsed: {RightLeg},
    canCombine: false,
    optionsCreated: 4,
    exposureRisk: 0.55
  )

  result.prerequisites = proc(state: FightState, who: FighterID): bool =
    let fighter = if who == FighterA: state.a else: state.b
    result = fighter.rightLeg.free and
             state.distance in [Short, Medium] and
             fighter.pos.balance > 0.7 and
             fighter.fatigue < 0.6

  result.apply = proc(state: var FightState, who: FighterID) =
    var fighter = if who == FighterA: addr state.a else: addr state.b
    var opponent = if who == FighterA: addr state.b else: addr state.a

    fighter.momentum.rotational += 60.0
    fighter.biomech.hipRotation += 90.0
    fighter.biomech.torsoRotation += 45.0
    fighter.biomech.weightDistribution -= 0.40
    fighter.biomech.recovering = true
    fighter.biomech.recoveryFrames = 6
    fighter.fatigue = min(1.0, fighter.fatigue + 0.18)

    if fighter.pos.balance > 0.7:
      opponent.damage += 0.08  # Very high damage
      opponent.pos.balance -= 0.15

proc createKarateMawashiGeri*(): Move =
  ## Karate roundhouse - snap kick, knee extension, lighter contact
  ## Characteristics: Faster, less power, better recovery
  result = Move(
    id: "karate_mawashi_geri",
    name: "Karate Mawashi-Geri (Roundhouse)",
    moveType: mtOffensive,
    category: mcArcStrike,
    targets: @["vzThighMuscle", "vzFloatingRibs", "vzJaw"],
    energyCost: 0.18,       # Less energy (snap, not swing)
    timeCost: 0.32,         # Faster
    reach: 0.90,
    height: Mid,
    angleBias: 35.0,
    recoveryTime: 0.22,     # Faster recovery
    lethalPotential: 0.40,  # Less power
    positionShift: PositionDelta(
      distanceChange: 0.0,
      angleChange: 25.0,
      balanceChange: -0.12,
      heightChange: 0.0
    ),
    physicsEffect: PhysicsEffect(
      linearMomentum: 0.10,
      rotationalMomentum: 40.0,    # Less rotation
      hipRotationDelta: 60.0,      # Moderate hip
      torsoRotationDelta: 30.0,
      weightShift: -0.25,
      commitmentLevel: 0.35,       # Less committed
      recoveryFramesOnMiss: 3,     # Better recovery
      recoveryFramesOnHit: 2
    ),
    styleOrigins: @["Karate", "Taekwondo"],
    followups: @["karate_gyaku_zuki", "boxing_jab"],
    limbsUsed: {RightLeg},
    canCombine: false,
    optionsCreated: 8,       # More options
    exposureRisk: 0.38       # Less exposure
  )

  result.prerequisites = proc(state: FightState, who: FighterID): bool =
    let fighter = if who == FighterA: state.a else: state.b
    result = fighter.rightLeg.free and
             state.distance in [Short, Medium] and
             fighter.pos.balance > 0.5 and
             fighter.fatigue < 0.75

  result.apply = proc(state: var FightState, who: FighterID) =
    var fighter = if who == FighterA: addr state.a else: addr state.b
    var opponent = if who == FighterA: addr state.b else: addr state.a

    fighter.momentum.rotational += 40.0
    fighter.biomech.hipRotation += 60.0
    fighter.biomech.torsoRotation += 30.0
    fighter.biomech.weightDistribution -= 0.25
    fighter.biomech.recovering = true
    fighter.biomech.recoveryFrames = 3
    fighter.fatigue = min(1.0, fighter.fatigue + 0.12)

    if fighter.pos.balance > 0.6:
      opponent.damage += 0.045  # Moderate damage
      opponent.pos.balance -= 0.08

# ============================================================================
# Variant Comparison System
# ============================================================================

proc compareVariants*(
  moves: seq[Move],
  scenarios: seq[tuple[state: FightState, who: FighterID, name: string]]
): VariantComparison =
  ## Compare move variants across different scenarios
  ## Returns which variant is optimal in each scenario

  result.scenarios = initTable[string, seq[tuple[moveId: string, score: float]]]()

  for scenario in scenarios:
    var scores: seq[tuple[moveId: string, score: float]] = @[]

    for move in moves:
      # Check if move is viable in this scenario
      if move.prerequisites(scenario.state, scenario.who):
        # Score it tactically
        let viableMoves = @[move]  # Simplified for comparison
        let score = scoreMoveTactically(move, scenario.state, scenario.who, viableMoves)
        scores.add((moveId: move.id, score: score))

    # Sort by score descending
    scores.sort(proc(a, b: auto): int =
      if b.score > a.score: 1
      elif b.score < a.score: -1
      else: 0
    )

    result.scenarios[scenario.name] = scores

proc printVariantComparison*(comparison: VariantComparison) =
  ## Print human-readable comparison results
  echo "\n" & "═".repeat(70)
  echo "MOVE VARIANT COMPARISON"
  echo "═".repeat(70)

  for scenario, scores in comparison.scenarios:
    echo fmt"\nScenario: {scenario}"
    echo "─".repeat(70)

    if scores.len == 0:
      echo "  No viable moves in this scenario"
      continue

    for i, s in scores:
      let rank = i + 1
      let emoji = if rank == 1: "🥇" elif rank == 2: "🥈" elif rank == 3: "🥉" else: "  "
      echo fmt"{emoji} {rank}. {s.moveId:30} Score: {s.score:.4f}"

proc createTestScenarios*(): seq[tuple[state: FightState, who: FighterID, name: string]] =
  ## Create various test scenarios to compare variants
  result = @[]

  # Scenario 1: Fresh fighters, medium range
  var fresh = createInitialState()
  result.add((state: fresh, who: FighterA, name: "Fresh fighters, medium range"))

  # Scenario 2: High fatigue (60%), medium range
  var tired = createInitialState()
  tired.a.fatigue = 0.60
  result.add((state: tired, who: FighterA, name: "60% fatigued, medium range"))

  # Scenario 3: Close range, balanced
  var closeRange = createInitialState()
  closeRange.distance = Short
  result.add((state: closeRange, who: FighterA, name: "Close range, fresh"))

  # Scenario 4: Unbalanced (40% balance)
  var unbalanced = createInitialState()
  unbalanced.a.pos.balance = 0.40
  result.add((state: unbalanced, who: FighterA, name: "Low balance (40%), medium range"))

  # Scenario 5: High fatigue + unbalanced
  var exhausted = createInitialState()
  exhausted.a.fatigue = 0.75
  exhausted.a.pos.balance = 0.45
  result.add((state: exhausted, who: FighterA, name: "Exhausted (75% fatigue, 45% balance)"))

when isMainModule:
  echo "=== Martial Arts Variant Comparison ==="
  echo ""

  # Register variants
  let straightPunchVariants = @[
    createWingChunStraightPunch(),
    createBoxingJab(),
    createKarateGyakuZuki()
  ]

  let roundKickVariants = @[
    createMuayThaiRoundKick(),
    createKarateMawashiGeri()
  ]

  # Create test scenarios
  let scenarios = createTestScenarios()

  echo "Testing Straight Punch Variants:"
  echo "  - Wing Chun Straight Punch (low energy, no rotation, high options)"
  echo "  - Boxing Jab (balanced, some rotation, good setup)"
  echo "  - Karate Gyaku-Zuki (high power, full rotation, committed)"

  let straightComparison = compareVariants(straightPunchVariants, scenarios)
  printVariantComparison(straightComparison)

  echo "\n\n"
  echo "Testing Round Kick Variants:"
  echo "  - Muay Thai Round Kick (hip-first, maximum power, high commitment)"
  echo "  - Karate Mawashi-Geri (snap kick, faster recovery, less power)"

  let kickComparison = compareVariants(roundKickVariants, scenarios)
  printVariantComparison(kickComparison)
