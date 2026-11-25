## MPN (Mannequin Position Notation) - Pure Physical Pose
## Focus: Joint angles and body configuration for visualization
## Not game state (fatigue/damage), just the physical pose resulting from moves

import fight_types
import std/[strformat, strutils, math]

type
  MannequinPose* = object
    ## Physical pose of a mannequin (MPN v2). Every angle is in degrees and
    ## flexion is positive, the same conventions as fpn_3d_viewer.html:
    ##   * leanForwardBack > 0 leans toward the opponent; leanLeftRight > 0 leans
    ##     to the fighter's left.
    ##   * hip/torso/neck rotation > 0 turns the front toward the fighter's left
    ##     (the right side comes forward). An orthodox stance is bladed at about -35.
    ##   * *Pitch = flexion (raising the limb forward), *Roll = abduction (away
    ##     from the midline), *Yaw = internal rotation (front of the limb toward
    ##     the midline).
    ##   * elbow/knee bend: 0 = straight.
    leanForwardBack*: float
    leanLeftRight*: float
    hipRotation*: float
    torsoRotation*: float
    neckRotation*: float          # offset on top of looking at the opponent

    leftShoulderPitch*: float
    leftShoulderRoll*: float
    leftShoulderYaw*: float
    rightShoulderPitch*: float
    rightShoulderRoll*: float
    rightShoulderYaw*: float

    leftElbowBend*: float
    rightElbowBend*: float

    leftHipPitch*: float
    leftHipRoll*: float
    leftHipYaw*: float
    rightHipPitch*: float
    rightHipRoll*: float
    rightHipYaw*: float

    leftKneeBend*: float
    rightKneeBend*: float

    stanceWidth*: float           # metres between the feet (sideways)
    facingAngle*: float           # degrees; kept for the legacy format only

## MPN v2 (one fighter):
##   v2:lean.rotation.shoulders.elbows.hips.knees.stance
##     lean      fwd,side
##     rotation  hip,torso,neck
##     shoulders lFlex,lAbd,lRot,rFlex,rAbd,rRot
##     elbows    l,r
##     hips      lFlex,lAbd,lRot,rFlex,rAbd,rRot
##     knees     l,r
##     stance    width_cm
## Values are integers. A scene is `A/B/distance` (distance c, s, m, l or v).
## The legacy format (no `v2:` prefix: lean in cm, shoulder pitch negative =
## forward, a facing angle after the stance width) is still read.

proc r(x: float): string = $int(round(x))

proc poseToMPN*(pose: MannequinPose): string =
  ## Compact MPN v2 string for one fighter.
  let p = pose
  "v2:" & [
    [r p.leanForwardBack, r p.leanLeftRight].join(","),
    [r p.hipRotation, r p.torsoRotation, r p.neckRotation].join(","),
    [r p.leftShoulderPitch, r p.leftShoulderRoll, r p.leftShoulderYaw,
     r p.rightShoulderPitch, r p.rightShoulderRoll, r p.rightShoulderYaw].join(","),
    [r p.leftElbowBend, r p.rightElbowBend].join(","),
    [r p.leftHipPitch, r p.leftHipRoll, r p.leftHipYaw,
     r p.rightHipPitch, r p.rightHipRoll, r p.rightHipYaw].join(","),
    [r p.leftKneeBend, r p.rightKneeBend].join(","),
    r(p.stanceWidth * 100)].join(".")

