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
    logUnknownStates*: bool      # Log states with no legal moves
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
        stance: Orthodox,
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
        stance: Orthodox,
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
    result.a.pos.stance = Southpaw
  if rand(1.0) > 0.5:
    result.b.pos.stance = Southpaw

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

    # Get legal moves for current fighter
    let legal = legalMoves(state, currentFighter)

    if legal.len == 0:
      # Unknown state - no legal moves
      if config.verbose:
        echo fmt"\n[!] Unknown state reached at move {moveCount}"
        echo toAnalysisStr(state)

      if db != nil and config.logUnknownStates:
        db.logUnknownState(state, fmt"No legal moves for {currentFighter} at move {moveCount}")

      unknownStateReached = true
      break

    # Select random move (uniform for now)
    let selectedMove = legal[rand(legal.len - 1)]

    if config.verbose:
      echo fmt"\n[{moveCount}] {currentFighter} uses {selectedMove.name}"

    # Store old hash for transition recording
    let oldHash = state.stateHash

    # Apply move
    selectedMove.apply(state, currentFighter)

    # Recompute hash
    state.stateHash = computeStateHash(state)

    # Record transition
    if db != nil:
      db.recordTransition(oldHash, state.stateHash, selectedMove.id, currentFighter)

    # Switch fighters
    currentFighter = if currentFighter == FighterA: FighterB else: FighterA
    inc moveCount

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
