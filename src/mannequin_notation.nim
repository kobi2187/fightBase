## MPN (Mannequin Position Notation) - Pure Physical Pose
## Focus: Joint angles and body configuration for visualization
## Not game state (fatigue/damage), just the physical pose resulting from moves

import fight_types
import std/[strformat, strutils, math]

type
  MannequinPose* = object
    ## Physical pose of a mannequin - all angles in degrees
    # Body lean and rotation
    leanForwardBack*: float      # cm, + = forward, - = back
    leanLeftRight*: float         # cm, + = right, - = left
    hipRotation*: float           # degrees, rotation around vertical axis
    torsoRotation*: float         # degrees, relative to hips
    neckRotation*: float          # degrees, head turn

    # Shoulders (relative to torso)
    leftShoulderPitch*: float     # degrees, forward/back swing
    leftShoulderRoll*: float      # degrees, raising arm sideways
    rightShoulderPitch*: float
    rightShoulderRoll*: float

    # Elbows
    leftElbowBend*: float         # degrees, 0 = straight, 150 = fully bent
    rightElbowBend*: float

    # Hips (relative to pelvis)
    leftHipPitch*: float          # degrees, leg forward/back (X-axis)
    leftHipRoll*: float           # degrees, leg sideways abduction (Z-axis)
    leftHipYaw*: float            # degrees, leg rotation inward/outward (Y-axis)
    rightHipPitch*: float
    rightHipRoll*: float
    rightHipYaw*: float

    # Knees
    leftKneeBend*: float          # degrees, 0 = straight, 150 = bent
    rightKneeBend*: float

    # Stance
    stanceWidth*: float           # meters, distance between feet
    facingAngle*: float           # degrees, which direction facing

## MPN FORMAT (compact):
## fighter_a/fighter_b/distance
##
## Fighter format: lean.rotation.shoulders.elbows.hips.knees.stance
##   lean: fb,lr (forward-back in cm, left-right in cm)
##   rotation: hip,torso,neck (all in degrees)
##   shoulders: lp,lr,rp,rr (left pitch/roll, right pitch/roll)
##   elbows: l,r (left bend, right bend in degrees)
##   hips: lp,lr,ly,rp,rr,ry (left pitch/roll/yaw, right pitch/roll/yaw)
##   knees: l,r (left bend, right bend in degrees)
##   stance: width,facing (stance width in cm, facing angle in degrees)
##
## Example:
## 5,0.10,5,2.20,10,25,15.90,95.0,0,5,0,0,5,0,0.15,20.45,90.30,0,90
##
## Decoded:
##   Lean: 5cm forward, 0cm sideways
##   Rotation: 10° hip, 5° torso, 2° neck
##   Shoulders: L(20° pitch, 10° roll) R(25° pitch, 15° roll)
##   Elbows: L(90° bent) R(95° bent)
##   Hips: L(0° pitch, 5° roll, 0° yaw) R(0° pitch, 5° roll, 0° yaw)
##   Knees: L(15° bent) R(20° bent)
##   Stance: 45cm width, facing 90°

proc poseToMPN*(pose: MannequinPose): string =
  ## Convert pose to compact MPN notation
  result = fmt"{pose.leanForwardBack:.0f},{pose.leanLeftRight:.0f}."  # lean
  result.add fmt"{pose.hipRotation:.0f},{pose.torsoRotation:.0f},{pose.neckRotation:.0f}."  # rotation
  result.add fmt"{pose.leftShoulderPitch:.0f},{pose.leftShoulderRoll:.0f},"
  result.add fmt"{pose.rightShoulderPitch:.0f},{pose.rightShoulderRoll:.0f}."  # shoulders
  result.add fmt"{pose.leftElbowBend:.0f},{pose.rightElbowBend:.0f}."  # elbows
  result.add fmt"{pose.leftHipPitch:.0f},{pose.leftHipRoll:.0f},{pose.leftHipYaw:.0f},"
  result.add fmt"{pose.rightHipPitch:.0f},{pose.rightHipRoll:.0f},{pose.rightHipYaw:.0f}."  # hips
  result.add fmt"{pose.leftKneeBend:.0f},{pose.rightKneeBend:.0f}."  # knees
  result.add fmt"{pose.stanceWidth*100:.0f},{pose.facingAngle:.0f}"  # stance (convert m to cm)

