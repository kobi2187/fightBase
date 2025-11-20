## Fight Position Notation (FPN) - Like FEN for chess
## Deterministic, compact text representation of any fight state

import fight_types
import std/[strutils, strformat]

## FPN FORMAT:
## fighter_a/fighter_b/distance/turn/movecount
##
## Fighter format: stance.balance.fatigue.damage.momentum.biomech.limbs
##   stance: o=orthodox, s=southpaw, n=neutral, q=square, w=wide, r=narrow, b=bladed, z=wrestling
##   balance: 0-100 (percentage)
##   fatigue: 0-100 (percentage)
##   damage: 0-100 (percentage)
##   momentum: linear,rotational (m/s, deg/s, integers)
##   biomech: hip,torso,weight,recovering,frames (integers)
##   limbs: 4 chars for LA,RA,LL,RL where:
##     - = free
##     X = damaged >50%
##     E = extended
##     B = both damaged and extended
##
## Distance: c=contact, s=short, m=medium, l=long, v=very_long
## Turn: A or B
## Movecount: integer

proc stanceToChar(stance: StanceKind): char =
  case stance:
  of skOrthodox: 'o'
  of skSouthpaw: 's'
  of skNeutral: 'n'
  of skSquare: 'q'
  of skWide: 'w'
  of skNarrow: 'r'
  of skBladed: 'b'
  of skWrestling: 'z'

proc charToStance(c: char): StanceKind =
  case c:
  of 'o': skOrthodox
  of 's': skSouthpaw
  of 'n': skNeutral
  of 'q': skSquare
  of 'w': skWide
  of 'r': skNarrow
  of 'b': skBladed
  of 'z': skWrestling
  else: skNeutral

proc limbToChar(limb: LimbStatus): char =
  if limb.damaged > 0.5 and limb.extended:
    'B'
  elif limb.damaged > 0.5:
    'X'
  elif limb.extended:
    'E'
  else:
    '-'

proc charToLimb(c: char): LimbStatus =
  case c:
  of 'B': LimbStatus(free: false, extended: true, damaged: 0.6, angle: 0.0)
  of 'X': LimbStatus(free: false, extended: false, damaged: 0.6, angle: 0.0)
  of 'E': LimbStatus(free: true, extended: true, damaged: 0.0, angle: 0.0)
  else:   LimbStatus(free: true, extended: false, damaged: 0.0, angle: 0.0)

proc distanceToChar(dist: DistanceKind): char =
  case dist:
  of Contact: 'c'
  of Short: 's'
  of Medium: 'm'
  of Long: 'l'
  of VeryLong: 'v'

proc charToDistance(c: char): DistanceKind =
  case c:
  of 'c': Contact
  of 's': Short
  of 'm': Medium
  of 'l': Long
  of 'v': VeryLong
  else: Medium

proc fighterToFPN(f: Fighter): string =
  ## Convert fighter to compact notation
  let stance = stanceToChar(f.pos.stance)
  let balance = int(f.pos.balance * 100.0)
  let fatigue = int(f.fatigue * 100.0)
  let damage = int(f.damage * 100.0)
  let linearMom = int(f.momentum.linear * 10.0)  # Store as deciseconds
  let rotMom = int(f.momentum.rotational)
  let hipRot = int(f.biomech.hipRotation)
  let torsoRot = int(f.biomech.torsoRotation)
  let weight = int(f.biomech.weightDistribution * 100.0)
  let recovering = if f.biomech.recovering: '1' else: '0'
  let frames = f.biomech.recoveryFrames

  let limbs = $limbToChar(f.leftArm) &
              $limbToChar(f.rightArm) &
              $limbToChar(f.leftLeg) &
              $limbToChar(f.rightLeg)

  result = fmt"{stance}.{balance}.{fatigue}.{damage}.{linearMom},{rotMom}.{hipRot},{torsoRot},{weight},{recovering},{frames}.{limbs}"

