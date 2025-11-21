## Core type definitions for the martial arts simulation engine
##
## KEY ARCHITECTURAL PRINCIPLE:
## The tablebase tree uses ONLY PositionState (stance, biomechanics, balance).
## Fatigue and damage are OVERLAYS applied at runtime when filtering moves.
## This prevents tree bloat from state variations that don't affect move legality.

import std/[options, tables, hashes, sets]

type
  FighterID* = enum
    FighterA = "A"
    FighterB = "B"

  LimbType* = enum
    LeftArm
    RightArm
    LeftLeg
    RightLeg

  StanceKind* = enum
    skNeutral      # neutral stance
    skOrthodox     # left foot forward
    skSouthpaw     # right foot forward
    skSquare       # feet parallel
    skWide         # wide stable base
    skNarrow       # narrow mobile base
    skBladed       # side-on
    skWrestling    # low wrestling stance

  SideKind* = enum
    Centerline     # facing opponent directly
    LiveSideLeft   # on opponent's open inside (left)
    LiveSideRight  # on opponent's open inside (right)
    DeadSideLeft   # on opponent's outside (left)
    DeadSideRight  # on opponent's outside (right)

  ControlKind* = enum
    None
    Clinch         # standing grappling, chest contact
    Underhook      # arm under opponent's arm
    Overhook       # arm over opponent's arm
    LegTrap        # controlling opponent's leg
    BackControl    # behind opponent
    Mount          # on top, ground
    Guard          # on bottom with legs controlling
    SideControl    # perpendicular ground control
    NeckControl    # controlling head/neck

  DistanceKind* = enum
    Contact        # 0-0.3m, grappling range
    Short          # 0.3-0.8m, elbow/knee range
    Medium         # 0.8-1.5m, punching range
    Long           # 1.5-2.5m, kicking range
    VeryLong       # 2.5m+, out of range

  PostureLevel* = enum
    ## Height/posture of fighter - determines move availability and effectiveness
    plStanding     # Normal upright stance
    plCrouched     # Ducking, low stance, wrestling stance
    plGrounded     # On ground (sitting, lying, fallen)
    plJumping      # Airborne (jumping, flying knee)
    plSpinning     # Mid-rotation (spinning kicks/strikes)

  Position3D* = object
    x*, y*, z*: float        # position in space (meters)
    facing*: float           # angle in degrees (0-360)
    stance*: StanceKind
    balance*: float          # 0.0 (falling) to 1.0 (perfectly stable)

  Momentum* = object
    ## Tracks physical momentum from moves
    linear*: float           # forward/backward momentum (m/s)
    rotational*: float       # spinning momentum (deg/s)
    decayRate*: float        # how fast momentum dissipates (per turn)

  BiomechanicalState* = object
    ## Tracks body configuration affecting available moves
    hipRotation*: float      # degrees rotated from neutral (-180 to +180)
    torsoRotation*: float    # degrees rotated from hips
    weightDistribution*: float # 0.0 (back leg) to 1.0 (front leg)
    recovering*: bool        # in recovery from committed move
    recoveryFrames*: int     # frames until fully recovered

  LimbPosition* = object
    ## Position/configuration of a limb (NOT including damage - that's an overlay)
    free*: bool              # can move freely
    extended*: bool          # currently extended/committed
    angle*: float            # relative angle to torso, degrees

  ## OVERLAYS - Applied at runtime, NOT part of tree state
  RuntimeOverlay* = object
    ## Fatigue and damage - applied when filtering viable moves
    ## NOT included in tree hash - prevents bloat
    fatigue*: float          # 0.0 (fresh) to 1.0 (exhausted)
    damage*: float           # 0.0 (unhurt) to 1.0 (incapacitated)
    leftArmDamage*: float    # per-limb damage
    rightArmDamage*: float
    leftLegDamage*: float
    rightLegDamage*: float

  Fighter* = object
    ## Position state (used in tree)
    pos*: Position3D
    posture*: PostureLevel   # height/posture level - affects move execution
    leftArm*, rightArm*: LimbPosition
    leftLeg*, rightLeg*: LimbPosition
    liveSide*: SideKind      # which side of opponent we're on
    control*: ControlKind    # grappling control state
    momentum*: Momentum      # current physical momentum
    biomech*: BiomechanicalState  # body configuration state

  FightState* = object
    ## The core position state - this is what goes in the tree
    a*, b*: Fighter
    distance*: DistanceKind
    sequenceLength*: int     # how many moves so far
    terminal*: bool          # is this a winning/losing position?
    winner*: Option[FighterID]
    stateHash*: string       # computed hash for deduplication

  RuntimeFightState* = object
    ## Complete state including overlays (for actual fight simulation)
    position*: FightState     # The tree position
    overlayA*: RuntimeOverlay # Fighter A overlays
    overlayB*: RuntimeOverlay # Fighter B overlays

  PositionDelta* = object
    ## Describes how a move changes position
    distanceChange*: float   # meters, can be negative
    angleChange*: float      # degrees rotation
    balanceChange*: float    # change to balance
    heightChange*: float     # change in height (for jumps, drops)

  PhysicsEffect* = object
    ## Physical consequences of a move
    linearMomentum*: float    # momentum generated (m/s)
    rotationalMomentum*: float # rotational momentum (deg/s)
    hipRotationDelta*: float  # change in hip rotation
    torsoRotationDelta*: float # change in torso rotation
    weightShift*: float       # change in weight distribution
    commitmentLevel*: float   # 0.0-1.0, how committed the move is
    recoveryFramesOnMiss*: int # extra recovery if move misses
    recoveryFramesOnHit*: int  # recovery even if move hits

  DamageEffect* = object
    ## Damage effects from a move - applied as overlay
    directDamage*: float      # direct damage to health
    fatigueInflicted*: float  # fatigue caused
    targetLimb*: Option[LimbType]  # which limb is damaged (if any)
    limbDamage*: float        # damage to specific limb

  MoveType* = enum
    ## Fundamental movement categories (GENERAL)
    mtPositional   # Stance changes, footwork, pivots, stepping
    mtEvasion      # Ducking, slipping, rolling, bobbing
    mtDeflection   # Redirecting attacks with minimal force
    mtDefensive    # Blocking, covering, framing
    mtOffensive    # All attacking movements

  MoveCategory* = enum
    ## Specific biomechanical sub-categories (within MoveType)
    ## POSITIONAL sub-types
    mcStep         # Linear stepping (forward, back, lateral)
    mcPivot        # Rotational footwork
    mcStanceChange # Switch stance, widen, narrow
    mcAngleChange  # Circling, creating angles
    mcLevelChange  # Raising/lowering center of mass

    ## EVASION sub-types
    mcSlip         # Head movement lateral
    mcBob          # Head movement vertical
    mcRoll         # Shoulder rotation evasion
    mcPull         # Pull back/lean back

    ## DEFLECTION sub-types
    mcParry        # Hand deflection
    mcCheck        # Limb obstruction
    mcRedirect     # Circular redirection (e.g., Aikido)
    mcJam          # Intercept and smother

    ## DEFENSIVE sub-types
    mcBlock        # Hard blocking
    mcCover        # Shell/guard
    mcFrame        # Structural defense (posting, frames)

    ## OFFENSIVE sub-types (attacks)
    mcStraightStrike  # Jab, cross, front kick, straight punch
    mcArcStrike       # Hook, roundhouse, haymaker
    mcWhipStrike      # Backfist, snap kick, slap
    mcPushStrike      # Teep, palm strike, push kick
    mcSweep           # Leg sweeps
    mcTrip            # Off-balancing with leg contact
    mcThrow           # Leverage throws
    mcTakedown        # Shooting takedowns
    mcClinchEntry     # Entering clinch
    mcLock            # Joint locks
    mcChoke           # Chokes and strangles
    mcTrap            # Limb trapping
    mcCounter         # Counter techniques
    mcFeint           # Deceptive movements

  HeightLevel* = enum
    Low    # below waist
    Mid    # waist to shoulders
    High   # head level

  MovePrerequisite* = proc(state: FightState, who: FighterID): bool {.closure.}
  MoveApplication* = proc(state: var FightState, who: FighterID) {.closure.}

  ## Move viability filter - checks if overlays allow this move
  MoveViabilityCheck* = proc(overlay: RuntimeOverlay, move: Move): float {.closure.}
    ## Returns 0.0-1.0 effectiveness based on fatigue/damage
    ## 1.0 = full effectiveness, 0.0 = can't perform

  Move* = object
    id*: string
    name*: string
    moveType*: MoveType      # GENERAL category (positional, evasion, etc)
    category*: MoveCategory  # SPECIFIC sub-category
    targets*: seq[string]    # Vulnerability zones this can hit (if offensive)
    energyCost*: float       # 0.0 (trivial) to 1.0 (exhausting)
    timeCost*: float         # seconds this action takes (for turn budget)
    reach*: float            # meters
    height*: HeightLevel
    angleBias*: float        # preferred angle relative to centerline
    recoveryTime*: float     # seconds until next move possible
    lethalPotential*: float  # 0.0 (no threat) to 1.0 (finisher)
    positionShift*: PositionDelta
    physicsEffect*: PhysicsEffect # momentum and biomechanical effects
    damageEffect*: DamageEffect   # damage/fatigue inflicted (overlay)
    postureChange*: Option[PostureLevel]  # attacker's posture after move
    defenderPostureChange*: Option[PostureLevel]  # defender's posture if hit (push down, knock down, etc)
    momentumTransfer*: float  # 0.0-1.0, how much attacker momentum transfers to defender
    prerequisites*: MovePrerequisite
    apply*: MoveApplication
    viabilityCheck*: MoveViabilityCheck  # checks overlay compatibility
    styleOrigins*: seq[string]  # which arts this comes from
    followups*: seq[string]     # likely next move IDs
    limbsUsed*: set[LimbType]  # which limbs this move uses
    canCombine*: bool        # can be combined with other moves in same turn
    optionsCreated*: int     # how many follow-up options this creates
    exposureRisk*: float     # 0.0-1.0, how much this exposes you

  StyleProfile* = object
    id*: string
    name*: string
    moveWeights*: Table[string, float]      # per move ID
    categoryBias*: Table[MoveCategory, float]
    distanceBias*: Table[DistanceKind, float]
    riskTolerance*: float    # -1.0 (conservative) to 1.0 (aggressive)
    adaptability*: float     # 0.0 (rigid) to 1.0 (flexible)

  ActionSequence* = object
    ## A sequence of moves performed simultaneously or in quick succession
    moves*: seq[Move]
    totalTimeCost*: float
    totalEnergyCost*: float
    limbsUsed*: set[LimbType]

  UnknownState* = object
    ## Logged when simulation reaches a state with no viable moves
    stateHash*: string
    state*: FightState
    timestamp*: int64
    description*: string