proc mpnToPose*(mpn: string): MannequinPose =
  ## Parse MPN notation into pose
  let parts = mpn.split('.')
  if parts.len != 7:
    raise newException(ValueError, "Invalid MPN format: expected 7 parts")

  # Lean
  let leanParts = parts[0].split(',')
  result.leanForwardBack = parseFloat(leanParts[0])
  result.leanLeftRight = parseFloat(leanParts[1])

  # Rotation
  let rotParts = parts[1].split(',')
  result.hipRotation = parseFloat(rotParts[0])
  result.torsoRotation = parseFloat(rotParts[1])
  result.neckRotation = parseFloat(rotParts[2])

  # Shoulders
  let shoulderParts = parts[2].split(',')
  result.leftShoulderPitch = parseFloat(shoulderParts[0])
  result.leftShoulderRoll = parseFloat(shoulderParts[1])
  result.rightShoulderPitch = parseFloat(shoulderParts[2])
  result.rightShoulderRoll = parseFloat(shoulderParts[3])

  # Elbows
  let elbowParts = parts[3].split(',')
  result.leftElbowBend = parseFloat(elbowParts[0])
  result.rightElbowBend = parseFloat(elbowParts[1])

  # Hips
  let hipParts = parts[4].split(',')
  result.leftHipPitch = parseFloat(hipParts[0])
  result.leftHipRoll = parseFloat(hipParts[1])
  result.leftHipYaw = parseFloat(hipParts[2])
  result.rightHipPitch = parseFloat(hipParts[3])
  result.rightHipRoll = parseFloat(hipParts[4])
  result.rightHipYaw = parseFloat(hipParts[5])

  # Knees
  let kneeParts = parts[5].split(',')
  result.leftKneeBend = parseFloat(kneeParts[0])
  result.rightKneeBend = parseFloat(kneeParts[1])

  # Stance
  let stanceParts = parts[6].split(',')
  result.stanceWidth = parseFloat(stanceParts[0]) / 100.0  # Convert cm to m
  result.facingAngle = parseFloat(stanceParts[1])

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
  ## This derives the physical pose from game state

  result = MannequinPose()

  # Lean from balance and momentum
  let balanceOffset = (1.0 - fighter.pos.balance) * 10.0  # cm
  let momentumOffset = fighter.momentum.linear * 2.0      # cm
  result.leanForwardBack = momentumOffset + balanceOffset

  # Lean left/right from weight distribution
  result.leanLeftRight = (fighter.biomech.weightDistribution - 0.5) * 8.0  # cm

  # Rotation from biomech
  result.hipRotation = fighter.biomech.hipRotation
  result.torsoRotation = fighter.biomech.torsoRotation
  result.neckRotation = 0.0  # Not tracked in current FightState

  # Shoulders - derive from extended state and stance
  let guardHeight = 20.0  # Standard guard position

  # Left shoulder
  if fighter.leftArm.extended:
    result.leftShoulderPitch = -30.0   # Forward punch
    result.leftShoulderRoll = 10.0
  else:
    result.leftShoulderPitch = guardHeight
    result.leftShoulderRoll = 5.0

  # Right shoulder
  if fighter.rightArm.extended:
    result.rightShoulderPitch = -30.0
    result.rightShoulderRoll = 10.0
  else:
    result.rightShoulderPitch = guardHeight
    result.rightShoulderRoll = 5.0

  # Elbows - extended = straight, guard = bent
  result.leftElbowBend = if fighter.leftArm.extended: 10.0 else: 90.0
  result.rightElbowBend = if fighter.rightArm.extended: 10.0 else: 90.0

  # Stance width - set first because biomechanics depend on it
  result.stanceWidth = case fighter.pos.stance:
    of skWide: 0.60
    of skWrestling: 0.70
    of skNarrow: 0.25
    else: 0.40

  # Hips - derive from stance
  case fighter.pos.stance:
  of skOrthodox:
    result.leftHipPitch = 10.0   # Front leg slightly forward
    result.rightHipPitch = -5.0
  of skSouthpaw:
    result.leftHipPitch = -5.0
    result.rightHipPitch = 10.0
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

  # Leg extension for kicks - override with explicit angles
  if fighter.leftLeg.extended:
    result.leftHipPitch = 45.0      # Lift leg forward (X-axis)
    result.leftKneeBend = 30.0      # Partially extended
    result.leftHipRoll = 20.0       # Abduction for side/round kick (Z-axis)
    result.leftHipYaw = 45.0        # Rotation inward for round kick (Y-axis)
  if fighter.rightLeg.extended:
    result.rightHipPitch = 45.0
    result.rightKneeBend = 30.0
    result.rightHipRoll = 20.0
    result.rightHipYaw = -45.0      # Negative = rotate inward (mirror of left)

  # Facing angle (simplified - could be derived from pos.facing)
  result.facingAngle = 90.0  # Facing opponent