proc fpnToFighter(fpn: string): Fighter =
  ## Parse fighter from FPN notation
  let parts = fpn.split('.')
  if parts.len != 7:
    raise newException(ValueError, "Invalid fighter FPN: " & fpn)

  let stance = charToStance(parts[0][0])
  let balance = parseInt(parts[1]).float / 100.0
  let fatigue = parseInt(parts[2]).float / 100.0
  let damage = parseInt(parts[3]).float / 100.0

  let momParts = parts[4].split(',')
  let linearMom = parseInt(momParts[0]).float / 10.0
  let rotMom = parseInt(momParts[1]).float

  let biomechParts = parts[5].split(',')
  let hipRot = parseInt(biomechParts[0]).float
  let torsoRot = parseInt(biomechParts[1]).float
  let weight = parseInt(biomechParts[2]).float / 100.0
  let recovering = biomechParts[3] == "1"
  let frames = parseInt(biomechParts[4])

  let limbs = parts[6]

  result = Fighter(
    pos: Position3D(
      x: 0.0, y: 0.0, z: 0.0,  # Position not stored in FPN (only stance/balance matter)
      facing: 0.0,
      stance: stance,
      balance: balance
    ),
    leftArm: charToLimb(limbs[0]),
    rightArm: charToLimb(limbs[1]),
    leftLeg: charToLimb(limbs[2]),
    rightLeg: charToLimb(limbs[3]),
    fatigue: fatigue,
    damage: damage,
    liveSide: Centerline,  # Not stored in basic FPN
    control: None,
    momentum: Momentum(
      linear: linearMom,
      rotational: rotMom,
      decayRate: 0.1
    ),
    biomech: BiomechanicalState(
      hipRotation: hipRot,
      torsoRotation: torsoRot,
      weightDistribution: weight,
      recovering: recovering,
      recoveryFrames: frames
    )
  )

proc toFPN*(state: FightState, currentTurn: FighterID = FighterA): string =
  ## Convert complete fight state to FPN notation
  let fighterA = fighterToFPN(state.a)
  let fighterB = fighterToFPN(state.b)
  let dist = distanceToChar(state.distance)
  let turn = if currentTurn == FighterA: 'A' else: 'B'
  let moves = state.sequenceLength

  result = fmt"{fighterA}/{fighterB}/{dist}/{turn}/{moves}"

proc fromFPN*(fpn: string): tuple[state: FightState, turn: FighterID] =
  ## Parse FPN notation into fight state
  let parts = fpn.split('/')
  if parts.len != 5:
    raise newException(ValueError, "Invalid FPN: " & fpn)

  result.state = FightState(
    a: fpnToFighter(parts[0]),
    b: fpnToFighter(parts[1]),
    distance: charToDistance(parts[2][0]),
    sequenceLength: parseInt(parts[4]),
    terminal: false,
    winner: none(FighterID)
  )

  result.turn = if parts[3][0] == 'A': FighterA else: FighterB

## ============================================================================
## Fight Move Notation (FMN) - Like PGN for chess
## ============================================================================

## FMN FORMAT (move recording):
## 1. move_id [target] {result}
## 2. move_id [target] {result}
## ...
##
## Example:
## 1. step_forward {} slip_left {}
## 2. straight_strike [vzNose] {hit}
## 3. low_kick [vzThighMuscle] {miss}

type
  MoveRecord* = object
    moveId*: string
    target*: string          # Empty if non-offensive
    result*: MoveResult

  MoveResult* = enum
    mrPending    # Not yet executed
    mrHit        # Connected
    mrMiss       # Missed
    mrBlocked    # Blocked/deflected
    mrParried    # Parried

  FightRecord* = object
    initialFPN*: string
    moves*: seq[seq[MoveRecord]]  # Each ply can have multiple moves
    comments*: seq[string]
    result*: string              # "A wins", "B wins", "Unknown state", etc

