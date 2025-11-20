## Generate SVG stick figure visualization from FPN notation
## Usage: fpn_to_svg "o.95.15.0.3,5.10,15,55,0,0.----/s.90.20.5.-1,0.-5,-10,45,0,0.----/m/A/5" output.svg

import fight_types
import fight_notation
import std/[strformat, strutils, math]

type
  Point = tuple[x, y: float]

  StickFigure = object
    head: Point
    torso: Point
    hips: Point
    leftShoulder: Point
    rightShoulder: Point
    leftElbow: Point
    rightElbow: Point
    leftHand: Point
    rightHand: Point
    leftKnee: Point
    rightKnee: Point
    leftFoot: Point
    rightFoot: Point

const
  CANVAS_WIDTH = 800.0
  CANVAS_HEIGHT = 600.0
  FIGURE_HEIGHT = 200.0
  HEAD_RADIUS = 15.0

proc calculateStickFigure(fighter: Fighter, centerX: float, facingRight: bool): StickFigure =
  ## Calculate stick figure joint positions based on fighter state

  let baseY = CANVAS_HEIGHT * 0.7  # Ground level

  # Adjust height based on stance
  let heightFactor = case fighter.pos.stance:
    of skWrestling: 0.8  # Lower
    of skWide: 0.9
    of skSquare: 0.95
    else: 1.0

  let height = FIGURE_HEIGHT * heightFactor

  # Balance affects lean
  let balanceLean = (1.0 - fighter.pos.balance) * 20.0  # More lean if unbalanced
  let leanDirection = if facingRight: balanceLean else: -balanceLean

  # Hip and torso rotation affect posture
  let hipRot = degToRad(fighter.biomech.hipRotation) * 0.3  # Scale down for visual
  let torsoRot = degToRad(fighter.biomech.torsoRotation) * 0.3

  # Head
  result.head = (
    x: centerX + leanDirection,
    y: baseY - height
  )

  # Torso (neck to hips)
  let torsoTop = baseY - height + HEAD_RADIUS
  let torsoBottom = baseY - height * 0.4

  result.torso = (
    x: centerX + sin(torsoRot) * 20.0,
    y: torsoTop + 30.0
  )

  result.hips = (
    x: centerX + sin(hipRot) * 15.0,
    y: torsoBottom
  )

  # Shoulders
  let shoulderWidth = 40.0
  let shoulderY = result.torso.y

  result.leftShoulder = (
    x: result.torso.x - shoulderWidth/2 * cos(torsoRot),
    y: shoulderY
  )

  result.rightShoulder = (
    x: result.torso.x + shoulderWidth/2 * cos(torsoRot),
    y: shoulderY
  )

  # Arms - adjust based on stance and limb status
  let armExtension = if facingRight: 50.0 else: 40.0

  # Left arm
  let leftArmExtended = fighter.leftArm.extended
  let leftArmAngle = if leftArmExtended:
      (if facingRight: -0.3 else: 0.3)
    else:
      -1.0  # Bent, guard position

  result.leftElbow = (
    x: result.leftShoulder.x + cos(leftArmAngle) * 30.0,
    y: result.leftShoulder.y + sin(leftArmAngle) * 30.0
  )

  result.leftHand = (
    x: result.leftElbow.x + cos(leftArmAngle) * armExtension,
    y: result.leftElbow.y + sin(leftArmAngle) * armExtension
  )

  # Right arm
  let rightArmExtended = fighter.rightArm.extended
  let rightArmAngle = if rightArmExtended:
      (if facingRight: -0.3 else: 0.3)
    else:
      -0.8  # Guard position

  result.rightElbow = (
    x: result.rightShoulder.x + cos(rightArmAngle) * 30.0,
    y: result.rightShoulder.y + sin(rightArmAngle) * 30.0
  )

  result.rightHand = (
    x: result.rightElbow.x + cos(rightArmAngle) * armExtension,
    y: result.rightElbow.y + sin(rightArmAngle) * armExtension
  )

  # Legs - stance affects positioning
  let legSpread = case fighter.pos.stance:
    of skOrthodox, skSouthpaw: 30.0
    of skWide: 50.0
    of skSquare: 40.0
    of skWrestling: 60.0
    else: 35.0

  let frontLegForward = if fighter.pos.stance in {skOrthodox, skSouthpaw}: 20.0 else: 0.0

  # Left leg
  let leftLegExtended = fighter.leftLeg.extended
  let leftKneeY = if leftLegExtended:
    result.hips.y + 40.0  # Straighter
  else:
    result.hips.y + 50.0  # More bent

  result.leftKnee = (
    x: result.hips.x - legSpread/2,
    y: leftKneeY
  )

  result.leftFoot = (
    x: result.leftKnee.x - 5.0 + (if fighter.pos.stance == skOrthodox: frontLegForward else: 0.0),
    y: baseY
  )

  # Right leg
  let rightLegExtended = fighter.rightLeg.extended
  let rightKneeY = if rightLegExtended:
    result.hips.y + 40.0
  else:
    result.hips.y + 50.0

  result.rightKnee = (
    x: result.hips.x + legSpread/2,
    y: rightKneeY
  )

  result.rightFoot = (
    x: result.rightKnee.x + 5.0 + (if fighter.pos.stance == skSouthpaw: frontLegForward else: 0.0),
    y: baseY
  )