proc createNeutralPose*(): MannequinPose =
  ## Create neutral fighting stance pose
  result = MannequinPose(
    leanForwardBack: 0.0,
    leanLeftRight: 0.0,
    hipRotation: 0.0,
    torsoRotation: 0.0,
    neckRotation: 0.0,
    leftShoulderPitch: 20.0,   # Guard position
    leftShoulderRoll: 5.0,
    rightShoulderPitch: 20.0,
    rightShoulderRoll: 5.0,
    leftElbowBend: 90.0,       # Bent at guard
    rightElbowBend: 90.0,
    leftHipPitch: 10.0,        # Orthodox stance
    leftHipRoll: 0.0,
    leftHipYaw: 0.0,           # No rotation
    rightHipPitch: -5.0,
    rightHipRoll: 0.0,
    rightHipYaw: 0.0,
    leftKneeBend: 15.0,        # Slight bend
    rightKneeBend: 15.0,
    stanceWidth: 0.40,         # 40cm
    facingAngle: 90.0
  )

proc createJabPose*(): MannequinPose =
  ## Create pose during a jab
  result = createNeutralPose()
  result.leanForwardBack = 8.0           # Leaning into punch
  result.hipRotation = 8.0
  result.torsoRotation = 12.0
  result.leftShoulderPitch = -35.0       # Left arm extended
  result.leftShoulderRoll = 8.0
  result.leftElbowBend = 15.0            # Almost straight
  result.leftHipPitch = 12.0             # Front leg forward
  result.leftKneeBend = 20.0             # Slight more bend

proc createRoundKickPose*(): MannequinPose =
  ## Create pose during round kick
  result = createNeutralPose()
  result.leanLeftRight = -15.0           # Leaning away from kick
  result.hipRotation = 60.0              # Heavy hip rotation
  result.torsoRotation = 30.0
  result.rightHipPitch = 80.0            # Right leg high (X-axis)
  result.rightHipRoll = 45.0             # Leg abducted to side (Z-axis)
  result.rightHipYaw = -60.0             # Leg rotates inward (Y-axis) - KEY for round kick!
  result.rightKneeBend = 40.0            # Partially bent
  result.leftKneeBend = 25.0             # Standing leg bent for balance
  result.stanceWidth = 0.15              # Narrow (one leg up)

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
  echo "   Reconstructed jab lean: ", parsed.leanForwardBack, "cm"
  echo "   Reconstructed hip rotation: ", parsed.hipRotation, "°"
  echo "   Reconstructed left elbow: ", parsed.leftElbowBend, "°"
