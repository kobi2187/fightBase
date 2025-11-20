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
    finalState*: FightState
    totalMoves*: int
    winner*: Option[FighterID]
    reachedUnknown*: bool
    reason*: string

# ============================================================================
# Initial state creation
# ============================================================================

proc createInitialState*(): FightState =
  ## Create a standard initial fighting position
  result = FightState(
    a: Fighter(
      pos: Position3D(
        x: -1.5, y: 0.0, z: 0.0,
        facing: 90.0,
        stance: skOrthodox,
        balance: 1.0
      ),
      leftArm: LimbStatus(free: true, extended: false, damaged: 0.0, angle: 0.0),
      rightArm: LimbStatus(free: true, extended: false, damaged: 0.0, angle: 0.0),
      leftLeg: LimbStatus(free: true, extended: false, damaged: 0.0, angle: 0.0),
      rightLeg: LimbStatus(free: true, extended: false, damaged: 0.0, angle: 0.0),
      fatigue: 0.0,
      damage: 0.0,
      liveSide: Centerline,
      control: None
    ),
    b: Fighter(
      pos: Position3D(
        x: 1.5, y: 0.0, z: 0.0,
        facing: 270.0,
        stance: skOrthodox,
        balance: 1.0
      ),
      leftArm: LimbStatus(free: true, extended: false, damaged: 0.0, angle: 0.0),
      rightArm: LimbStatus(free: true, extended: false, damaged: 0.0, angle: 0.0),
      leftLeg: LimbStatus(free: true, extended: false, damaged: 0.0, angle: 0.0),
      rightLeg: LimbStatus(free: true, extended: false, damaged: 0.0, angle: 0.0),
      fatigue: 0.0,
      damage: 0.0,
      liveSide: Centerline,
      control: None
    ),
    distance: Medium,
    sequenceLength: 0,
    terminal: false,
    winner: none(FighterID)
  )
  result.stateHash = computeStateHash(result)

proc createRandomInitialState*(): FightState =
  ## Create a randomized initial state (for variety)
  result = createInitialState()

  # Randomize stances
  if rand(1.0) > 0.5:
    result.a.pos.stance = skSouthpaw
  if rand(1.0) > 0.5:
    result.b.pos.stance = skSouthpaw

  # Randomize distance
  let r = rand(1.0)
  if r < 0.2:
    result.distance = Short
  elif r < 0.6:
    result.distance = Medium
  else:
    result.distance = Long

  # Slight fatigue/balance variation
  result.a.fatigue = rand(0.1)
  result.b.fatigue = rand(0.1)
  result.a.pos.balance = 0.9 + rand(0.1)
  result.b.pos.balance = 0.9 + rand(0.1)

  result.stateHash = computeStateHash(result)

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
    echo toCompactRepr(state)

  while moveCount < config.maxSequenceLength:
    # Record state
    if db != nil and config.recordAllStates:
      discard db.recordState(state)

    # Check terminal condition
    if isTerminalPosition(state):
      state.terminal = true
      state.winner = some(determineWinner(state))
      if db != nil:
        db.recordTerminalState(state, "Natural termination")
      break

    # Build action sequence for current fighter's turn
    var actionSeq = createEmptySequence()
    var turnMoveCount = 0

    # Keep adding moves to sequence until time runs out or no compatible moves
    while true:
      # Get viable moves for current state (physics-based, not sport rules)
      let viable = viableMoves(state, currentFighter)

      if viable.len == 0:
        # No viable moves at all
        if turnMoveCount == 0:
          # Couldn't even start a turn - unknown state
          if config.verbose:
            echo fmt"\n[!] Unknown state reached at move {moveCount}"
            echo toAnalysisStr(state)

          if db != nil and config.logUnknownStates:
            db.logUnknownState(state, fmt"No viable moves for {currentFighter} at move {moveCount}")

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
        echo fmt"  → {selectedMove.name} (time: {selectedMove.timeCost:.2f}s)"

      # Store old hash for first move of turn
      let oldHash = if turnMoveCount == 1: state.stateHash else: ""

      # Apply move
      selectedMove.apply(state, currentFighter)

      # Recompute hash
      state.stateHash = computeStateHash(state)

      # Record transition (only for first move of turn for now)
      if db != nil and turnMoveCount == 1:
        db.recordTransition(oldHash, state.stateHash, selectedMove.id, currentFighter)

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

    # Switch fighters
    currentFighter = if currentFighter == FighterA: FighterB else: FighterA

    if config.verbose and moveCount mod 10 == 0:
      echo fmt"  [{moveCount}] {toCompactRepr(state)}"

  # Determine result
  result = SimulationResult(
    finalState: state,
    totalMoves: moveCount,
    winner: state.winner,
    reachedUnknown: unknownStateReached,
    reason:
      if unknownStateReached: "Unknown state"
      elif state.terminal: fmt"Terminal: {state.winner.get()} wins"
      else: "Max sequence length"
  )

  if config.verbose:
    echo "\n=== Fight ended ==="
    echo fmt"Moves: {moveCount} | Reason: {result.reason}"
    if state.winner.isSome:
      echo fmt"Winner: {state.winner.get()}"
    echo toAnalysisStr(state)

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
    if result.finalState.terminal:
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
