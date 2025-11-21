## Example: Generate and Analyze a Martial Arts Game Tree
##
## This example demonstrates basic usage of the game tree generator.
## Start here to validate that moves are realistic before scaling up.

import ../src/game_tree
import ../src/moves
import ../src/state_storage
import std/[strformat, times]

proc generateSmallTree() =
  echo "=== Martial Arts Tablebase Generator ==="
  echo ""

  # Initialize move registry
  echo "Initializing moves..."
  initializeMoves()
  echo "  ✓ Registered moves"
  echo ""

  # Open database
  let dbPath = "fight_tree_test.db"
  echo fmt"Opening database: {dbPath}"
  let gtdb = openGameTreeDB(dbPath)
  defer: gtdb.close()
  echo "  ✓ Database ready"
  echo ""

  # Generate tree (start small for validation)
  echo "Generating tree..."
  echo "  Batch size: 50 states per iteration"
  echo "  Max iterations: 100"
  echo ""

  let startTime = getTime()
  let stats = gtdb.generateGameTree(
    batchSize = 50,
    maxIterations = 100
  )
  let elapsed = (getTime() - startTime).inSeconds

  # Display results
  echo ""
  echo "=== Generation Complete ==="
  echo fmt"Time elapsed: {elapsed}s"
  echo ""
  echo "Tree Statistics:"
  echo fmt"  Total unique states: {stats.totalStates}"
  echo fmt"  Terminal states: {stats.terminalStates}"
  echo fmt"  Player1 wins: {stats.player1Wins}"
  echo fmt"  Player2 wins: {stats.player2Wins}"
  echo fmt"  Draws: {stats.draws}"
  echo fmt"  Max depth: {stats.maxDepth}"
  echo fmt"  Avg game length: {stats.avgGameLength:.2f}"
  echo ""

  # Show state distribution by depth
  echo "States by depth (move_number):"
  for row in gtdb.db.fastRows(sql"""
    SELECT move_number, COUNT(*) as count
    FROM states
    GROUP BY move_number
    ORDER BY move_number
    LIMIT 10
  """):
    let depth = row[0]
    let count = row[1]
    echo fmt"  Depth {depth}: {count} states"
  echo ""

  # Show most common opening moves
  echo "Most common opening moves:"
  for row in gtdb.db.fastRows(sql"""
    SELECT move_id, COUNT(*) as count
    FROM state_transitions
    WHERE mover = 'Player1'
      AND from_hash IN (SELECT state_hash FROM states WHERE move_number = 0)
    GROUP BY move_id
    ORDER BY count DESC
    LIMIT 5
  """):
    echo fmt"  {row[0]}: {row[1]} times"
  echo ""

  # Show terminal reasons
  echo "Terminal conditions:"
  for row in gtdb.db.fastRows(sql"""
    SELECT terminal_reason, COUNT(*) as count
    FROM states
    WHERE is_terminal = 1
    GROUP BY terminal_reason
    ORDER BY count DESC
  """):
    if row[0] != "":
      echo fmt"  {row[0]}: {row[1]} states"
  echo ""

  echo "=== Next Steps ==="
  echo "1. Examine states manually to verify moves are realistic"
  echo "2. Query specific positions: SELECT * FROM states WHERE move_number = 3"
  echo "3. If moves look good, increase maxIterations to generate deeper tree"
  echo "4. Analyze patterns to extract martial arts principles"
  echo ""
  echo fmt"Database saved to: {dbPath}"

proc inspectStates() =
  ## Example: Inspect specific states for manual validation
  echo "=== Inspecting Sample States ==="
  echo ""

  let gtdb = openGameTreeDB("fight_tree_test.db")
  defer: gtdb.close()

  # Get a few states at depth 3
  echo "Sample states at depth 3:"
  var count = 0
  for row in gtdb.db.fastRows(sql"""
    SELECT state_hash, state_json
    FROM states
    WHERE move_number = 3
    LIMIT 3
  """):
    count += 1
    let hash = row[0]
    let stateJson = parseJson(row[1])
    let state = fromJson(stateJson, FightState)

    echo ""
    echo fmt"State {count} (hash: {hash[0..15]}...):"
    echo fmt"  Fighter A: {state.a.posture}, balance: {state.a.pos.balance:.2f}"
    echo fmt"  Fighter B: {state.b.posture}, balance: {state.b.pos.balance:.2f}"
    echo fmt"  Distance: {state.distance}"

    # Show how we got here
    echo "  Path to this state:"
    for transRow in gtdb.db.fastRows(sql"""
      SELECT from_hash, move_id, mover, hit_success
      FROM state_transitions
      WHERE to_hash = ?
      LIMIT 1
    """, hash):
      let moveId = transRow[1]
      let mover = transRow[2]
      let hitSuccess = if transRow[3] == "1": "hit" else: "miss"
      echo fmt"    {mover} → {moveId} ({hitSuccess})"

proc analyzeMoveEffectiveness() =
  ## Example: Analyze which moves lead to winning positions
  echo "=== Move Effectiveness Analysis ==="
  echo ""

  let gtdb = openGameTreeDB("fight_tree_test.db")
  defer: gtdb.close()

  echo "Moves that lead to Player1 wins:"
  for row in gtdb.db.fastRows(sql"""
    SELECT
      t.move_id,
      COUNT(*) as total_uses,
      SUM(CASE WHEN s.winner = 'Player1' THEN 1 ELSE 0 END) as wins,
      AVG(s.sequence_length) as avg_length
    FROM state_transitions t
    JOIN states s ON t.to_hash = s.state_hash
    WHERE t.mover = 'Player1'
      AND s.is_terminal = 1
    GROUP BY t.move_id
    HAVING total_uses > 5
    ORDER BY wins DESC
    LIMIT 10
  """):
    let moveId = row[0]
    let total = row[1]
    let wins = row[2]
    let avgLen = row[3]
    let winRate = if total != "0": (parseInt(wins).float / parseInt(total).float * 100.0) else: 0.0
    echo fmt"  {moveId}: {wins}/{total} wins ({winRate:.1f}%), avg length: {avgLen}"

when isMainModule:
  # Run the example
  generateSmallTree()

  echo ""
  echo "Press Enter to inspect states..."
  discard stdin.readLine()
  inspectStates()

  echo ""
  echo "Press Enter to analyze move effectiveness..."
  discard stdin.readLine()
  analyzeMoveEffectiveness()

  echo ""
  echo "Done! See docs/GAME_TREE_USAGE.md for more analysis techniques."
