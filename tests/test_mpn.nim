## MPN v2 (mannequin pose notation): round trip, legacy parsing, and agreement
## with the conventions of fpn_3d_viewer.html.

import std/[unittest, strutils]
import mannequin_notation

suite "MPN v2":
  test "round trip":
    for pose in [createNeutralPose(), createJabPose(), createCrossPose(), createRoundKickPose()]:
      let s = poseToMPN(pose)
      check s.startsWith("v2:")
      check s.split('.').len == 7
      check poseToMPN(mpnToPose(s)) == s

  test "reference poses are the viewer's exported frames":
    check poseToMPN(createNeutralPose()) == guardMPN
    check poseToMPN(createJabPose()) == jabMPN
    check poseToMPN(createCrossPose()) == crossMPN
    check poseToMPN(createRoundKickPose()) == roundKickMPN

  test "flexion is positive: a jab raises the lead arm forward and nearly straightens it":
    let j = createJabPose()
    check j.leftShoulderPitch > 80
    check j.leftElbowBend < 25

  test "legacy format: lean in cm, shoulder pitch negative forward, 4-value groups":
    let p = mpnToPose("8,0.8,12,0.-35,8,-30,10.15,90.12,0,-5,0.20,15.40,90")
    check p.leanForwardBack > 7 and p.leanForwardBack < 8      # atan(8/60)
    check p.leftShoulderPitch == 35                             # -(-35)
    check p.rightShoulderPitch == 30
    check p.leftHipPitch == 12
    check p.stanceWidth == 0.40
    check p.facingAngle == 90

  test "malformed input is rejected":
    expect ValueError: discard mpnToPose("v2:1,2.3")
    expect ValueError: discard mpnToPose("v2:1,2.3,4,5.1,2,3.1,2.1,2,3,4,5,6.1,2.x")
