## State storage and unknown state logging using SQLite

import fight_types
import fight_display
import std/[strformat, times, json, hashes, base64, options, strutils]
import db_connector/db_sqlite

type
  StateDB* = ref object
    db: DbConn
    filename: string

# ============================================================================
# State hashing and serialization
# ============================================================================

proc computeStateHash*(state: FightState): string =
  ## Compute deterministic hash for a fight state
  let h = hash(state)
  result = $h

proc toJson*(fighter: Fighter): JsonNode =
  ## Serialize fighter to JSON (position state only)
  %* {
    "pos": {
      "x": fighter.pos.x,
      "y": fighter.pos.y,
      "z": fighter.pos.z,
      "facing": fighter.pos.facing,
      "stance": $fighter.pos.stance,
      "balance": fighter.pos.balance
    },
    "posture": $fighter.posture,
    "leftArm": {
      "free": fighter.leftArm.free,
      "extended": fighter.leftArm.extended,
      "angle": fighter.leftArm.angle
    },
    "rightArm": {
      "free": fighter.rightArm.free,
      "extended": fighter.rightArm.extended,
      "angle": fighter.rightArm.angle
    },
    "leftLeg": {
      "free": fighter.leftLeg.free,
      "extended": fighter.leftLeg.extended,
      "angle": fighter.leftLeg.angle
    },
    "rightLeg": {
      "free": fighter.rightLeg.free,
      "extended": fighter.rightLeg.extended,
      "angle": fighter.rightLeg.angle
    },
    "liveSide": $fighter.liveSide,
    "control": $fighter.control,
    "momentum": {
      "linear": fighter.momentum.linear,
      "rotational": fighter.momentum.rotational,
      "decayRate": fighter.momentum.decayRate
    },
    "biomech": {
      "hipRotation": fighter.biomech.hipRotation,
      "torsoRotation": fighter.biomech.torsoRotation,
      "weightDistribution": fighter.biomech.weightDistribution,
      "recovering": fighter.biomech.recovering,
      "recoveryFrames": fighter.biomech.recoveryFrames
    }
  }

proc toJson*(state: FightState): JsonNode =
  ## Serialize fight state to JSON
  result = %* {
    "a": state.a.toJson(),
    "b": state.b.toJson(),
    "distance": $state.distance,
    "sequenceLength": state.sequenceLength,
    "terminal": state.terminal,
    "stateHash": state.stateHash
  }
  if state.winner.isSome:
    result["winner"] = % $state.winner.get()

proc fromJson*(json: JsonNode, T: typedesc[Fighter]): Fighter =
  ## Deserialize Fighter from JSON
  result.pos = Position3D(
    x: json["pos"]["x"].getFloat(),
    y: json["pos"]["y"].getFloat(),
    z: json["pos"]["z"].getFloat(),
    facing: json["pos"]["facing"].getFloat(),
    stance: parseEnum[StanceKind](json["pos"]["stance"].getStr()),
    balance: json["pos"]["balance"].getFloat()
  )
  result.posture = parseEnum[PostureLevel](json["posture"].getStr())
  result.leftArm = LimbPosition(
    free: json["leftArm"]["free"].getBool(),
    extended: json["leftArm"]["extended"].getBool(),
    angle: json["leftArm"]["angle"].getFloat()
  )
  result.rightArm = LimbPosition(
    free: json["rightArm"]["free"].getBool(),
    extended: json["rightArm"]["extended"].getBool(),
    angle: json["rightArm"]["angle"].getFloat()
  )
  result.leftLeg = LimbPosition(
    free: json["leftLeg"]["free"].getBool(),
    extended: json["leftLeg"]["extended"].getBool(),
    angle: json["leftLeg"]["angle"].getFloat()
  )
  result.rightLeg = LimbPosition(
    free: json["rightLeg"]["free"].getBool(),
    extended: json["rightLeg"]["extended"].getBool(),
    angle: json["rightLeg"]["angle"].getFloat()
  )
  result.liveSide = parseEnum[SideKind](json["liveSide"].getStr())
  result.control = parseEnum[ControlKind](json["control"].getStr())
  result.momentum = Momentum(
    linear: json["momentum"]["linear"].getFloat(),
    rotational: json["momentum"]["rotational"].getFloat(),
    decayRate: json["momentum"]["decayRate"].getFloat()
  )
  result.biomech = BiomechanicalState(
    hipRotation: json["biomech"]["hipRotation"].getFloat(),
    torsoRotation: json["biomech"]["torsoRotation"].getFloat(),
    weightDistribution: json["biomech"]["weightDistribution"].getFloat(),
    recovering: json["biomech"]["recovering"].getBool(),
    recoveryFrames: json["biomech"]["recoveryFrames"].getInt()
  )