# Hash function for FightState deduplication
# CRITICAL: Only includes POSITION state, NOT overlays (fatigue/damage)
proc hash*(f: Fighter): Hash =
  var h: Hash = 0
  h = h !& hash(f.pos.x)
  h = h !& hash(f.pos.y)
  h = h !& hash(f.pos.facing)
  h = h !& hash(f.pos.stance)
  h = h !& hash(f.pos.balance)
  # Posture level - critical for move availability
  h = h !& hash(f.posture)
  # Limb positions (NOT damage)
  h = h !& hash(f.leftArm.free)
  h = h !& hash(f.leftArm.extended)
  h = h !& hash(f.rightArm.free)
  h = h !& hash(f.rightArm.extended)
  h = h !& hash(f.leftLeg.free)
  h = h !& hash(f.leftLeg.extended)
  h = h !& hash(f.rightLeg.free)
  h = h !& hash(f.rightLeg.extended)
  # Side and control
  h = h !& hash(f.liveSide)
  h = h !& hash(f.control)
  # Biomechanics
  h = h !& hash(f.biomech.recovering)
  h = h !& hash(f.biomech.recoveryFrames)
  # Momentum
  h = h !& hash(f.momentum.linear)
  h = h !& hash(f.momentum.rotational)
  # NOTE: fatigue and damage are NOT included - they are overlays
  result = !$h

