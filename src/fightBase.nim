## Main entry point for the martial arts simulation engine

import std/[os, strutils, parseopt, random, strformat]
import fight_types
import fight_display
import constraints
import moves
import state_storage
import simulator

proc printUsage() =
  echo """
FightBase - Martial Arts Simulation Engine

Usage:
  fightBase [command] [options]

Commands:
  test          Run a single interactive test fight
  batch N       Run N simulations (default: 1000)
  stats         Show database statistics
  export        Export unknown states to file
  list          List unresolved unknown states

Options:
  --db FILE     Database file (default: fight_states.db)
  --max N       Max sequence length (default: 200)
  --record      Record all states (default: true for batch)
  --log         Log unknown states (default: true)
  --verbose     Verbose output (default: false)
  --seed N      Random seed (default: random)

Examples:
  fightBase test --verbose
  fightBase batch 10000 --max 150
  fightBase stats --db my_fights.db
  fightBase export --db fight_states.db
"""

proc main() =
  # Parse command line
  var command = ""
  var dbFile = "fight_states.db"
  var maxLength = 200
  var recordAll = false
  var logUnknown = true
  var verbose = false
  var batchSize = 1000
  var seedValue = 0

  if paramCount() == 0:
    printUsage()
    return

  command = paramStr(1)

  # Parse options
  var p = initOptParser(commandLineParams())
  var skipNext = false

  for kind, key, val in p.getopt():
    if skipNext:
      skipNext = false
      continue

    case kind
    of cmdLongOption, cmdShortOption:
      case key
      of "db": dbFile = val
      of "max": maxLength = parseInt(val)
      of "record": recordAll = true
      of "log": logUnknown = true
      of "verbose": verbose = true
      of "seed": seedValue = parseInt(val)
      else: discard
    of cmdArgument:
      if command == "batch" and key.len > 0 and key[0].isDigit():
        batchSize = parseInt(key)
    of cmdEnd: discard

  # Initialize random seed
  if seedValue != 0:
    randomize(seedValue)
    echo "Using seed: ", seedValue
  else:
    randomize()

  # Initialize moves
  echo "Initializing move database..."
  initializeMoves()
  echo ""

  # Execute command
  case command
  of "test":
    echo "Running interactive test fight...\n"
    let result = runInteractiveFight()
    echo "\n=== Final Result ==="
    echo result.reason

  of "batch":
    let config = SimulationConfig(
      maxSequenceLength: maxLength,
      recordAllStates: true,  # Always record in batch mode
      logUnknownStates: logUnknown,
      verbose: verbose
    )

    let stats = runBatchSimulation(batchSize, config, dbFile)
    echo fmt"""
Batch Results:
  Completed: {stats.completed}
  Reached unknown states: {stats.unknown}
  Reached terminal states: {stats.terminal}
  Unknown rate: {(stats.unknown.float / stats.completed.float * 100.0):.1f}%
  Terminal rate: {(stats.terminal.float / stats.completed.float * 100.0):.1f}%
"""

  of "stats":
    let db = openStateDB(dbFile)
    defer: db.close()
    echo db.getStats()

  of "export":
    let db = openStateDB(dbFile)
    defer: db.close()

    let outFile = dbFile.changeFileExt(".txt")
    db.exportUnknownStatesToFile(outFile)

  of "list":
    let db = openStateDB(dbFile)
    defer: db.close()

    let unknown = db.getUnresolvedUnknownStates(20)
    echo fmt"Found {unknown.len} unresolved unknown states:\n"

    for i, state in unknown:
      echo fmt"[{i+1}] ID {state.id} | Hash: {state.hash[0..15]}..."
      echo state.text
      echo ""

  else:
    echo "Unknown command: ", command
    echo ""
    printUsage()

when isMainModule:
  main()