proc fromJson*(json: JsonNode, T: typedesc[FightState]): FightState =
  ## Deserialize FightState from JSON
  result.a = fromJson(json["a"], Fighter)
  result.b = fromJson(json["b"], Fighter)
  result.distance = parseEnum[DistanceKind](json["distance"].getStr())
  result.sequenceLength = json["sequenceLength"].getInt()
  result.terminal = json["terminal"].getBool()
  result.stateHash = json["stateHash"].getStr()
  if json.hasKey("winner"):
    result.winner = some(parseEnum[FighterID](json["winner"].getStr()))
  else:
    result.winner = none(FighterID)

# ============================================================================
# Database operations
# ============================================================================

proc openStateDB*(filename: string): StateDB =
  ## Open or create state database
  result = StateDB(filename: filename)
  result.db = open(filename, "", "", "")

  # Create tables
  result.db.exec(sql"""
    CREATE TABLE IF NOT EXISTS states (
      state_hash TEXT PRIMARY KEY,
      state_json TEXT NOT NULL,
      sequence_length INTEGER,
      is_terminal INTEGER,
      first_seen INTEGER,
      seen_count INTEGER DEFAULT 1
    )
  """)

  result.db.exec(sql"""
    CREATE TABLE IF NOT EXISTS unknown_states (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      state_hash TEXT NOT NULL,
      state_json TEXT NOT NULL,
      text_repr TEXT NOT NULL,
      timestamp INTEGER NOT NULL,
      resolved INTEGER DEFAULT 0,
      notes TEXT
    )
  """)

  result.db.exec(sql"""
    CREATE TABLE IF NOT EXISTS state_transitions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      from_hash TEXT NOT NULL,
      to_hash TEXT NOT NULL,
      move_id TEXT NOT NULL,
      who TEXT NOT NULL,
      count INTEGER DEFAULT 1,
      UNIQUE(from_hash, to_hash, move_id, who)
    )
  """)

  result.db.exec(sql"""
    CREATE TABLE IF NOT EXISTS terminal_states (
      state_hash TEXT PRIMARY KEY,
      winner TEXT NOT NULL,
      win_distance INTEGER DEFAULT 0,
      reason TEXT
    )
  """)

  result.db.exec(sql"""
    CREATE INDEX IF NOT EXISTS idx_unknown_resolved
    ON unknown_states(resolved)
  """)

  result.db.exec(sql"""
    CREATE INDEX IF NOT EXISTS idx_transitions_from
    ON state_transitions(from_hash)
  """)

proc close*(sdb: StateDB) =
  ## Close database connection
  sdb.db.close()

# ============================================================================
# State recording
# ============================================================================

proc recordState*(sdb: StateDB, state: FightState): bool =
  ## Record a state; returns true if new, false if seen before
  let hash = state.stateHash
  let now = getTime().toUnix()

  # Check if exists
  let row = sdb.db.getRow(sql"SELECT seen_count FROM states WHERE state_hash = ?", hash)

  if row[0] == "":
    # New state
    sdb.db.exec(sql"""
      INSERT INTO states (state_hash, state_json, sequence_length, is_terminal, first_seen)
      VALUES (?, ?, ?, ?, ?)
    """, hash, $state.toJson(), state.sequenceLength,
        (if state.terminal: 1 else: 0), now)
    result = true
  else:
    # Increment seen count
    sdb.db.exec(sql"""
      UPDATE states SET seen_count = seen_count + 1 WHERE state_hash = ?
    """, hash)
    result = false

proc recordTransition*(sdb: StateDB, fromHash: string, toHash: string,
                      moveId: string, who: FighterID) =
  ## Record a state transition
  let whoStr = $who

  # Try to increment existing transition
  let row = sdb.db.getRow(sql"""
    SELECT count FROM state_transitions
    WHERE from_hash = ? AND to_hash = ? AND move_id = ? AND who = ?
  """, fromHash, toHash, moveId, whoStr)

  if row[0] == "":
    # New transition
    sdb.db.exec(sql"""
      INSERT INTO state_transitions (from_hash, to_hash, move_id, who)
      VALUES (?, ?, ?, ?)
    """, fromHash, toHash, moveId, whoStr)
  else:
    # Increment count
    sdb.db.exec(sql"""
      UPDATE state_transitions SET count = count + 1
      WHERE from_hash = ? AND to_hash = ? AND move_id = ? AND who = ?
    """, fromHash, toHash, moveId, whoStr)

