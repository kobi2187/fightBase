## Textual representation of fight states for human review

import std/[strformat, strutils, options]
import fight_types

proc toLimbStatusStr*(limb: LimbPosition): string =
  var parts: seq[string]
  if not limb.free: parts.add("TRAPPED")
  if limb.extended: parts.add("extended")
  if limb.angle != 0.0: parts.add(fmt"angle({limb.angle:.1f}°)")
  if parts.len == 0:
    "ready"
  else:
    parts.join(", ")

proc toFighterStr*(f: Fighter, label: string): string =
  result = fmt"""
Fighter {label}:
  Position: ({f.pos.x:.2f}, {f.pos.y:.2f}, {f.pos.z:.2f})
  Facing: {f.pos.facing:.0f}° | Stance: {f.pos.stance} | Balance: {f.pos.balance:.2f}
  Posture: {f.posture} | Side: {f.liveSide} | Control: {f.control}
  Left arm:  {toLimbStatusStr(f.leftArm)}
  Right arm: {toLimbStatusStr(f.rightArm)}
  Left leg:  {toLimbStatusStr(f.leftLeg)}
  Right leg: {toLimbStatusStr(f.rightLeg)}"""

proc toTextRepr*(state: FightState): string =
  ## Generates a complete human-readable text representation
  result = "=" .repeat(70) & "\n"
  result &= fmt"FIGHT STATE (Hash: {state.stateHash[0..7]}...)" & "\n"
  result &= fmt"Sequence Length: {state.sequenceLength} | Distance: {state.distance}" & "\n"

  if state.terminal:
    result &= fmt"TERMINAL STATE - Winner: {state.winner.get()}" & "\n"

  result &= "=" .repeat(70) & "\n"
  result &= toFighterStr(state.a, "A")
  result &= "\n\n"
  result &= toFighterStr(state.b, "B")
  result &= "\n" & "=" .repeat(70) & "\n"

proc toCompactRepr*(state: FightState): string =
  ## Compact one-line representation for logs
  let aStatus = fmt"A[{state.a.posture} bal:{state.a.pos.balance:.1f}]"
  let bStatus = fmt"B[{state.b.posture} bal:{state.b.pos.balance:.1f}]"
  let ctrl = if state.a.control != None: fmt" ctrl:{state.a.control}" else: ""
  result = fmt"{aStatus} <-{state.distance}-> {bStatus}{ctrl}"

proc toAnalysisStr*(state: FightState): string =
  ## Analysis-focused representation highlighting key tactical factors
  result = fmt"Distance: {state.distance} | Seq: {state.sequenceLength}" & "\n"

  # Posture comparison
  let postureComp =
    if state.a.posture != state.b.posture: fmt"A:{state.a.posture} vs B:{state.b.posture}"
    else: fmt"both {state.a.posture}"

  # Balance comparison
  let balanceComp =
    if state.a.pos.balance < 0.5: "A unstable"
    elif state.b.pos.balance < 0.5: "B unstable"
    else: "both stable"

  # Control status
  let controlStatus =
    if state.a.control != None: fmt"A has {state.a.control}"
    elif state.b.control != None: fmt"B has {state.b.control}"
    else: "no control"

  result &= fmt"  {postureComp} | {balanceComp} | {controlStatus}" & "\n"

  # Limb availability
  var aLimbs = 0
  if state.a.leftArm.free: inc aLimbs
  if state.a.rightArm.free: inc aLimbs
  if state.a.leftLeg.free: inc aLimbs
  if state.a.rightLeg.free: inc aLimbs

  var bLimbs = 0
  if state.b.leftArm.free: inc bLimbs
  if state.b.rightArm.free: inc bLimbs
  if state.b.leftLeg.free: inc bLimbs
  if state.b.rightLeg.free: inc bLimbs

  result &= fmt"  A has {aLimbs}/4 limbs free | B has {bLimbs}/4 limbs free"

proc toMoveDescription*(move: Move): string =
  ## Human-readable move description
  result = fmt"{move.name} ({move.category})"
  result &= fmt" - Energy: {move.energyCost:.2f}, Reach: {move.reach:.2f}m, Height: {move.height}"
  if move.styleOrigins.len > 0:
    result &= " - Origins: " & move.styleOrigins.join(", ")