proc moveResultToStr(r: MoveResult): string =
  case r:
  of mrPending: "?"
  of mrHit: "hit"
  of mrMiss: "miss"
  of mrBlocked: "blocked"
  of mrParried: "parried"

proc strToMoveResult(s: string): MoveResult =
  case s:
  of "hit": mrHit
  of "miss": mrMiss
  of "blocked": mrBlocked
  of "parried": mrParried
  else: mrPending

proc toFMN*(record: FightRecord): string =
  ## Convert fight record to FMN notation
  result = "[FPN \"" & record.initialFPN & "\"]\n"
  result.add("[Result \"" & record.result & "\"]\n\n")

  for plyIdx, ply in record.moves:
    result.add($(plyIdx + 1) & ". ")
    for moveIdx, move in ply:
      if moveIdx > 0:
        result.add(" ")
      result.add(move.moveId)
      if move.target != "":
        result.add("[" & move.target & "]")
      result.add("{" & moveResultToStr(move.result) & "}")
    result.add("\n")

    if plyIdx < record.comments.len and record.comments[plyIdx] != "":
      result.add("  # " & record.comments[plyIdx] & "\n")

proc fromFMN*(fmn: string): FightRecord =
  ## Parse FMN notation
  ## Simplified parser for now
  result.moves = @[]
  result.comments = @[]

  for line in fmn.splitLines():
    if line.startsWith("[FPN"):
      let start = line.find('"') + 1
      let endIdx = line.find('"', start)
      result.initialFPN = line[start..<endIdx]
    elif line.startsWith("[Result"):
      let start = line.find('"') + 1
      let endIdx = line.find('"', start)
      result.result = line[start..<endIdx]

## ============================================================================
## Visual Board Representation (like ASCII chess boards)
## ============================================================================

proc toVisualBoard*(state: FightState, currentTurn: FighterID = FighterA): string =
  ## Create ASCII visualization of fight state
  result = ""
  result.add("╔═══════════════════════════════════════════════════════════╗\n")
  result.add("║                    FIGHT STATE                            ║\n")
  result.add("╠═══════════════════════════════════════════════════════════╣\n")

  # Fighter A
  result.add(fmt"║ Fighter A ({stanceToChar(state.a.pos.stance)})                                               ║" & "\n")
  result.add(fmt"║   Balance: {int(state.a.pos.balance*100):3}%  Fatigue: {int(state.a.fatigue*100):3}%  Damage: {int(state.a.damage*100):3}%   ║" & "\n")

  let aLimbs = $limbToChar(state.a.leftArm) & $limbToChar(state.a.rightArm) &
               $limbToChar(state.a.leftLeg) & $limbToChar(state.a.rightLeg)
  result.add(fmt"║   Limbs: {aLimbs}  Momentum: {int(state.a.momentum.linear*10):+3} lin, {int(state.a.momentum.rotational):+3} rot ║" & "\n")

  # Distance
  let distStr = case state.distance:
    of Contact: "CONTACT"
    of Short: "SHORT"
    of Medium: "MEDIUM"
    of Long: "LONG"
    of VeryLong: "VERY LONG"

  result.add("║                                                           ║\n")
  result.add(fmt"║                  ←  {distStr:^10}  →                  ║" & "\n")
  result.add("║                                                           ║\n")

  # Fighter B
  result.add(fmt"║ Fighter B ({stanceToChar(state.b.pos.stance)})                                               ║" & "\n")
  result.add(fmt"║   Balance: {int(state.b.pos.balance*100):3}%  Fatigue: {int(state.b.fatigue*100):3}%  Damage: {int(state.b.damage*100):3}%   ║" & "\n")

  let bLimbs = $limbToChar(state.b.leftArm) & $limbToChar(state.b.rightArm) &
               $limbToChar(state.b.leftLeg) & $limbToChar(state.b.rightLeg)
  result.add(fmt"║   Limbs: {bLimbs}  Momentum: {int(state.b.momentum.linear*10):+3} lin, {int(state.b.momentum.rotational):+3} rot ║" & "\n")

  # Footer
  result.add("╠═══════════════════════════════════════════════════════════╣\n")
  let turnStr = if currentTurn == FighterA: "A" else: "B"
  result.add(fmt"║ Turn: {turnStr}   Move: {state.sequenceLength:3}                                      ║" & "\n")
  result.add("╚═══════════════════════════════════════════════════════════╝\n")