proc mpnToPose*(mpn: string): MannequinPose =
  ## Parse one fighter's MPN (v2, or the legacy format).
  let v2 = mpn.startsWith("v2:")
  let parts = (if v2: mpn[3 .. ^1] else: mpn).split('.')
  if parts.len != 7:
    raise newException(ValueError, "Invalid MPN format: expected 7 parts, got " & $parts.len)
  var g: seq[seq[float]]
  for part in parts:
    var vals: seq[float]
    for x in part.split(','): vals.add parseFloat(x.strip)
    g.add vals
  proc need(i, n: int) =
    if g[i].len < n:
      raise newException(ValueError, "Invalid MPN format: group " & $(i + 1) & " needs " & $n & " values")
  need(0, 2); need(1, 3); need(3, 2); need(5, 2); need(6, 1)
  # Shoulders and hips: 6 values (flex, abd, rot per side) or legacy 4 (pitch, roll).
  proc six(i: int): seq[float] =
    if g[i].len >= 6: g[i][0 .. 5]
    elif g[i].len == 4: @[g[i][0], g[i][1], 0.0, g[i][2], g[i][3], 0.0]
    else: raise newException(ValueError, "Invalid MPN format: group " & $(i + 1) & " needs 4 or 6 values")
  let sh = six(2)
  let hp = six(4)
  if v2:
    result.leanForwardBack = g[0][0]
    result.leanLeftRight = g[0][1]
    result.leftShoulderPitch = sh[0]
    result.rightShoulderPitch = sh[3]
  else:
    # Legacy: lean in cm on a ~60 cm lever, positive side lean = right;
    # shoulder pitch negative = forward.
    result.leanForwardBack = radToDeg(arctan2(g[0][0], 60.0))
    result.leanLeftRight = -radToDeg(arctan2(g[0][1], 60.0))
    result.leftShoulderPitch = -sh[0]
    result.rightShoulderPitch = -sh[3]
  result.hipRotation = g[1][0]
  result.torsoRotation = g[1][1]
  result.neckRotation = g[1][2]
  result.leftShoulderRoll = sh[1]
  result.leftShoulderYaw = sh[2]
  result.rightShoulderRoll = sh[4]
  result.rightShoulderYaw = sh[5]
  result.leftElbowBend = g[3][0]
  result.rightElbowBend = g[3][1]
  result.leftHipPitch = hp[0]
  result.leftHipRoll = hp[1]
  result.leftHipYaw = hp[2]
  result.rightHipPitch = hp[3]
  result.rightHipRoll = hp[4]
  result.rightHipYaw = hp[5]
  result.leftKneeBend = g[5][0]
  result.rightKneeBend = g[5][1]
  result.stanceWidth = g[6][0] / 100.0
  result.facingAngle = if g[6].len > 1: g[6][1] else: 90.0

type
  LegBiomechanics = object
    kneeBend*: float         # Calculated knee bend in degrees
    hipAbduction*: float     # Hip abduction angle for stance width
    legAngle*: float         # Leg angle from vertical in degrees

proc calculateLegBiomechanics(stanceWidthM: float): LegBiomechanics =
  ## Calculate biomechanically correct leg angles from stance width
  ## Stance width determines hip ABDUCTION angle (legs spreading sideways)
  ## The hip is a ball-and-socket joint at the pelvis - it rotates, not repositions

  const
    hipWidth = 0.30       # Hip joint separation in meters (30cm) - FIXED at pelvis
    thighLength = 0.45    # Thigh length in meters (45cm)
    shinLength = 0.45     # Shin length in meters (45cm)

  let totalLegLength = thighLength + shinLength

  # Desired foot separation from stance width
  let desiredFootSeparation = stanceWidthM

  # Hip joints are fixed at hip width (30cm apart)
  # To achieve desired foot separation, calculate required hip abduction angle
  let hipJointSeparation = hipWidth
  let additionalSpread = desiredFootSeparation - hipJointSeparation

  # Hip abduction angle needed to spread feet to desired width
  # tan(abduction_angle) = (additional_spread/2) / leg_length
  let abductionAngle = arctan((additionalSpread / 2.0) / totalLegLength)
  let abductionDeg = radToDeg(abductionAngle)

  # Calculate knee bend: as legs angle out, knees must bend to keep feet on ground
  const baseKneeBend = 15.0           # Minimum bend even in narrow stance
  let additionalBend = abductionDeg * 1.5  # More bend as legs angle out
  let kneeBend = min(baseKneeBend + additionalBend, 60.0)  # Cap at 60°

  result = LegBiomechanics(
    kneeBend: kneeBend,
    hipAbduction: min(abs(abductionDeg), 35.0),  # Cap abduction at 35°
    legAngle: abductionDeg
  )

