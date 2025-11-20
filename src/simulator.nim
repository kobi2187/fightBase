## Forward simulation engine

import fight_types
import constraints
import moves
import state_storage
import fight_display
import std/[random, options, strformat]

type
  SimulationConfig* = object
    maxSequenceLength*: int     # Stop after this many moves
    recordAllStates*: bool       # Record every state to DB
    logUnknownStates*: bool      # Log states with no viable moves
    verbose*: bool               # Print progress

  SimulationResult* = object
    finalState*: RuntimeFightState
    totalMoves*: int
    winner*: Option[FighterID]
    reachedUnknown*: bool
    reason*: string

# ============================================================================
# Helper functions for runtime state
# ============================================================================

proc getOverlay*(state: RuntimeFightState, who: FighterID): var RuntimeOverlay =
  ## Get overlay for specified fighter
  if who == FighterA:
    return state.overlayA
  else:
    return state.overlayB

proc getOpponentOverlay*(state: RuntimeFightState, who: FighterID): var RuntimeOverlay =
  ## Get overlay for opponent
  if who == FighterA:
    return state.overlayB
  else:
    return state.overlayA

# ============================================================================
# Initial state creation
# ============================================================================

proc createInitialState*(): RuntimeFightState =
  ## Create a standard initial fighting position
  let position = FightState(
    a: Fighter(
      pos: Position3D(
        x: -1.5, y: 0.0, z: 0.0,
        facing: 90.0,
        stance: skOrthodox,
        balance: 1.0
      ),
      leftArm: LimbPosition(free: true, extended: false, angle: 0.0),
      rightArm: LimbPosition(free: true, extended: false, angle: 0.0),
      leftLeg: LimbPosition(free: true, extended: false, angle: 0.0),
      rightLeg: LimbPosition(free: true, extended: false, angle: 0.0),
      liveSide: Centerline,
      control: None,
      momentum: Momentum(linear: 0.0, rotational: 0.0, decayRate: 0.5),
      biomech: BiomechanicalState(
        hipRotation: 0.0,
        torsoRotation: 0.0,
        weightDistribution: 0.5,
        recovering: false,
        recoveryFrames: 0
      )
    ),
    b: Fighter(
      pos: Position3D(
        x: 1.5, y: 0.0, z: 0.0,
        facing: 270.0,
        stance: skOrthodox,
        balance: 1.0
      ),
      leftArm: LimbPosition(free: true, extended: false, angle: 0.0),
      rightArm: LimbPosition(free: true, extended: false, angle: 0.0),
      leftLeg: LimbPosition(free: true, extended: false, angle: 0.0),
      rightLeg: LimbPosition(free: true, extended: false, angle: 0.0),
      liveSide: Centerline,
      control: None,
      momentum: Momentum(linear: 0.0, rotational: 0.0, decayRate: 0.5),
      biomech: BiomechanicalState(
        hipRotation: 0.0,
        torsoRotation: 0.0,
        weightDistribution: 0.5,
        recovering: false,
        recoveryFrames: 0
      )
    ),
    distance: Medium,
    sequenceLength: 0,
    terminal: false,
    winner: none(FighterID)
  )

  result = RuntimeFightState(
    position: position,
    overlayA: createFreshOverlay(),
    overlayB: createFreshOverlay()
  )
  result.position.stateHash = computeStateHash(result.position)

proc createRandomInitialState*(): RuntimeFightState =
  ## Create a randomized initial state (for variety)
  result = createInitialState()

  # Randomize stances
  if rand(1.0) > 0.5:
    result.position.a.pos.stance = skSouthpaw
  if rand(1.0) > 0.5:
    result.position.b.pos.stance = skSouthpaw

  # Randomize distance
  let r = rand(1.0)
  if r < 0.2:
    result.position.distance = Short
  elif r < 0.6:
    result.position.distance = Medium
  else:
    result.position.distance = Long

  # Slight overlay variation (fatigue only, start fresh otherwise)
  result.overlayA.fatigue = rand(0.1)
  result.overlayB.fatigue = rand(0.1)

  # Slight balance variation
  result.position.a.pos.balance = 0.9 + rand(0.1)
  result.position.b.pos.balance = 0.9 + rand(0.1)

  result.position.stateHash = computeStateHash(result.position)

