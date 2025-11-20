## Interactive fight visualization
## Watch simulated fights unfold move-by-move

import fight_types
import fight_notation
import simulator
import moves
import general_moves
import state_storage
import std/[strformat, strutils, os]

proc clearScreen() =
  when defined(windows):
    discard execShellCmd("cls")
  else:
    discard execShellCmd("clear")

proc waitForKey() =
  echo "\n[Press ENTER to continue, 'q' to quit]"
  let input = readLine(stdin)
  if input.toLower() == "q":
    quit(0)

proc visualizeFight*(stepByStep: bool = true, maxMoves: int = 50) =
  ## Run and visualize a single fight

  echo "Initializing fight system..."
  registerGeneralMoves()
  echo fmt"Loaded {ALL_MOVES.len} moves"

  var state = createRandomInitialState()
  var currentFighter = FighterA
  var moveCount = 0

  clearScreen()
  echo "╔═══════════════════════════════════════════════════════════╗"
  echo "║           MARTIAL ARTS SIMULATION ENGINE                 ║"
  echo "║              Fight Visualization Mode                     ║"
  echo "╚═══════════════════════════════════════════════════════════╝"
  echo ""

  echo "Initial State:"
  echo toVisualBoard(state, currentFighter)
  echo "FPN: ", toFPN(state, currentFighter)
  echo "Compact: ", toCompactBoard(state)

  if stepByStep:
    waitForKey()

  # Fight loop
  while moveCount < maxMoves:
    if stepByStep:
      clearScreen()

    echo fmt"\n{'═'.repeat(60)}"
    echo fmt" MOVE {moveCount + 1} - Fighter {currentFighter}'s turn"
    echo '═'.repeat(60)

    # Get viable moves
    let viable = viableMoves(state, currentFighter)

    if viable.len == 0:
      echo "\n⚠️  NO VIABLE MOVES - Unknown state reached!"
      echo toVisualBoard(state, currentFighter)
      break

    echo fmt"\nViable moves: {viable.len}"
    for i, move in viable:
      if i < 5:  # Show first 5
        let exposure = fmt"{int(move.exposureRisk * 100)}%"
        let energy = fmt"{int(move.energyCost * 100)}%"
        echo fmt"  • {move.name:20} [{move.moveType}] exposure:{exposure} energy:{energy}"
      elif i == 5:
        echo fmt"  ... and {viable.len - 5} more"
        break

    # Build action sequence (simplified - just pick first viable)
    var actionSeq = createEmptySequence()
    var selectedMoves: seq[Move] = @[]

    # Try to build a sequence
    for move in viable:
      if canAddToSequence(actionSeq, move):
        selectedMoves.add(move)
        addMoveToSequence(actionSeq, move)

        # 50% chance to stop and execute
        if selectedMoves.len > 0 and (selectedMoves.len >= 2 or rand(1.0) < 0.5):
          break

    if selectedMoves.len == 0:
      echo "\n⚠️  Could not build action sequence!"
      break

    # Show selected sequence
    echo fmt"\n✓ Selected sequence ({selectedMoves.len} moves):"
    for move in selectedMoves:
      let targets = if move.targets.len > 0: move.targets.join(", ") else: "none"
      echo fmt"  → {move.name} [targets: {targets}]"

    echo fmt"\n  Time: {actionSeq.totalTimeCost:.2f}s, Energy: {int(actionSeq.totalEnergyCost*100)}%"

    # Apply moves
    for move in selectedMoves:
      move.apply(state, currentFighter)

    # Update state
    inc moveCount
    state.sequenceLength = moveCount

    # Check terminal
    if isTerminalPosition(state):
      echo "\n🏁 TERMINAL POSITION REACHED!"
      let winner = determineWinner(state)
      echo fmt"   Winner: Fighter {winner}"
      echo toVisualBoard(state, currentFighter)
      break

    # Show updated state
    echo "\nResulting state:"
    echo toVisualBoard(state, currentFighter)
    echo "Compact: ", toCompactBoard(state)

    # Switch fighters
    currentFighter = if currentFighter == FighterA: FighterB else: FighterA

    if stepByStep:
      waitForKey()
    else:
      sleep(500)  # 500ms delay

  echo "\n" & '═'.repeat(60)
  echo " FIGHT COMPLETE"
  echo '═'.repeat(60)
  echo fmt"Total moves: {moveCount}"
  echo fmt"Final state: {toCompactBoard(state)}"

  if state.terminal:
    echo fmt"Result: Fighter {state.winner.get()} wins!"
  else:
    echo "Result: Fight limit reached"

proc batchVisualize*(numFights: int = 5) =
  ## Run multiple fights and show summary
  echo "Running batch visualization..."
  registerGeneralMoves()

  var results: seq[tuple[moves: int, winner: Option[FighterID], reason: string]] = @[]

  for i in 1..numFights:
    echo fmt"\n=== Fight {i}/{numFights} ==="

    let config = SimulationConfig(
      maxSequenceLength: 100,
      recordAllStates: false,
      logUnknownStates: false,
      verbose: false
    )

    let result = simulateFight(config, nil)

    let reason = if result.reachedUnknown: "Unknown state"
               elif result.winner.isSome: fmt"Fighter {result.winner.get()} wins"
               else: "Move limit"

    results.add((moves: result.totalMoves, winner: result.winner, reason: reason))

    echo fmt"  Moves: {result.totalMoves}"
    echo fmt"  Result: {reason}"
    echo fmt"  Final: {toCompactBoard(result.finalState)}"

  echo "\n" & '═'.repeat(60)
  echo " BATCH SUMMARY"
  echo '═'.repeat(60)

  var totalMoves = 0
  var aWins = 0
  var bWins = 0
  var unknownStates = 0

  for r in results:
    totalMoves += r.moves
    if r.reason == "Unknown state":
      inc unknownStates
    elif r.winner.isSome:
      if r.winner.get() == FighterA:
        inc aWins
      else:
        inc bWins

  echo fmt"Total fights: {numFights}"
  echo fmt"Average moves: {totalMoves div numFights}"
  echo fmt"Fighter A wins: {aWins}"
  echo fmt"Fighter B wins: {bWins}"
  echo fmt"Unknown states: {unknownStates}"

when isMainModule:
  import std/parseopt

  var mode = "interactive"
  var fights = 5

  for kind, key, val in getopt():
    case kind:
    of cmdLongOption, cmdShortOption:
      case key:
      of "mode", "m":
        mode = val
      of "fights", "f":
        fights = parseInt(val)
      of "help", "h":
        echo """
Fight Visualization Tool

Usage:
  visualize [options]

Options:
  --mode=MODE, -m MODE      Mode: interactive, auto, batch (default: interactive)
  --fights=N, -f N          Number of fights for batch mode (default: 5)
  --help, -h                Show this help

Modes:
  interactive    Step through each move with ENTER
  auto          Auto-play with 500ms delay
  batch         Run multiple fights and show summary

Examples:
  visualize --mode=interactive
  visualize --mode=auto
  visualize --mode=batch --fights=10
"""
        quit(0)
      else:
        discard
    else:
      discard

  case mode:
  of "interactive":
    echo "Starting interactive mode..."
    visualizeFight(stepByStep = true)
  of "auto":
    echo "Starting auto mode..."
    visualizeFight(stepByStep = false)
  of "batch":
    batchVisualize(fights)
  else:
    echo "Unknown mode: ", mode
    quit(1)
