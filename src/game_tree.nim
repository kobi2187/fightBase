## Game Tree Generator - Chess-style tablebase for martial arts
## Systematically expands all possible fight states from initial position
## Tracks damage along paths for realistic terminal evaluation

import fight_types
import moves
import vulnerabilities
import constraints
import state_storage
import std/[db_sqlite, options, json, strformat, times, tables, hashes]

type
  Player* = enum
    Player1 = "Player1"  # White - always moves first
    Player2 = "Player2"  # Black - always moves second

  VulnerabilityHit* = object
    ## Record of a vulnerability being hit
    zone*: VulnerabilityZone
    force*: float
    damage*: float
    target*: Player  # Which player was hit

  DamageInfo* = object
    ## Metadata about damage dealt in a transition
    hit*: bool
    damage*: float
    force*: float
    vulnerabilities*: seq[VulnerabilityZone]

  PathDamage* = object
    ## Accumulated damage along a specific path
    damagePlayer1*: float
    damagePlayer2*: float
    hitHistory*: seq[VulnerabilityHit]

  GameTreeDB* = ref object
    db: DbConn
    filename: string

  TreeStats* = object
    totalStates*: int
    terminalStates*: int
    player1Wins*: int
    player2Wins*: int
    draws*: int
    avgGameLength*: float
    maxDepth*: int

# ============================================================================
# Database operations
# ============================================================================

proc openGameTreeDB*(filename: string): GameTreeDB =
  ## Open or create game tree database
  result = GameTreeDB(filename: filename)
  result.db = open(filename, "", "", "")

  # States table (position only - no damage/fatigue)
  result.db.exec(sql"""
    CREATE TABLE IF NOT EXISTS states (
      state_hash TEXT PRIMARY KEY,
      state_json TEXT NOT NULL,
      sequence_length INTEGER,
      last_mover TEXT,           -- "Player1", "Player2", or NULL (initial)
      is_terminal INTEGER,
      terminal_reason TEXT,
      winner TEXT,               -- "Player1", "Player2", or NULL (draw)
      first_seen INTEGER,
      has_children INTEGER DEFAULT 0
    )
  """)

  # Transitions WITH damage metadata
  result.db.exec(sql"""
    CREATE TABLE IF NOT EXISTS state_transitions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      from_hash TEXT NOT NULL,
      to_hash TEXT NOT NULL,
      move_id TEXT NOT NULL,
      mover TEXT NOT NULL,
      vulnerabilities_hit TEXT,  -- JSON array of zones hit
      damage_dealt REAL,
      force_applied REAL,
      hit_success INTEGER,       -- 1 if hit landed, 0 if missed
      UNIQUE(from_hash, move_id, mover)
    )
  """)

  # Path damage tracking
  result.db.exec(sql"""
    CREATE TABLE IF NOT EXISTS path_damage (
      state_hash TEXT NOT NULL,
      from_hash TEXT NOT NULL,
      cumulative_damage_p1 REAL,
      cumulative_damage_p2 REAL,
      hit_count_p1 INTEGER,
      hit_count_p2 INTEGER,
      critical_hits TEXT,        -- JSON of critical hits
      PRIMARY KEY (state_hash, from_hash)
    )
  """)

  # Indices for efficient leaf queries
  result.db.exec(sql"""
    CREATE INDEX IF NOT EXISTS idx_leaf_states
    ON states(has_children, is_terminal, sequence_length)
    WHERE has_children = 0 AND is_terminal = 0
  """)

  result.db.exec(sql"""
    CREATE INDEX IF NOT EXISTS idx_transitions_from
    ON state_transitions(from_hash)
  """)

proc close*(gtdb: GameTreeDB) =
  gtdb.db.close()

# ============================================================================
# Player turn logic
# ============================================================================

proc getNextPlayer*(lastMover: Option[Player]): Player =
  ## Determine whose turn it is
  if lastMover.isNone or lastMover.get() == Player2:
    Player1
  else:
    Player2