proc recordTerminalState*(sdb: StateDB, state: FightState, reason: string = "") =
  ## Record a terminal (winning) state
  let hash = state.stateHash
  let winnerStr = if state.winner.isSome: $state.winner.get() else: "draw"

  sdb.db.exec(sql"""
    INSERT OR REPLACE INTO terminal_states (state_hash, winner, reason)
    VALUES (?, ?, ?)
  """, hash, winnerStr, reason)

# ============================================================================
# Unknown state logging
# ============================================================================

proc logUnknownState*(sdb: StateDB, state: FightState, context: string = "") =
  ## Log a state that has no viable moves (physics-based impossibility)
  let hash = state.stateHash
  let now = getTime().toUnix()
  let textRepr = toTextRepr(state)
  let jsonRepr = $state.toJson()

  let notes = if context != "": context else: "No viable moves found"

  sdb.db.exec(sql"""
    INSERT INTO unknown_states (state_hash, state_json, text_repr, timestamp, notes)
    VALUES (?, ?, ?, ?, ?)
  """, hash, jsonRepr, textRepr, now, notes)

  echo fmt"[UNKNOWN STATE] Logged: {hash[0..7]}... (seq: {state.sequenceLength})"

proc getUnresolvedUnknownStates*(sdb: StateDB, limit: int = 100): seq[tuple[id: int, hash: string, text: string]] =
  ## Get unresolved unknown states for human review
  result = @[]
  for row in sdb.db.fastRows(sql"""
    SELECT id, state_hash, text_repr
    FROM unknown_states
    WHERE resolved = 0
    ORDER BY timestamp DESC
    LIMIT ?
  """, limit):
    result.add((
      id: parseInt(row[0]),
      hash: row[1],
      text: row[2]
    ))

proc markUnknownStateResolved*(sdb: StateDB, id: int, notes: string = "") =
  ## Mark an unknown state as resolved
  sdb.db.exec(sql"""
    UPDATE unknown_states SET resolved = 1, notes = ? WHERE id = ?
  """, notes, id)

# ============================================================================
# Query operations
# ============================================================================

proc getStateCount*(sdb: StateDB): int =
  ## Get total number of unique states
  let row = sdb.db.getRow(sql"SELECT COUNT(*) FROM states")
  result = parseInt(row[0])

proc getUnknownStateCount*(sdb: StateDB): int =
  ## Get number of unresolved unknown states
  let row = sdb.db.getRow(sql"SELECT COUNT(*) FROM unknown_states WHERE resolved = 0")
  result = parseInt(row[0])

proc getTerminalStateCount*(sdb: StateDB): int =
  ## Get number of terminal states
  let row = sdb.db.getRow(sql"SELECT COUNT(*) FROM terminal_states")
  result = parseInt(row[0])

proc getStats*(sdb: StateDB): string =
  ## Get database statistics
  let total = getStateCount(sdb)
  let unknown = getUnknownStateCount(sdb)
  let terminal = getTerminalStateCount(sdb)

  let transRow = sdb.db.getRow(sql"SELECT COUNT(*) FROM state_transitions")
  let transitions = parseInt(transRow[0])

  result = fmt"""
State Database Statistics:
  Total unique states: {total}
  Unresolved unknown states: {unknown}
  Terminal states: {terminal}
  Recorded transitions: {transitions}
"""

# ============================================================================
# Export for analysis
# ============================================================================

proc exportUnknownStatesToFile*(sdb: StateDB, filename: string) =
  ## Export all unresolved unknown states to a text file
  var file = open(filename, fmWrite)
  defer: file.close()

  file.writeLine("=" .repeat(80))
  file.writeLine("UNRESOLVED UNKNOWN STATES")
  file.writeLine("=" .repeat(80))
  file.writeLine("")

  var count = 0
  for row in sdb.db.fastRows(sql"""
    SELECT id, state_hash, text_repr, notes, timestamp
    FROM unknown_states
    WHERE resolved = 0
    ORDER BY timestamp DESC
  """):
    count += 1
    file.writeLine(fmt"[{count}] ID: {row[0]} | Hash: {row[1][0..15]}...")
    file.writeLine(fmt"Timestamp: {row[4]} | Notes: {row[3]}")
    file.writeLine("")
    file.writeLine(row[2])
    file.writeLine("")
    file.writeLine("-" .repeat(80))
    file.writeLine("")

  echo fmt"Exported {count} unknown states to {filename}"