# ============================================================================
# Single fight simulation
# ============================================================================

proc simulateFight*(config: SimulationConfig, db: StateDB = nil): SimulationResult =
  ## Run a single fight simulation
  var state = createRandomInitialState()
  var currentFighter = FighterA
  var moveCount = 0
  var unknownStateReached = false

  if config.verbose:
    echo "\n=== Starting fight simulation ==="
    echo toCompactRepr(state.position)

  while moveCount < config.maxSequenceLength:
    # Record state (position only)
    if db != nil and config.recordAllStates:
      discard db.recordState(state.position)

    # Check terminal condition
    if isTerminalPosition(state.position):
      state.position.terminal = true
      state.position.winner = some(determineWinner(state.position))
      if db != nil:
        db.recordTerminalState(state.position, "Natural termination")
      break

    # Build action sequence for current fighter's turn
    var actionSeq = createEmptySequence()
    var turnMoveCount = 0

    # Keep adding moves to sequence until time runs out or no compatible moves
    while true:
      # Get viable moves for current position
      let positionMoves = viableMoves(state.position, currentFighter)

      # Filter by overlay viability
      var viable: seq[Move] = @[]
      let overlay = state.getOverlay(currentFighter)
      for move in positionMoves:
        # Check if move is viable given fatigue/damage
        if move.viabilityCheck.isNil or move.viabilityCheck(overlay, move) > 0.0:
          viable.add(move)

      if viable.len == 0:
        # No viable moves at all
        if turnMoveCount == 0:
          # Couldn't even start a turn - unknown state
          if config.verbose:
            echo fmt"\n[!] Unknown state reached at move {moveCount}"
            echo toAnalysisStr(state.position)

          if db != nil and config.logUnknownStates:
            db.logUnknownState(state.position, fmt"No viable moves for {currentFighter} at move {moveCount}")

          unknownStateReached = true
          break  # Exit inner while
        else:
          # Already did some moves, end turn normally
          break  # Exit inner while

      # Filter for moves that can be added to current sequence
      var compatibleMoves: seq[Move] = @[]
      for move in viable:
        if canAddToSequence(actionSeq, move):
          compatibleMoves.add(move)

      if compatibleMoves.len == 0:
        # No more moves can be added to sequence
        break  # Exit inner while

      # Select random compatible move
      let selectedMove = compatibleMoves[rand(compatibleMoves.len - 1)]

      # Add to sequence
      addMoveToSequence(actionSeq, selectedMove)
      inc turnMoveCount

      if config.verbose:
        if turnMoveCount == 1:
          echo fmt"\n[{moveCount}] {currentFighter}:"
        echo fmt"  → {selectedMove.name} (time: {selectedMove.timeCost:.2f}s, energy: {selectedMove.energyCost:.2f})"

      # Store old hash for first move of turn
      let oldHash = if turnMoveCount == 1: state.position.stateHash else: ""

      # Apply move to position
      selectedMove.apply(state.position, currentFighter)

      # Apply overlay effects
      var attackerOverlay = state.getOverlay(currentFighter)
      var defenderOverlay = state.getOpponentOverlay(currentFighter)

      # Increase attacker fatigue
      attackerOverlay.fatigue = min(1.0, attackerOverlay.fatigue + selectedMove.energyCost)

      # Apply damage to defender if applicable
      if selectedMove.damageEffect.directDamage > 0:
        defenderOverlay.damage = min(1.0, defenderOverlay.damage + selectedMove.damageEffect.directDamage)

      # Apply fatigue to defender
      if selectedMove.damageEffect.fatigueInflicted > 0:
        defenderOverlay.fatigue = min(1.0, defenderOverlay.fatigue + selectedMove.damageEffect.fatigueInflicted)

      # Apply limb damage if applicable
      if selectedMove.damageEffect.targetLimb.isSome:
        let limb = selectedMove.damageEffect.targetLimb.get
        case limb:
        of LeftArm:
          defenderOverlay.leftArmDamage = min(1.0, defenderOverlay.leftArmDamage + selectedMove.damageEffect.limbDamage)
        of RightArm:
          defenderOverlay.rightArmDamage = min(1.0, defenderOverlay.rightArmDamage + selectedMove.damageEffect.limbDamage)
        of LeftLeg:
          defenderOverlay.leftLegDamage = min(1.0, defenderOverlay.leftLegDamage + selectedMove.damageEffect.limbDamage)
        of RightLeg:
          defenderOverlay.rightLegDamage = min(1.0, defenderOverlay.rightLegDamage + selectedMove.damageEffect.limbDamage)

      # Recompute hash (position only)
      state.position.stateHash = computeStateHash(state.position)

      # Record transition (only for first move of turn for now)
      if db != nil and turnMoveCount == 1:
        db.recordTransition(oldHash, state.position.stateHash, selectedMove.id, currentFighter)

      inc moveCount

      # Random chance to end turn early (70% continue, 30% stop)
      # This prevents always maxing out the action sequence
      if rand(1.0) < 0.3:
        break  # Exit inner while

    # Check if unknown state was reached
    if unknownStateReached:
      break  # Exit outer while

    if config.verbose and turnMoveCount > 0:
      echo fmt"  Total turn time: {actionSeq.totalTimeCost:.2f}s, energy: {actionSeq.totalEnergyCost:.2f}"
      echo fmt"  Overlays - A: fat={state.overlayA.fatigue:.2f} dmg={state.overlayA.damage:.2f} | B: fat={state.overlayB.fatigue:.2f} dmg={state.overlayB.damage:.2f}"

    # Switch fighters
    currentFighter = if currentFighter == FighterA: FighterB else: FighterA

    if config.verbose and moveCount mod 10 == 0:
      echo fmt"  [{moveCount}] {toCompactRepr(state.position)}"

  # Determine result
  result = SimulationResult(
    finalState: state,
    totalMoves: moveCount,
    winner: state.position.winner,
    reachedUnknown: unknownStateReached,
    reason:
      if unknownStateReached: "Unknown state"
      elif state.position.terminal: fmt"Terminal: {state.position.winner.get()} wins"
      else: "Max sequence length"
  )

  if config.verbose:
    echo "\n=== Fight ended ==="
    echo fmt"Moves: {moveCount} | Reason: {result.reason}"
    if state.position.winner.isSome:
      echo fmt"Winner: {state.position.winner.get()}"
    echo toAnalysisStr(state.position)

