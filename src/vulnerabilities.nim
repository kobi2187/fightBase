## Vulnerability Points System
## Maps all human body weak points with tactical data

import fight_types

type
  VulnerabilityZone* = enum
    # HEAD TARGETS
    vzEyes          # Immediate blindness reflex
    vzTemples       # Rotational KO, disorientation
    vzNose          # Break, tearing, disorientation
    vzJaw           # KO via rotational acceleration
    vzEars          # Balance disruption, pain
    vzThroat        # Gag reflex, airway threat
    vzBackOfHead    # Concussion risk, high danger
    vzNeck          # Structural danger, control point

    # TORSO TARGETS
    vzSolarPlexus   # Diaphragm spasm, wind knockout
    vzFloatingRibs  # Fracture, organ protection reflex
    vzLiver         # Systemic shock, instant disable
    vzKidneys       # Pain, structural damage
    vzSpine         # Control point, structural danger
    vzCollarbone    # Easy break, arm disability

    # ARM TARGETS
    vzShoulder      # Joint manipulation, power loss
    vzElbow         # Joint lock, easy break
    vzWrist         # Control point, leverage
    vzFingers       # Easy break, grip loss
    vzBicepTendon   # Arm weakness, pain

    # LEG TARGETS
    vzGroin         # Systemic shock, instant disable
    vzHip           # Balance, mobility loss
    vzKneeFront     # Hyperextension threat
    vzKneeLateral   # MCL damage, instant mobility loss
    vzAnkle         # Mobility loss, balance
    vzFoot          # Pin, stomp, mobility
    vzCalf          # Charley horse, mobility
    vzThighMuscle   # Femoral nerve, leg dysfunction

    # BALANCE/STRUCTURE
    vzBaseOfSkull   # Neck reflex, extreme danger
    vzCenterMass    # Push/pull for off-balance

  VulnerabilityData* = object
    zone*: VulnerabilityZone
    forceRequired*: float        # Newtons to affect
    distanceFromCenter*: float   # Meters from body centerline
    heightLevel*: HeightZone     # High/Mid/Low positioning
    exposureDefault*: float      # 0.0-1.0, how exposed normally
    exposureInStance*: array[StanceKind, float]  # Exposure per stance
    effectOnHit*: VulnerabilityEffect

  HeightZone* = enum
    hzLow    # Below waist
    hzMid    # Waist to shoulders
    hzHigh   # Shoulders and above

  VulnerabilityEffect* = object
    pain*: float                 # 0.0-1.0 pain level
    structural*: bool            # Affects balance/position
    disabling*: bool             # Can end fight immediately
    systemic*: bool              # Affects whole body (groin, liver, etc)
    reflex*: bool                # Causes involuntary reaction
    compliance*: float           # 0.0-1.0 likelihood to stop fighting
    recoveryTime*: int           # Frames to recover (if recoverable)

# Calculate reachability from a given position and stance
proc calculateReachability*(
  attacker: Fighter,
  defender: Fighter,
  target: VulnerabilityZone,
  distance: float
): float =
  ## Returns 0.0-1.0 representing how reachable this target is
  ## 1.0 = easily reachable, 0.0 = impossible to reach

  let vulnData = getVulnerabilityData(target)

  # Base reachability from distance
  var reachability = case vulnData.heightLevel:
    of hzHigh:
      if distance < 0.5: 0.9  # Close range, easy
      elif distance < 1.0: 0.7
      elif distance < 1.5: 0.4
      else: 0.1
    of hzMid:
      if distance < 0.5: 1.0  # Always reachable close
      elif distance < 1.0: 0.8
      elif distance < 1.5: 0.5
      else: 0.2
    of hzLow:
      if distance < 0.5: 0.8  # Harder to reach low
      elif distance < 1.0: 0.6
      elif distance < 1.5: 0.3
      else: 0.1

  # Modify by defender's stance exposure
  let exposure = vulnData.exposureInStance[defender.stance]
  reachability *= exposure

  # Modify by defender's guard state
  # TODO: Add guard position tracking

  result = reachability

