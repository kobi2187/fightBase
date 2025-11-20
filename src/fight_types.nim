## Core type definitions for the martial arts simulation engine

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

  LimbStatus* = object
    free*: bool              # can move freely
    extended*: bool          # currently extended/committed
    damaged*: float          # 0.0 (fine) to 1.0 (unusable)
    angle*: float            # relative angle to torso, degrees

  Fighter* = object
    pos*: Position3D
    leftArm*, rightArm*: LimbStatus
    leftLeg*, rightLeg*: LimbStatus
    fatigue*: float          # 0.0 (fresh) to 1.0 (exhausted)
    damage*: float           # 0.0 (unhurt) to 1.0 (incapacitated)
    liveSide*: SideKind      # which side of opponent we're on
    control*: ControlKind    # grappling control state
    momentum*: Momentum      # current physical momentum
    biomech*: BiomechanicalState  # body configuration state

  FightState* = object
    a*, b*: Fighter
    distance*: DistanceKind
    sequenceLength*: int     # how many moves so far
    terminal*: bool          # is this a winning/losing position?
    winner*: Option[FighterID]
    stateHash*: string       # computed hash for deduplication

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
    prerequisites*: MovePrerequisite
    apply*: MoveApplication
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
proc hash*(f: Fighter): Hash =
  var h: Hash = 0
  h = h !& hash(f.pos.x)
  h = h !& hash(f.pos.y)
  h = h !& hash(f.pos.facing)
  h = h !& hash(f.pos.stance)
  h = h !& hash(f.pos.balance)
  h = h !& hash(f.fatigue)
  h = h !& hash(f.damage)
  h = h !& hash(f.liveSide)
  h = h !& hash(f.control)
  result = !$h

proc hash*(s: FightState): Hash =
  var h: Hash = 0
  h = h !& hash(s.a)
  h = h !& hash(s.b)
  h = h !& hash(s.distance)
  result = !$h

# String representations are automatically generated by the enum type system