proc fighterStateToMannequinPose*(fighter: Fighter): MannequinPose =
  ## Convert FightState fighter to mannequin pose
  ## This derives the physical pose from game state + posture level

  result = MannequinPose()

  # Base lean from balance and momentum
  # Lean in degrees: off-balance and forward momentum tip the body forward.
  let balanceOffset = (1.0 - fighter.pos.balance) * 10.0
  let momentumOffset = fighter.momentum.linear * 2.0
  result.leanForwardBack = 6.0 + momentumOffset + balanceOffset

  # Modify lean based on posture
  case fighter.posture:
  of plStanding:
    # Normal lean
    discard
  of plCrouched:
    # Lower, more forward lean
    result.leanForwardBack += 15.0
  of plGrounded:
    # Very low, almost horizontal
    result.leanForwardBack += 50.0  # close to horizontal
  of plJumping:
    # Airborne - less forward lean, more upright
    result.leanForwardBack -= 10.0
  of plSpinning:
    # Mid-rotation - variable lean
    result.leanForwardBack += 5.0

  # Lean left/right from weight distribution
  result.leanLeftRight = -(fighter.biomech.weightDistribution - 0.5) * 8.0

  # Rotation from biomech (amplified by spinning)
  result.hipRotation = fighter.biomech.hipRotation
  result.torsoRotation = fighter.biomech.torsoRotation
  if fighter.posture == plSpinning:
    result.hipRotation *= 1.5  # More rotation during spin
    result.torsoRotation *= 1.3
  result.neckRotation = 0.0  # Not tracked in current FightState

  # Shoulders: an extended arm is a straight punch at shoulder height; otherwise
  # the hands are up in guard (fists by the chin).
  # Extended values are the viewer's aimed jab and cross (the arm is swung across
  # to the centre line, because the hips are bladed).
  if fighter.leftArm.extended:
    result.leftShoulderPitch = 103.0
    result.leftShoulderRoll = 49.0
    result.leftShoulderYaw = 5.0
  else:
    result.leftShoulderPitch = 45.0
    result.leftShoulderRoll = 14.0
    result.leftShoulderYaw = 30.0
  if fighter.rightArm.extended:
    result.rightShoulderPitch = 103.0
    result.rightShoulderRoll = 14.0
    result.rightShoulderYaw = 5.0
  else:
    result.rightShoulderPitch = 38.0
    result.rightShoulderRoll = 16.0
    result.rightShoulderYaw = 38.0
  result.leftElbowBend = if fighter.leftArm.extended: 18.0 else: 118.0
  result.rightElbowBend = if fighter.rightArm.extended: 19.0 else: 132.0

  # Stance width - set first because biomechanics depend on it
  result.stanceWidth = case fighter.pos.stance:
    of skWide: 0.60
    of skWrestling: 0.70
    of skNarrow: 0.25
    else: 0.40

  # Hips - derive from stance
  case fighter.pos.stance:
  of skOrthodox:
    result.leftHipPitch = 18.0   # lead leg forward, rear leg back
    result.rightHipPitch = -18.0
  of skSouthpaw:
    result.leftHipPitch = -18.0
    result.rightHipPitch = 18.0
  of skWide:
    result.leftHipPitch = 0.0
    result.rightHipPitch = 0.0
  of skWrestling:
    result.leftHipPitch = 15.0   # Lower stance, forward
    result.rightHipPitch = 15.0
  else:
    result.leftHipPitch = 0.0
    result.rightHipPitch = 0.0

  # Hip abduction and knee bend calculated from stance width biomechanics
  # Wider stance = more hip abduction = need more knee bend
  # Hip abduction is for STANCE WIDTH (legs spreading at ball-socket joint)
  # Hip roll/pitch is for KICKS (rotating the leg for strikes)
  let legBio = calculateLegBiomechanics(result.stanceWidth)

  # For normal stance: use calculated abduction
  result.leftHipRoll = legBio.hipAbduction
  result.rightHipRoll = legBio.hipAbduction

  # Default: no yaw rotation (neutral leg alignment)
  result.leftHipYaw = 0.0
  result.rightHipYaw = 0.0

  # Base knee bend from biomechanics
  result.leftKneeBend = legBio.kneeBend
  result.rightKneeBend = legBio.kneeBend

  # Additional bend for wrestling/low stances
  if fighter.pos.stance == skWrestling:
    result.leftKneeBend += 20.0   # Extra deep bend
    result.rightKneeBend += 20.0

  # Adjust knee bend based on posture
  case fighter.posture:
  of plStanding:
    # Normal bend (already set)
    discard
  of plCrouched:
    # Deep bend
    result.leftKneeBend += 30.0
    result.rightKneeBend += 30.0
  of plGrounded:
    # Fully bent or legs extended
    result.leftKneeBend = 90.0
    result.rightKneeBend = 90.0
  of plJumping:
    # Legs may be chambered or extended
    result.leftKneeBend = 40.0
    result.rightKneeBend = 40.0
  of plSpinning:
    # One leg bent, one extended (simplified)
    result.leftKneeBend += 10.0
    result.rightKneeBend = 20.0

  # Leg extension for kicks - override with explicit angles
  # An extended leg is a round-kick shape: raised sideways, knee nearly straight,
  # turned in (internal rotation), with the hips turned over.
  if fighter.leftLeg.extended:
    result.leftHipPitch = 25.0
    result.leftKneeBend = 12.0
    result.leftHipRoll = 80.0
    result.leftHipYaw = 35.0
    result.hipRotation = -80.0
  if fighter.rightLeg.extended:
    result.rightHipPitch = 25.0
    result.rightKneeBend = 12.0
    result.rightHipRoll = 80.0
    result.rightHipYaw = 35.0
    result.hipRotation = 80.0

  # Facing angle (simplified - could be derived from pos.facing)
  result.facingAngle = 90.0  # Facing opponent