proc getVulnerabilityData*(zone: VulnerabilityZone): VulnerabilityData =
  ## Returns the static data for each vulnerability zone
  case zone:

  # ===== HEAD TARGETS =====
  of vzEyes:
    result = VulnerabilityData(
      zone: vzEyes,
      forceRequired: 5.0,        # Just need to touch
      distanceFromCenter: 0.08,   # 8cm from centerline
      heightLevel: hzHigh,
      exposureDefault: 0.9,       # Usually exposed
      exposureInStance: [
        skNeutral: 0.9,
        skOrthodox: 0.85,         # Slightly covered by lead hand
        skSouthpaw: 0.85,
        skWrestling: 0.6,         # Lower, more protected
        skBladed: 0.95,           # Very exposed
        skSquare: 0.9
      ],
      effectOnHit: VulnerabilityEffect(
        pain: 0.8,
        structural: false,
        disabling: false,
        systemic: false,
        reflex: true,             # Immediate blink/flinch
        compliance: 0.7,          # High compliance from blindness threat
        recoveryTime: 30          # ~0.5 seconds
      )
    )

  of vzTemples:
    result = VulnerabilityData(
      zone: vzTemples,
      forceRequired: 100.0,
      distanceFromCenter: 0.12,
      heightLevel: hzHigh,
      exposureDefault: 0.7,
      exposureInStance: [
        skNeutral: 0.7,
        skOrthodox: 0.6,
        skSouthpaw: 0.6,
        skWrestling: 0.5,
        skBladed: 0.8,
        skSquare: 0.7
      ],
      effectOnHit: VulnerabilityEffect(
        pain: 0.9,
        structural: false,
        disabling: true,           # Can cause KO
        systemic: true,
        reflex: true,
        compliance: 0.95,
        recoveryTime: 600          # 10 seconds if not KO'd
      )
    )

  of vzNose:
    result = VulnerabilityData(
      zone: vzNose,
      forceRequired: 80.0,
      distanceFromCenter: 0.0,    # Centerline
      heightLevel: hzHigh,
      exposureDefault: 0.95,
      exposureInStance: [
        skNeutral: 0.95,
        skOrthodox: 0.9,
        skSouthpaw: 0.9,
        skWrestling: 0.7,
        skBladed: 0.98,
        skSquare: 0.95
      ],
      effectOnHit: VulnerabilityEffect(
        pain: 1.0,                 # Maximum pain
        structural: false,
        disabling: false,
        systemic: false,
        reflex: true,              # Eyes water, head pulls back
        compliance: 0.8,
        recoveryTime: 180          # 3 seconds
      )
    )

  of vzJaw:
    result = VulnerabilityData(
      zone: vzJaw,
      forceRequired: 200.0,
      distanceFromCenter: 0.08,
      heightLevel: hzHigh,
      exposureDefault: 0.8,
      exposureInStance: [
        skNeutral: 0.8,
        skOrthodox: 0.7,
        skSouthpaw: 0.7,
        skWrestling: 0.5,          # Chin tucked
        skBladed: 0.85,
        skSquare: 0.8
      ],
      effectOnHit: VulnerabilityEffect(
        pain: 0.9,
        structural: true,          # Head rotation
        disabling: true,           # KO via rotational acceleration
        systemic: true,
        reflex: true,
        compliance: 0.98,
        recoveryTime: 1800         # 30 seconds if not KO'd
      )
    )

  of vzThroat:
    result = VulnerabilityData(
      zone: vzThroat,
      forceRequired: 20.0,       # Very sensitive
      distanceFromCenter: 0.0,
      heightLevel: hzHigh,
      exposureDefault: 0.7,
      exposureInStance: [
        skNeutral: 0.7,
        skOrthodox: 0.5,
        skSouthpaw: 0.5,
        skWrestling: 0.3,          # Well protected
        skBladed: 0.8,
        skSquare: 0.7
      ],
      effectOnHit: VulnerabilityEffect(
        pain: 1.0,
        structural: false,
        disabling: true,           # Gag reflex, airway panic
        systemic: true,
        reflex: true,
        compliance: 0.99,          # Extreme compliance
        recoveryTime: 300          # 5 seconds
      )
    )

  # ===== TORSO TARGETS =====
  of vzSolarPlexus:
    result = VulnerabilityData(
      zone: vzSolarPlexus,
      forceRequired: 30.0,
      distanceFromCenter: 0.0,
      heightLevel: hzMid,
      exposureDefault: 0.8,
      exposureInStance: [
        skNeutral: 0.8,
        skOrthodox: 0.6,           # Turned away
        skSouthpaw: 0.6,
        skWrestling: 0.5,
        skBladed: 0.95,            # Very exposed
        skSquare: 0.9
      ],
      effectOnHit: VulnerabilityEffect(
        pain: 0.9,
        structural: false,
        disabling: true,           # Wind knockout, diaphragm spasm
        systemic: true,
        reflex: true,
        compliance: 0.9,
        recoveryTime: 240          # 4 seconds
      )
    )

  of vzLiver:
    result = VulnerabilityData(
      zone: vzLiver,
      forceRequired: 150.0,
      distanceFromCenter: 0.15,   # Right side
      heightLevel: hzMid,
      exposureDefault: 0.6,
      exposureInStance: [
        skNeutral: 0.6,
        skOrthodox: 0.4,           # Protected by stance
        skSouthpaw: 0.8,           # More exposed
        skWrestling: 0.5,
        skBladed: 0.7,
        skSquare: 0.6
      ],
      effectOnHit: VulnerabilityEffect(
        pain: 1.0,
        structural: false,
        disabling: true,           # Systemic shock, instant drop
        systemic: true,
        reflex: true,
        compliance: 1.0,           # Fight over
        recoveryTime: 3600         # 60 seconds
      )
    )

  of vzFloatingRibs:
    result = VulnerabilityData(
      zone: vzFloatingRibs,
      forceRequired: 250.0,
      distanceFromCenter: 0.15,
      heightLevel: hzMid,
      exposureDefault: 0.7,
      exposureInStance: [
        skNeutral: 0.7,
        skOrthodox: 0.5,
        skSouthpaw: 0.5,
        skWrestling: 0.6,
        skBladed: 0.8,
        skSquare: 0.7
      ],
      effectOnHit: VulnerabilityEffect(
        pain: 0.95,
        structural: true,          # Breathing affected
        disabling: false,
        systemic: false,
        reflex: true,
        compliance: 0.8,
        recoveryTime: 600
      )
    )

  # ===== LEG TARGETS =====
  of vzGroin:
    result = VulnerabilityData(
      zone: vzGroin,
      forceRequired: 10.0,       # Extremely sensitive
      distanceFromCenter: 0.0,
      heightLevel: hzLow,
      exposureDefault: 0.7,
      exposureInStance: [
        skNeutral: 0.7,
        skOrthodox: 0.5,
        skSouthpaw: 0.5,
        skWrestling: 0.3,          # Well protected
        skBladed: 0.9,             # Very exposed
        skSquare: 0.8
      ],
      effectOnHit: VulnerabilityEffect(
        pain: 1.0,
        structural: true,
        disabling: true,           # Systemic shock
        systemic: true,
        reflex: true,
        compliance: 1.0,
        recoveryTime: 1800         # 30 seconds
      )
    )

  of vzKneeLateral:
    result = VulnerabilityData(
      zone: vzKneeLateral,
      forceRequired: 60.0,
      distanceFromCenter: 0.15,
      heightLevel: hzLow,
      exposureDefault: 0.9,       # Usually exposed
      exposureInStance: [
        skNeutral: 0.9,
        skOrthodox: 0.85,
        skSouthpaw: 0.85,
        skWrestling: 0.8,
        skBladed: 0.95,
        skSquare: 0.9
      ],
      effectOnHit: VulnerabilityEffect(
        pain: 0.95,
        structural: true,          # MCL damage
        disabling: true,           # Instant mobility loss
        systemic: false,
        reflex: true,
        compliance: 0.95,
        recoveryTime: 7200         # 2 minutes (or permanent)
      )
    )

  of vzKneeFront:
    result = VulnerabilityData(
      zone: vzKneeFront,
      forceRequired: 200.0,      # Stronger structure
      distanceFromCenter: 0.0,
      heightLevel: hzLow,
      exposureDefault: 0.95,
      exposureInStance: [
        skNeutral: 0.95,
        skOrthodox: 0.9,
        skSouthpaw: 0.9,
        skWrestling: 0.85,
        skBladed: 0.98,
        skSquare: 0.95
      ],
      effectOnHit: VulnerabilityEffect(
        pain: 0.9,
        structural: true,
        disabling: false,          # Stops advance, not instant disable
        systemic: false,
        reflex: true,
        compliance: 0.7,
        recoveryTime: 300
      )
    )

  of vzFoot:
    result = VulnerabilityData(
      zone: vzFoot,
      forceRequired: 150.0,      # Stomp force
      distanceFromCenter: 0.15,
      heightLevel: hzLow,
      exposureDefault: 1.0,       # Always exposed
      exposureInStance: [
        skNeutral: 1.0,
        skOrthodox: 1.0,
        skSouthpaw: 1.0,
        skWrestling: 1.0,
        skBladed: 1.0,
        skSquare: 1.0
      ],
      effectOnHit: VulnerabilityEffect(
        pain: 0.85,
        structural: true,          # Balance and mobility
        disabling: false,
        systemic: false,
        reflex: true,
        compliance: 0.6,
        recoveryTime: 180
      )
    )

  of vzThighMuscle:
    result = VulnerabilityData(
      zone: vzThighMuscle,
      forceRequired: 300.0,      # Thick muscle
      distanceFromCenter: 0.15,
      heightLevel: hzLow,
      exposureDefault: 0.85,
      exposureInStance: [
        skNeutral: 0.85,
        skOrthodox: 0.75,
        skSouthpaw: 0.75,
        skWrestling: 0.7,
        skBladed: 0.9,
        skSquare: 0.85
      ],
      effectOnHit: VulnerabilityEffect(
        pain: 0.8,
        structural: true,          # Leg dysfunction
        disabling: false,
        systemic: false,
        reflex: true,
        compliance: 0.5,
        recoveryTime: 600
      )
    )

  # ===== ARM TARGETS =====
  of vzFingers:
    result = VulnerabilityData(
      zone: vzFingers,
      forceRequired: 40.0,
      distanceFromCenter: 0.4,    # Extended reach
      heightLevel: hzMid,
      exposureDefault: 0.95,
      exposureInStance: [
        skNeutral: 0.95,
        skOrthodox: 0.9,
        skSouthpaw: 0.9,
        skWrestling: 0.85,
        skBladed: 0.98,
        skSquare: 0.95
      ],
      effectOnHit: VulnerabilityEffect(
        pain: 0.9,
        structural: true,          # Grip loss
        disabling: false,
        systemic: false,
        reflex: true,
        compliance: 0.7,
        recoveryTime: 300
      )
    )

  of vzElbow:
    result = VulnerabilityData(
      zone: vzElbow,
      forceRequired: 80.0,       # Joint lock pressure
      distanceFromCenter: 0.25,
      heightLevel: hzMid,
      exposureDefault: 0.7,
      exposureInStance: [
        skNeutral: 0.7,
        skOrthodox: 0.6,
        skSouthpaw: 0.6,
        skWrestling: 0.5,
        skBladed: 0.75,
        skSquare: 0.7
      ],
      effectOnHit: VulnerabilityEffect(
        pain: 0.95,
        structural: true,
        disabling: false,
        systemic: false,
        reflex: true,
        compliance: 0.9,           # Joint locks create high compliance
        recoveryTime: 120
      )
    )

  # Fallback for any targets not explicitly defined
  else:
    result = VulnerabilityData(
      zone: zone,
      forceRequired: 100.0,
      distanceFromCenter: 0.1,
      heightLevel: hzMid,
      exposureDefault: 0.5,
      exposureInStance: [
        skNeutral: 0.5,
        skOrthodox: 0.5,
        skSouthpaw: 0.5,
        skWrestling: 0.5,
        skBladed: 0.5,
        skSquare: 0.5
      ],
      effectOnHit: VulnerabilityEffect(
        pain: 0.5,
        structural: false,
        disabling: false,
        systemic: false,
        reflex: false,
        compliance: 0.3,
        recoveryTime: 60
      )
    )