proc hash*(s: FightState): Hash =
  var h: Hash = 0
  h = h !& hash(s.a)
  h = h !& hash(s.b)
  h = h !& hash(s.distance)
  result = !$h

# Helper to create default overlay (fresh fighter)
proc createFreshOverlay*(): RuntimeOverlay =
  RuntimeOverlay(
    fatigue: 0.0,
    damage: 0.0,
    leftArmDamage: 0.0,
    rightArmDamage: 0.0,
    leftLegDamage: 0.0,
    rightLegDamage: 0.0
  )

# Posture-dependent move modifiers
proc getPostureEffectMultiplier*(posture: PostureLevel, moveCategory: MoveCategory): float =
  ## Calculate effectiveness multiplier based on posture and move type
  ## Returns 0.0-1.0+ (some moves are MORE effective from certain postures)
  case posture:
  of plStanding:
    # Standing is neutral - most moves work normally
    case moveCategory:
    of mcStraightStrike, mcArcStrike, mcWhipStrike: 1.0
    of mcStep, mcPivot, mcStanceChange: 1.0
    of mcSweep, mcTrip: 0.8  # Harder to sweep from high stance
    else: 1.0

  of plCrouched:
    # Crouched - good for low attacks, bad for high attacks
    case moveCategory:
    of mcStraightStrike, mcArcStrike: 0.6  # Weak punches from low
    of mcWhipStrike: 0.7
    of mcSweep, mcTrip, mcTakedown: 1.3  # BETTER at takedowns from low
    of mcSlip, mcBob, mcRoll: 1.2  # Better evasion from low
    of mcPushStrike: 0.5  # Weak push kicks from low
    else: 0.9

  of plGrounded:
    # Grounded - very limited options
    case moveCategory:
    of mcStraightStrike, mcArcStrike: 0.3  # Very weak strikes
    of mcStep, mcPivot: 0.0  # Can't step on ground
    of mcRoll: 1.2  # Better at rolling on ground
    of mcBlock, mcCover: 1.1  # Good at defensive posture
    else: 0.4

  of plJumping:
    # Jumping - great for flying attacks, terrible for defense
    case moveCategory:
    of mcArcStrike: 1.4  # Flying knees, jumping kicks are devastating
    of mcStraightStrike: 1.2
    of mcBlock, mcCover, mcParry: 0.3  # Can't defend well in air
    of mcStep, mcPivot: 0.0  # Can't reposition in air
    else: 0.5

  of plSpinning:
    # Spinning - committed, high power, vulnerable
    case moveCategory:
    of mcArcStrike: 1.5  # Spinning kicks/punches have huge power
    of mcWhipStrike: 1.6  # Perfect for spinning backfists
    of mcBlock, mcParry, mcSlip: 0.2  # Very vulnerable during spin
    of mcStep: 0.3  # Limited mobility
    else: 0.6

