## Core type definitions for the martial arts simulation engine

import std/[options, tables, hashes]

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
    Orthodox        # left foot forward
    Southpaw       # right foot forward
    Square         # feet parallel
    Wide           # wide stable base
    Narrow         # narrow mobile base
    Bladed         # side-on

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

  MoveCategory* = enum
    ## Canonical biomechanical categories
    Straight       # linear strikes (jab, cross, front kick)
    Arc            # circular strikes (hook, roundhouse)
    Whip           # snapping strikes (backfist, snap kick)
    Push           # pushing techniques (teep, palm strike)
    Pull           # pulling techniques (clinch entry, drag)
    Sweep          # leg sweeps
    Trip           # off-balancing with leg contact
    Throw          # leverage throws
    Takedown       # shooting takedowns
    Clinch         # clinch entries
    Lock           # joint locks
    Choke          # chokes and strangles
    Displacement   # footwork, pivots
    Feint          # deceptive movements
    Trap           # limb trapping
    Block          # defensive blocks
    Evade          # evasive movements
    Counter        # counter techniques

  HeightLevel* = enum
    Low    # below waist
    Mid    # waist to shoulders
    High   # head level

  MovePrerequisite* = proc(state: FightState, who: FighterID): bool {.closure.}
  MoveApplication* = proc(state: var FightState, who: FighterID) {.closure.}

  Move* = object
    id*: string
    name*: string
    category*: MoveCategory
    energyCost*: float       # 0.0 (trivial) to 1.0 (exhausting)
    timeCost*: float         # seconds this action takes (for turn budget)
    reach*: float            # meters
    height*: HeightLevel
    angleBias*: float        # preferred angle relative to centerline
    recoveryTime*: float     # seconds until next move possible
    lethalPotential*: float  # 0.0 (no threat) to 1.0 (finisher)
    positionShift*: PositionDelta
    prerequisites*: MovePrerequisite
    apply*: MoveApplication
    styleOrigins*: seq[string]  # which arts this comes from
    followups*: seq[string]     # likely next move IDs
    limbsUsed*: set[LimbType]  # which limbs this move uses
    canCombine*: bool        # can be combined with other moves in same turn

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
    ## Logged when simulation reaches a state with no legal moves
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