# Reference poses exported from fpn_3d_viewer.html: the leg angles are its
# foot-planting IK solution and the striking limb is its aimed (IK) solution at
# the moment of impact, so loading these in the viewer reproduces its frames.
const
  guardMPN* = "v2:6,0.-35,-8,0.45,14,30,38,16,38.118,132.28,17,-17,7,18,-20.34,35.30"
  jabMPN* = "v2:0,0.-45,-12,0.103,49,5,38,16,38.18,132.24,20,-27,3,19,-10.39,26.30"
  crossMPN* = "v2:7,0.15,16,0.50,14,40,103,14,5.135,19.33,-16,33,-23,-2,-30.53,11.30"
  roundKickMPN* = "v2:-6,24.102,18,0.45,14,30,38,16,38.118,132.29,-9,7,12,108,35.42,6.30"

proc createNeutralPose*(): MannequinPose =
  ## Orthodox fighting stance (the viewer's guard).
  mpnToPose(guardMPN)

proc createJabPose*(): MannequinPose =
  ## Lead straight at the moment of impact, at punching range.
  mpnToPose(jabMPN)

proc createCrossPose*(): MannequinPose =
  ## Rear straight at the moment of impact, at punching range.
  mpnToPose(crossMPN)

proc createRoundKickPose*(): MannequinPose =
  ## Rear round kick at impact, at kicking range: hips turned over, leg raised
  ## sideways and turned in, body leaning away.
  mpnToPose(roundKickMPN)

when isMainModule:
  echo "=== MPN (Mannequin Position Notation) Test ==="
  echo ""

  echo "1. Neutral stance:"
  let neutral = createNeutralPose()
  let neutralMPN = poseToMPN(neutral)
  echo "   MPN: ", neutralMPN
  echo ""

  echo "2. Jab position:"
  let jab = createJabPose()
  let jabMPN = poseToMPN(jab)
  echo "   MPN: ", jabMPN
  echo ""

  echo "3. Round kick:"
  let kick = createRoundKickPose()
  let kickMPN = poseToMPN(kick)
  echo "   MPN: ", kickMPN
  echo ""

  echo "4. Parse and reconstruct:"
  let parsed = mpnToPose(jabMPN)
  echo "   Reconstructed jab lean: ", parsed.leanForwardBack, "°"
  echo "   Reconstructed hip rotation: ", parsed.hipRotation, "°"
  echo "   Reconstructed left elbow: ", parsed.leftElbowBend, "°"