proc getBestTargets*(
  attacker: Fighter,
  defender: Fighter,
  distance: float,
  preferLowExposure: bool = false
): seq[tuple[zone: VulnerabilityZone, score: float]] =
  ## Returns ranked list of best targets to attack
  ## Higher score = better target
  ## If preferLowExposure=true, favors attacks that expose attacker less

  result = @[]

  for zone in VulnerabilityZone:
    let vulnData = getVulnerabilityData(zone)
    let reachability = calculateReachability(attacker, defender, zone, distance)

    if reachability < 0.1:
      continue  # Not reachable enough

    # Score based on effect vs force required
    var score = (vulnData.effectOnHit.compliance * 100.0) / vulnData.forceRequired
    score *= reachability

    # Prefer disabling targets
    if vulnData.effectOnHit.disabling:
      score *= 2.0

    # Prefer systemic effects
    if vulnData.effectOnHit.systemic:
      score *= 1.5

    # In tight spots (close distance), prefer low-force high-compliance
    if distance < 0.5:
      score *= (1.0 / (vulnData.forceRequired + 1.0))  # Favor low force

    # If preferring low exposure (defender mindset)
    if preferLowExposure:
      # Favor targets that don't require full commitment
      if vulnData.forceRequired < 100.0:
        score *= 1.5

    result.add((zone: zone, score: score))

  # Sort by score descending
  result.sort(proc(a, b: auto): int =
    if b.score > a.score: 1
    elif b.score < a.score: -1
    else: 0
  )