# ============================================================================
# Batch simulation
# ============================================================================

proc runBatchSimulation*(numFights: int, config: SimulationConfig,
                        dbFilename: string = "fight_states.db"): tuple[
                          completed: int, unknown: int, terminal: int] =
  ## Run many simulations and collect data
  echo fmt"\n=== Running {numFights} fight simulations ==="
  echo fmt"Config: maxLength={config.maxSequenceLength}, recordAll={config.recordAllStates}"

  let db = openStateDB(dbFilename)
  defer: db.close()

  var stats = (completed: 0, unknown: 0, terminal: 0)

  for i in 1..numFights:
    let result = simulateFight(config, db)
    inc stats.completed

    if result.reachedUnknown:
      inc stats.unknown
    if result.finalState.position.terminal:
      inc stats.terminal

    if i mod 100 == 0:
      echo fmt"[{i}/{numFights}] States: {db.getStateCount()}, Unknown: {db.getUnknownStateCount()}, Terminal: {db.getTerminalStateCount()}"

  echo "\n=== Batch simulation complete ==="
  echo db.getStats()

  result = stats

# ============================================================================
# Interactive simulation
# ============================================================================

proc runInteractiveFight*(): SimulationResult =
  ## Run a single fight with detailed output for testing
  let config = SimulationConfig(
    maxSequenceLength: 200,
    recordAllStates: false,
    logUnknownStates: false,
    verbose: true
  )

  result = simulateFight(config, nil)