proc toCompactBoard*(state: FightState): string =
  ## Ultra-compact single-line representation
  let aStance = stanceToChar(state.a.pos.stance)
  let bStance = stanceToChar(state.b.pos.stance)
  let dist = distanceToChar(state.distance)
  let aBal = int(state.a.pos.balance * 10)
  let bBal = int(state.b.pos.balance * 10)
  let aFat = int(state.a.fatigue * 10)
  let bFat = int(state.b.fatigue * 10)
  let aDmg = int(state.a.damage * 10)
  let bDmg = int(state.b.damage * 10)

  result = fmt"A:{aStance}{aBal}{aFat}{aDmg} <{dist}> B:{bStance}{bBal}{bFat}{bDmg} #{state.sequenceLength}"

## ============================================================================
## Examples and Tests
## ============================================================================

when isMainModule:
  # Test FPN encoding/decoding
  let testState = FightState(
    a: Fighter(
      pos: Position3D(x: -1.5, y: 0.0, z: 0.0, facing: 90.0, stance: skOrthodox, balance: 0.95),
      leftArm: LimbStatus(free: true, extended: false, damaged: 0.0, angle: 0.0),
      rightArm: LimbStatus(free: true, extended: false, damaged: 0.0, angle: 0.0),
      leftLeg: LimbStatus(free: true, extended: false, damaged: 0.0, angle: 0.0),
      rightLeg: LimbStatus(free: true, extended: false, damaged: 0.0, angle: 0.0),
      fatigue: 0.15,
      damage: 0.0,
      liveSide: Centerline,
      control: None,
      momentum: Momentum(linear: 0.3, rotational: 5.0, decayRate: 0.1),
      biomech: BiomechanicalState(
        hipRotation: 10.0,
        torsoRotation: 15.0,
        weightDistribution: 0.55,
        recovering: false,
        recoveryFrames: 0
      )
    ),
    b: Fighter(
      pos: Position3D(x: 1.5, y: 0.0, z: 0.0, facing: 270.0, stance: skSouthpaw, balance: 0.90),
      leftArm: LimbStatus(free: true, extended: false, damaged: 0.0, angle: 0.0),
      rightArm: LimbStatus(free: true, extended: false, damaged: 0.0, angle: 0.0),
      leftLeg: LimbStatus(free: true, extended: false, damaged: 0.0, angle: 0.0),
      rightLeg: LimbStatus(free: true, extended: false, damaged: 0.0, angle: 0.0),
      fatigue: 0.20,
      damage: 0.05,
      liveSide: Centerline,
      control: None,
      momentum: Momentum(linear: -0.1, rotational: 0.0, decayRate: 0.1),
      biomech: BiomechanicalState(
        hipRotation: -5.0,
        torsoRotation: -10.0,
        weightDistribution: 0.45,
        recovering: false,
        recoveryFrames: 0
      )
    ),
    distance: Medium,
    sequenceLength: 5,
    terminal: false,
    winner: none(FighterID)
  )

  echo "=== FPN Test ==="
  let fpn = toFPN(testState, FighterA)
  echo "FPN: ", fpn
  echo ""

  echo "=== Visual Board ==="
  echo toVisualBoard(testState, FighterA)
  echo ""

  echo "=== Compact Board ==="
  echo toCompactBoard(testState)