proc playerToFighter*(player: Player): FighterID =
  ## Convert Player to FighterID
  if player == Player1: FighterA else: FighterB

# ============================================================================
# Initial state
# ============================================================================

proc createInitialState*(): FightState =
  ## Create starting position - both standing, medium distance, neutral
  result = FightState(
    a: Fighter(
      pos: Position3D(
        x: 0.0, y: 0.0, z: 0.0,
        facing: 0.0,
        stance: skOrthodox,
        balance: 1.0
      ),
      posture: plStanding,
      leftArm: LimbPosition(free: true, extended: false, angle: 0.0),
      rightArm: LimbPosition(free: true, extended: false, angle: 0.0),
      leftLeg: LimbPosition(free: true, extended: false, angle: 0.0),
      rightLeg: LimbPosition(free: true, extended: false, angle: 0.0),
      liveSide: Centerline,
      control: None,
      momentum: Momentum(linear: 0.0, rotational: 0.0, decayRate: 0.1),
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
        x: 1.0, y: 0.0, z: 0.0,
        facing: 180.0,
        stance: skOrthodox,
        balance: 1.0
      ),
      posture: plStanding,
      leftArm: LimbPosition(free: true, extended: false, angle: 0.0),
      rightArm: LimbPosition(free: true, extended: false, angle: 0.0),
      leftLeg: LimbPosition(free: true, extended: false, angle: 0.0),
      rightLeg: LimbPosition(free: true, extended: false, angle: 0.0),
      liveSide: Centerline,
      control: None,
      momentum: Momentum(linear: 0.0, rotational: 0.0, decayRate: 0.1),
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

  result.stateHash = computeStateHash(result)

# ============================================================================
# Damage calculation
# ============================================================================

proc calculateForce*(move: Move): float =
  ## Estimate force generated by move based on physics
  ## Force (N) ≈ mass * acceleration
  ## For strikes: use momentum and commitment as proxies
  let baseMass = 5.0  # kg (approximate limb mass)
  let velocity = move.physicsEffect.linearMomentum +
                 move.physicsEffect.rotationalMomentum * 0.01
  let commitmentFactor = 1.0 + move.physicsEffect.commitmentLevel

  result = baseMass * velocity * commitmentFactor * 20.0  # Scale to Newtons

proc calculateDamageDealt*(
  beforeState: FightState,
  afterState: FightState,
  move: Move,
  who: FighterID
): DamageInfo =
  ## Calculate what damage was dealt by this move
  result.hit = false
  result.damage = 0.0
  result.force = 0.0
  result.vulnerabilities = @[]

  # Only offensive moves deal damage
  if move.moveType != mtOffensive:
    return

  # Check if hit landed (balance change indicates hit)
  let defender = if who == FighterA: afterState.b else: afterState.a
  let beforeDefender = if who == FighterA: beforeState.b else: beforeState.a

  if defender.pos.balance < beforeDefender.pos.balance - 0.01:
    result.hit = true
    result.force = calculateForce(move)

    # Find most likely target hit
    let attacker = if who == FighterA: beforeState.a else: beforeState.b
    let distance = distanceInMeters(beforeState.distance)

    let targets = getBestTargets(attacker, beforeDefender, distance)

    if targets.len > 0:
      let targetZone = targets[0].zone
      result.vulnerabilities = @[targetZone]
      result.damage = move.damageEffect.directDamage

# ============================================================================
# Terminal state evaluation
# ============================================================================

proc isCriticalKO*(zone: VulnerabilityZone, force: float, cumulativeDamage: float): bool =
  ## Check if this hit to this zone = instant KO
  let vulnData = getVulnerabilityData(zone)

  # Immediate KO zones (sufficient force)
  if zone in {vzLiver, vzJaw, vzTemples} and
     force > vulnData.forceRequired * 1.5:
    return true

  # Accumulated damage makes KO easier
  let threshold = vulnData.forceRequired * (1.0 - cumulativeDamage * 0.5)
  return force > threshold

proc isTerminal*(
  state: FightState,
  pathDamageP1: float,
  pathDamageP2: float,
  hitHistory: seq[VulnerabilityHit]
): (bool, string, Option[Player]) =
  ## Check if state is terminal considering accumulated damage

  # 1. Stalemate - too long
  if state.sequenceLength >= 200:
    return (true, "stalemate", none(Player))

  # 2. Position-based terminals
  if state.a.pos.balance < 0.2:
    return (true, "fallen_a", some(Player2))
  if state.b.pos.balance < 0.2:
    return (true, "fallen_b", some(Player1))

  if state.a.posture == plGrounded and state.a.pos.balance < 0.4:
    return (true, "grounded_helpless_a", some(Player2))
  if state.b.posture == plGrounded and state.b.pos.balance < 0.4:
    return (true, "grounded_helpless_b", some(Player1))

  # 3. Damage-based terminals
  if pathDamageP1 > 0.8:
    return (true, "damage_ko_a", some(Player2))
  if pathDamageP2 > 0.8:
    return (true, "damage_ko_b", some(Player1))

  # 4. Critical vulnerability hits
  for hit in hitHistory:
    if hit.target == Player1:
      if isCriticalKO(hit.zone, hit.force, pathDamageP1):
        return (true, fmt"ko_{hit.zone}_a", some(Player2))
    else:
      if isCriticalKO(hit.zone, hit.force, pathDamageP2):
        return (true, fmt"ko_{hit.zone}_b", some(Player1))

  # Not terminal
  return (false, "", none(Player))

# ============================================================================
# State insertion
# ============================================================================

proc insertState*(
  gtdb: GameTreeDB,
  state: FightState,
  lastMover: Option[Player],
  isTerminal: bool,
  terminalReason: string,
  winner: Option[Player]
): bool =
  ## Insert state, returns true if new
  let now = getTime().toUnix()
  let lastMoverStr = if lastMover.isSome: $lastMover.get() else: ""
  let winnerStr = if winner.isSome: $winner.get() else: ""

  # Check if exists
  let row = gtdb.db.getRow(
    sql"SELECT state_hash FROM states WHERE state_hash = ?",
    state.stateHash
  )

  if row[0] == "":
    # New state
    gtdb.db.exec(sql"""
      INSERT INTO states (
        state_hash, state_json, sequence_length, last_mover,
        is_terminal, terminal_reason, winner, first_seen, has_children
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0)
    """,
      state.stateHash,
      $toJson(state),
      state.sequenceLength,
      lastMoverStr,
      (if isTerminal: 1 else: 0),
      terminalReason,
      winnerStr,
      now
    )
    return true
  else:
    return false

proc insertTransition*(
  gtdb: GameTreeDB,
  fromHash: string,
  toHash: string,
  moveId: string,
  mover: Player,
  damageInfo: DamageInfo
) =
  ## Insert transition with damage metadata
  let vulnsJson = $(%damageInfo.vulnerabilities.mapIt($it))

  gtdb.db.exec(sql"""
    INSERT OR IGNORE INTO state_transitions (
      from_hash, to_hash, move_id, mover,
      vulnerabilities_hit, damage_dealt, force_applied, hit_success
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
  """,
    fromHash, toHash, moveId, $mover,
    vulnsJson, damageInfo.damage, damageInfo.force,
    (if damageInfo.hit: 1 else: 0)
  )

proc insertPathDamage*(
  gtdb: GameTreeDB,
  stateHash: string,
  fromHash: string,
  damageP1: float,
  damageP2: float,
  hitCountP1: int,
  hitCountP2: int,
  criticalHits: seq[VulnerabilityHit]
) =
  ## Insert path damage record
  let criticalJson = $(%criticalHits.mapIt(%*{
    "zone": $it.zone,
    "force": it.force,
    "damage": it.damage,
    "target": $it.target
  }))

  gtdb.db.exec(sql"""
    INSERT OR REPLACE INTO path_damage (
      state_hash, from_hash, cumulative_damage_p1, cumulative_damage_p2,
      hit_count_p1, hit_count_p2, critical_hits
    ) VALUES (?, ?, ?, ?, ?, ?, ?)
  """,
    stateHash, fromHash, damageP1, damageP2,
    hitCountP1, hitCountP2, criticalJson
  )

# ============================================================================
# Path damage retrieval
# ============================================================================

proc getPathDamage*(gtdb: GameTreeDB, stateHash: string, fromHash: string): PathDamage =
  ## Get accumulated damage to this state
  let row = gtdb.db.getRow(sql"""
    SELECT cumulative_damage_p1, cumulative_damage_p2
    FROM path_damage
    WHERE state_hash = ? AND from_hash = ?
  """, stateHash, fromHash)

  if row[0] != "":
    result.damagePlayer1 = parseFloat(row[0])
    result.damagePlayer2 = parseFloat(row[1])
  else:
    result.damagePlayer1 = 0.0
    result.damagePlayer2 = 0.0

  result.hitHistory = @[]

# ============================================================================
# Tree expansion
# ============================================================================

proc expandLeafStates*(gtdb: GameTreeDB, batchSize: int = 100): int =
  ## Expand leaf states (no children yet)
  ## Returns number of new states created
  var newStatesCount = 0

  # Fetch leaf states
  let leafRows = gtdb.db.getAllRows(sql"""
    SELECT state_hash, state_json, last_mover, sequence_length
    FROM states
    WHERE has_children = 0
      AND is_terminal = 0
      AND sequence_length < 200
    ORDER BY sequence_length ASC
    LIMIT ?
  """, batchSize)

  for row in leafRows:
    let stateHash = row[0]
    let stateJson = parseJson(row[1])
    let lastMoverStr = row[2]
    let seqLen = parseInt(row[3])

    # Deserialize state
    var state = fromJson(stateJson, FightState)

    let lastMover = if lastMoverStr == "": none(Player)
                    else: some(parseEnum[Player](lastMoverStr))

    # Determine whose turn
    let currentPlayer = getNextPlayer(lastMover)
    let who = playerToFighter(currentPlayer)

    # Get viable moves (position-based only)
    let moves = viableMoves(state, who)

    if moves.len == 0:
      # No viable moves - terminal (trapped)
      let winner = if currentPlayer == Player1: some(Player2) else: some(Player1)
      discard gtdb.insertState(state, lastMover, true, "no_moves", winner)
      gtdb.db.exec(sql"UPDATE states SET has_children = 1 WHERE state_hash = ?", stateHash)
      continue

    # Get path damage to this state
    let pathDamage = gtdb.getPathDamage(stateHash, "")

    # Apply each move
    for move in moves:
      var newState = state
      move.apply(newState, who)
      newState.sequenceLength = seqLen + 1

      # Calculate damage dealt
      let damageInfo = calculateDamageDealt(state, newState, move, who)

      # Update path damage
      var newDamageP1 = pathDamage.damagePlayer1
      var newDamageP2 = pathDamage.damagePlayer2
      var newHitCountP1 = 0
      var newHitCountP2 = 0

      if damageInfo.hit:
        if currentPlayer == Player1:
          newDamageP2 += damageInfo.damage
          inc newHitCountP2
        else:
          newDamageP1 += damageInfo.damage
          inc newHitCountP1

      # Build hit history
      var newHitHistory = pathDamage.hitHistory
      if damageInfo.hit and damageInfo.vulnerabilities.len > 0:
        newHitHistory.add(VulnerabilityHit(
          zone: damageInfo.vulnerabilities[0],
          force: damageInfo.force,
          damage: damageInfo.damage,
          target: if currentPlayer == Player1: Player2 else: Player1
        ))

      # Check terminal WITH damage
      let (isTerm, reason, winner) = isTerminal(
        newState, newDamageP1, newDamageP2, newHitHistory
      )

      newState.stateHash = computeStateHash(newState)

      # Insert state
      let isNew = gtdb.insertState(
        newState,
        some(currentPlayer),
        isTerm,
        reason,
        winner
      )

      if isNew:
        inc newStatesCount

      # Insert transition
      gtdb.insertTransition(stateHash, newState.stateHash, move.id, currentPlayer, damageInfo)

      # Insert path damage
      gtdb.insertPathDamage(
        newState.stateHash,
        stateHash,
        newDamageP1,
        newDamageP2,
        newHitCountP1,
        newHitCountP2,
        newHitHistory
      )

    # Mark parent as expanded
    gtdb.db.exec(sql"UPDATE states SET has_children = 1 WHERE state_hash = ?", stateHash)

  return newStatesCount

# ============================================================================
# Main generation loop
# ============================================================================

proc generateGameTree*(
  gtdb: GameTreeDB,
  batchSize: int = 100,
  maxIterations: int = 10000
): TreeStats =
  ## Generate complete game tree
  var iteration = 0
  var totalNewStates = 0

  # Insert initial state
  let initialState = createInitialState()
  discard gtdb.insertState(initialState, none(Player), false, "", none(Player))

  echo "Starting game tree generation..."
  echo fmt"Initial state: {initialState.stateHash[0..7]}..."

  # Expand iteratively
  while iteration < maxIterations:
    let newStates = gtdb.expandLeafStates(batchSize)

    if newStates == 0:
      echo "No new states - tree complete or batch exhausted!"
      break

    totalNewStates += newStates
    inc iteration

    if iteration mod 10 == 0:
      echo fmt"Iteration {iteration}: +{newStates} states (total new: {totalNewStates})"

  # Gather stats
  result = getTreeStats(gtdb)

proc getTreeStats*(gtdb: GameTreeDB): TreeStats =
  ## Get statistics about the generated tree
  let totalRow = gtdb.db.getRow(sql"SELECT COUNT(*) FROM states")
  result.totalStates = parseInt(totalRow[0])

  let termRow = gtdb.db.getRow(sql"SELECT COUNT(*) FROM states WHERE is_terminal = 1")
  result.terminalStates = parseInt(termRow[0])

  let p1WinRow = gtdb.db.getRow(sql"SELECT COUNT(*) FROM states WHERE winner = 'Player1'")
  result.player1Wins = parseInt(p1WinRow[0])

  let p2WinRow = gtdb.db.getRow(sql"SELECT COUNT(*) FROM states WHERE winner = 'Player2'")
  result.player2Wins = parseInt(p2WinRow[0])

  result.draws = result.terminalStates - result.player1Wins - result.player2Wins

  let avgRow = gtdb.db.getRow(sql"""
    SELECT AVG(sequence_length) FROM states WHERE is_terminal = 1
  """)
  result.avgGameLength = if avgRow[0] != "": parseFloat(avgRow[0]) else: 0.0

  let maxRow = gtdb.db.getRow(sql"SELECT MAX(sequence_length) FROM states")
  result.maxDepth = if maxRow[0] != "": parseInt(maxRow[0]) else: 0

proc `$`*(stats: TreeStats): string =
  fmt"""
Game Tree Statistics:
  Total states: {stats.totalStates}
  Terminal states: {stats.terminalStates}
  Player1 wins: {stats.player1Wins}
  Player2 wins: {stats.player2Wins}
  Draws: {stats.draws}
  Average game length: {stats.avgGameLength:.1f} moves
  Max depth: {stats.maxDepth} moves
"""
