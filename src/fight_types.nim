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

# String representations are automatically generated by the enum type system