proc inferPostureFromStance*(stance: StanceKind): PostureLevel =
  ## Infer posture level from stance
  case stance:
  of skWrestling: plCrouched
  else: plStanding

# Momentum-based overcommitment checks
proc checkOvercommitment*(fighter: Fighter, missedTarget: bool, commitmentLevel: float): tuple[overcommitted: bool, balanceLoss: float, postureChange: Option[PostureLevel]] =
  ## Check if fighter overcommitted and should lose balance/fall
  ## Returns: (did they overcommit?, how much balance to lose, new posture if they fall)

  if not missedTarget:
    # Hit landed, no overcommitment penalty
    return (false, 0.0, none(PostureLevel))

  # Calculate overcommitment risk based on:
  # - Commitment level of move
  # - Current momentum (high momentum = harder to stop)
  # - Current balance (low balance = easier to overcommit)

  let momentumFactor = abs(fighter.momentum.linear) + abs(fighter.momentum.rotational) * 0.01  # Convert deg/s to comparable scale
  let balanceFactor = 1.0 - fighter.pos.balance  # Low balance = high factor

  let overcommitRisk = commitmentLevel * (1.0 + momentumFactor + balanceFactor)

  if overcommitRisk > 1.2:
    # Severe overcommitment - fall over
    return (true, 0.4, some(plGrounded))
  elif overcommitRisk > 0.8:
    # Moderate overcommitment - stumble, lose significant balance
    return (true, 0.25, none(PostureLevel))
  elif overcommitRisk > 0.5:
    # Minor overcommitment - just balance loss
    return (true, 0.1, none(PostureLevel))
  else:
    # Controlled miss
    return (false, 0.05, none(PostureLevel))

proc transferMomentum*(attacker: var Fighter, defender: var Fighter, transfer: float, hitSuccess: bool) =
  ## Transfer momentum from attacker to defender when move lands
  ## Transfer is 0.0-1.0 (percentage of momentum transferred)

  if not hitSuccess or transfer <= 0.0:
    return

  # Transfer linear momentum
  let linearTransfer = attacker.momentum.linear * transfer
  defender.momentum.linear += linearTransfer
  attacker.momentum.linear -= linearTransfer * 0.5  # Attacker loses some but not all

  # Transfer rotational momentum (less effective)
  let rotationalTransfer = attacker.momentum.rotational * transfer * 0.3
  defender.momentum.rotational += rotationalTransfer

  # High momentum transfer can knock defender off balance or change posture
  if abs(linearTransfer) > 1.0 or abs(rotationalTransfer) > 50.0:
    # Strong push/strike - defender loses balance
    defender.pos.balance -= min(0.3, abs(linearTransfer) * 0.15)

# String representations are automatically generated by the enum type system