proc svgLine(p1, p2: Point, color: string = "black", width: float = 3.0, damaged: bool = false): string =
  let style = if damaged:
    fmt"""stroke="{color}" stroke-width="{width}" stroke-dasharray="5,5" opacity="0.5""""
  else:
    fmt"""stroke="{color}" stroke-width="{width}""""

  result = fmt"""<line x1="{p1.x:.1f}" y1="{p1.y:.1f}" x2="{p2.x:.1f}" y2="{p2.y:.1f}" {style}/>"""

proc svgCircle(p: Point, radius: float, color: string = "black", fill: string = "white"): string =
  result = fmt"""<circle cx="{p.x:.1f}" cy="{p.y:.1f}" r="{radius:.1f}" stroke="{color}" stroke-width="2" fill="{fill}"/>"""

proc getColorForDamage(damage: float, fatigue: float): string =
  ## Return color based on fighter condition
  if damage > 0.5:
    "red"
  elif damage > 0.2:
    "orange"
  elif fatigue > 0.7:
    "blue"
  elif fatigue > 0.4:
    "darkblue"
  else:
    "black"

proc generateSVG*(fpnString: string): string =
  ## Generate complete SVG from FPN string

  let (state, turn) = fromFPN(fpnString)

  # Calculate figure positions
  let fighterAX = CANVAS_WIDTH * 0.25
  let fighterBX = CANVAS_WIDTH * 0.75

  let figA = calculateStickFigure(state.a, fighterAX, facingRight = true)
  let figB = calculateStickFigure(state.b, fighterBX, facingRight = false)

  let colorA = getColorForDamage(state.a.damage, state.a.fatigue)
  let colorB = getColorForDamage(state.b.damage, state.b.fatigue)

  # Start SVG
  result = fmt"""<?xml version="1.0" encoding="UTF-8"?>
<svg width="{CANVAS_WIDTH:.0f}" height="{CANVAS_HEIGHT:.0f}" xmlns="http://www.w3.org/2000/svg">
  <!-- Background -->
  <rect width="{CANVAS_WIDTH:.0f}" height="{CANVAS_HEIGHT:.0f}" fill="#f5f5f5"/>

  <!-- Ground line -->
  <line x1="0" y1="{CANVAS_HEIGHT * 0.7:.1f}" x2="{CANVAS_WIDTH:.0f}" y2="{CANVAS_HEIGHT * 0.7:.1f}" stroke="#999" stroke-width="2"/>

  <!-- Distance indicator -->
"""

  # Distance line between fighters
  let distanceY = CANVAS_HEIGHT * 0.15
  let distStr = $state.distance
  result.add(fmt"""  <line x1="{fighterAX:.1f}" y1="{distanceY:.1f}" x2="{fighterBX:.1f}" y2="{distanceY:.1f}" stroke="#666" stroke-width="2" stroke-dasharray="5,5"/>""" & "\n")
  result.add(fmt"""  <text x="{CANVAS_WIDTH/2:.1f}" y="{distanceY - 5:.1f}" text-anchor="middle" font-family="Arial" font-size="14" fill="#666">{distStr}</text>""" & "\n")

  # Fighter A
  result.add(fmt"""  <!-- Fighter A ({$state.a.pos.stance}) -->""" & "\n")
  result.add("  " & svgLine(figA.head, figA.torso, colorA) & "\n")
  result.add("  " & svgLine(figA.torso, figA.hips, colorA) & "\n")

  # Arms
  result.add("  " & svgLine(figA.leftShoulder, figA.leftElbow, colorA, 2.5, state.a.leftArm.damaged > 0.5) & "\n")
  result.add("  " & svgLine(figA.leftElbow, figA.leftHand, colorA, 2.5, state.a.leftArm.damaged > 0.5) & "\n")
  result.add("  " & svgLine(figA.rightShoulder, figA.rightElbow, colorA, 2.5, state.a.rightArm.damaged > 0.5) & "\n")
  result.add("  " & svgLine(figA.rightElbow, figA.rightHand, colorA, 2.5, state.a.rightArm.damaged > 0.5) & "\n")

  # Legs
  result.add("  " & svgLine(figA.hips, figA.leftKnee, colorA, 3.0, state.a.leftLeg.damaged > 0.5) & "\n")
  result.add("  " & svgLine(figA.leftKnee, figA.leftFoot, colorA, 3.0, state.a.leftLeg.damaged > 0.5) & "\n")
  result.add("  " & svgLine(figA.hips, figA.rightKnee, colorA, 3.0, state.a.rightLeg.damaged > 0.5) & "\n")
  result.add("  " & svgLine(figA.rightKnee, figA.rightFoot, colorA, 3.0, state.a.rightLeg.damaged > 0.5) & "\n")

  # Head
  let headFillA = if state.a.damage > 0.5: "#ffcccc" else: "white"
  result.add("  " & svgCircle(figA.head, HEAD_RADIUS, colorA, headFillA) & "\n")

  # Fighter B
  result.add(fmt"""  <!-- Fighter B ({$state.b.pos.stance}) -->""" & "\n")
  result.add("  " & svgLine(figB.head, figB.torso, colorB) & "\n")
  result.add("  " & svgLine(figB.torso, figB.hips, colorB) & "\n")

  # Arms
  result.add("  " & svgLine(figB.leftShoulder, figB.leftElbow, colorB, 2.5, state.b.leftArm.damaged > 0.5) & "\n")
  result.add("  " & svgLine(figB.leftElbow, figB.leftHand, colorB, 2.5, state.b.leftArm.damaged > 0.5) & "\n")
  result.add("  " & svgLine(figB.rightShoulder, figB.rightElbow, colorB, 2.5, state.b.rightArm.damaged > 0.5) & "\n")
  result.add("  " & svgLine(figB.rightElbow, figB.rightHand, colorB, 2.5, state.b.rightArm.damaged > 0.5) & "\n")

  # Legs
  result.add("  " & svgLine(figB.hips, figB.leftKnee, colorB, 3.0, state.b.leftLeg.damaged > 0.5) & "\n")
  result.add("  " & svgLine(figB.leftKnee, figB.leftFoot, colorB, 3.0, state.b.leftLeg.damaged > 0.5) & "\n")
  result.add("  " & svgLine(figB.hips, figB.rightKnee, colorB, 3.0, state.b.rightLeg.damaged > 0.5) & "\n")
  result.add("  " & svgLine(figB.rightKnee, figB.rightFoot, colorB, 3.0, state.b.rightLeg.damaged > 0.5) & "\n")

  # Head
  let headFillB = if state.b.damage > 0.5: "#ffcccc" else: "white"
  result.add("  " & svgCircle(figB.head, HEAD_RADIUS, colorB, headFillB) & "\n")

  # Status info
  result.add("\n  <!-- Status Info -->\n")

  # Fighter A stats
  let balA = int(state.a.pos.balance * 100)
  let fatA = int(state.a.fatigue * 100)
  let dmgA = int(state.a.damage * 100)
  result.add(fmt"""  <text x="{fighterAX:.1f}" y="30" text-anchor="middle" font-family="monospace" font-size="12" fill="{colorA}">Fighter A</text>""" & "\n")
  result.add(fmt"""  <text x="{fighterAX:.1f}" y="45" text-anchor="middle" font-family="monospace" font-size="10" fill="{colorA}">Bal:{balA}% Fat:{fatA}% Dmg:{dmgA}%</text>""" & "\n")

  # Fighter B stats
  let balB = int(state.b.pos.balance * 100)
  let fatB = int(state.b.fatigue * 100)
  let dmgB = int(state.b.damage * 100)
  result.add(fmt"""  <text x="{fighterBX:.1f}" y="30" text-anchor="middle" font-family="monospace" font-size="12" fill="{colorB}">Fighter B</text>""" & "\n")
  result.add(fmt"""  <text x="{fighterBX:.1f}" y="45" text-anchor="middle" font-family="monospace" font-size="10" fill="{colorB}">Bal:{balB}% Fat:{fatB}% Dmg:{dmgB}%</text>""" & "\n")

  # Turn indicator
  let turnText = if turn == FighterA: "Fighter A's turn" else: "Fighter B's turn"
  result.add(fmt"""  <text x="{CANVAS_WIDTH/2:.1f}" y="{CANVAS_HEIGHT - 20:.1f}" text-anchor="middle" font-family="Arial" font-size="14" fill="#333">Move #{state.sequenceLength} - {turnText}</text>""" & "\n")

  # FPN string at bottom
  result.add(fmt"""  <text x="{CANVAS_WIDTH/2:.1f}" y="{CANVAS_HEIGHT - 5:.1f}" text-anchor="middle" font-family="monospace" font-size="8" fill="#999">{fpnString}</text>""" & "\n")

  result.add("</svg>\n")

when isMainModule:
  import os

  if paramCount() < 1:
    echo "Usage: fpn_to_svg <FPN_string> [output.svg]"
    echo ""
    echo "Example:"
    echo "  fpn_to_svg \"o.95.15.0.3,5.10,15,55,0,0.----/s.90.20.5.-1,0.-5,-10,45,0,0.----/m/A/5\" fight.svg"
    quit(1)

  let fpnString = paramStr(1)
  let outputFile = if paramCount() >= 2: paramStr(2) else: "fight.svg"

  try:
    let svg = generateSVG(fpnString)
    writeFile(outputFile, svg)
    echo "✓ Generated: ", outputFile
    echo "  Open in browser to view"
  except Exception as e:
    echo "Error: ", e.msg
    quit(1)
