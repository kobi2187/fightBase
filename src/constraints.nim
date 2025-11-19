## Constraint checking and prerequisite validation system
## These functions determine what moves are physically possible

import fight_types
import std/math

# ============================================================================
# Distance and reach constraints
# ============================================================================

proc distanceInMeters*(dk: DistanceKind): float =
  ## Convert distance enum to approximate meters (center of range)
  case dk
  of Contact: 0.15
  of Short: 0.55
  of Medium: 1.15
  of Long: 2.0
  of VeryLong: 3.0

proc canReachTarget*(attacker: Fighter, move: Move, distance: DistanceKind): bool =
  ## Can the attacker reach with this move at this distance?
  let distMeters = distanceInMeters(distance)
  result = move.reach >= distMeters - 0.3  # Allow 30cm margin

proc isDistanceOptimal*(move: Move, distance: DistanceKind): bool =
  ## Is this distance optimal for this move?
  case move.category
  of Clinch, Lock, Choke: distance == Contact
  of Straight, Arc, Whip: distance in {Short, Medium}
  of Push: distance in {Short, Medium, Long}
  of Throw, Takedown: distance in {Contact, Short}
  of Sweep, Trip: distance in {Contact, Short}
  else: true  # Other moves are more flexible

# ============================================================================
# Limb availability constraints
# ============================================================================

proc hasFreeLimbs*(fighter: Fighter, required: int = 1): bool =
  ## Does fighter have at least N free limbs?
  var count = 0
  if fighter.leftArm.free: inc count
  if fighter.rightArm.free: inc count
  if fighter.leftLeg.free: inc count
  if fighter.rightLeg.free: inc count
  result = count >= required

proc hasFreeArm*(fighter: Fighter): bool =
  fighter.leftArm.free or fighter.rightArm.free

proc hasFreeLeg*(fighter: Fighter): bool =
  fighter.leftLeg.free or fighter.rightLeg.free

proc canUseLimb*(limb: LimbStatus, move: Move): bool =
  ## Can this specific limb execute this move?
  if not limb.free: return false
  if limb.extended and move.category in {Straight, Arc}: return false
  if limb.damaged > 0.6: return false  # Too damaged
  result = true

# ============================================================================
# Balance and stability constraints
# ============================================================================

proc isBalanceAdequate*(fighter: Fighter, move: Move): bool =
  ## Does fighter have enough balance for this move?
  case move.category
  of Throw, Takedown: fighter.pos.balance >= 0.6
  of Arc, Whip: fighter.pos.balance >= 0.5
  of Sweep, Trip: fighter.pos.balance >= 0.7
  else: fighter.pos.balance >= 0.3  # Most moves work with low balance

proc canPivot*(fighter: Fighter): bool =
  ## Can fighter pivot/turn?
  fighter.pos.balance >= 0.5 and fighter.fatigue < 0.8

proc canJump*(fighter: Fighter): bool =
  ## Can fighter jump or leave ground?
  fighter.pos.balance >= 0.7 and fighter.fatigue < 0.6

# ============================================================================
# Fatigue constraints
# ============================================================================

proc canAffordMove*(fighter: Fighter, move: Move): bool =
  ## Does fighter have energy for this move?
  # Allow moves that would push fatigue up to 0.95
  fighter.fatigue + move.energyCost <= 0.95

proc getFatigueThreshold*(fatigue: float): int =
  ## Returns fatigue level bracket (0-5)
  ## Higher = more restricted
  if fatigue < 0.2: 0      # Fresh
  elif fatigue < 0.4: 1    # Light fatigue
  elif fatigue < 0.6: 2    # Moderate fatigue
  elif fatigue < 0.75: 3   # Heavy fatigue
  elif fatigue < 0.9: 4    # Extreme fatigue
  else: 5                  # Exhausted

proc isMoveFatigueAppropriate*(move: Move, fatigue: float): bool =
  ## Some moves disabled at high fatigue
  let threshold = getFatigueThreshold(fatigue)
  case move.category
  of Throw, Takedown: threshold <= 3
  of Arc, Whip: threshold <= 4
  else: threshold <= 5

# ============================================================================
# Positional and angular constraints
# ============================================================================

proc isOnLiveSide*(fighter: Fighter): bool =
  ## Is fighter on opponent's live (inside) side?
  fighter.liveSide in {LiveSideLeft, LiveSideRight}

proc isOnDeadSide*(fighter: Fighter): bool =
  ## Is fighter on opponent's dead (outside) side?
  fighter.liveSide in {DeadSideLeft, DeadSideRight}

proc canAccessAngle*(fighter: Fighter, move: Move): bool =
  ## Can fighter access the angle needed for this move?
  # Simplified: most moves work from centerline or live side
  # Some moves require dead side (certain strikes from outside)
  case move.category
  of Clinch: fighter.liveSide in {Centerline, LiveSideLeft, LiveSideRight}
  of Throw: fighter.liveSide != DeadSideLeft and fighter.liveSide != DeadSideRight
  else: true  # Most strikes work from any angle

# ============================================================================
# Stance and posture constraints
# ============================================================================

proc isStanceCompatible*(fighter: Fighter, move: Move): bool =
  ## Is the current stance compatible with this move?
  # Most moves work from most stances, but some have preferences
  case move.category
  of Throw:
    # Throws harder from narrow stance
    fighter.pos.stance != Narrow
  of Takedown:
    # Takedowns need mobile stance
    fighter.pos.stance in {Orthodox, Southpaw, Square}
  else:
    true

# ============================================================================
# Control and grappling constraints
# ============================================================================

proc hasGrapplingControl*(fighter: Fighter): bool =
  fighter.control in {Clinch, Underhook, Overhook, BackControl, Mount, SideControl}

proc hasStrikingControl*(fighter: Fighter): bool =
  fighter.control in {None, NeckControl}

proc canStrike*(fighter: Fighter): bool =
  ## Can fighter throw strikes in current control state?
  case fighter.control
  of None, Clinch, NeckControl: true
  of Underhook, Overhook: hasFreeLimbs(fighter, 1)
  else: false  # Most ground control prevents striking

proc canGrapple*(fighter: Fighter, distance: DistanceKind): bool =
  ## Can fighter attempt grappling?
  distance in {Contact, Short} and hasFreeLimbs(fighter, 2)

# ============================================================================
# Combined prerequisite checks
# ============================================================================

proc checkBasicPrerequisites*(state: FightState, who: FighterID, move: Move): bool =
  ## Standard checks that apply to most moves
  let fighter = if who == FighterA: state.a else: state.b

  # Basic physical constraints
  if not canAffordMove(fighter, move): return false
  if not isBalanceAdequate(fighter, move): return false
  if not isMoveFatigueAppropriate(move, fighter.fatigue): return false
  if not canReachTarget(fighter, move, state.distance): return false
  if not hasFreeLimbs(fighter, 1): return false
  if not isStanceCompatible(fighter, move): return false

  # Category-specific checks
  case move.category
  of Straight, Arc, Whip, Push:
    if not canStrike(fighter): return false
  of Clinch, Throw, Takedown, Lock, Choke:
    if not canGrapple(fighter, state.distance): return false
  else:
    discard

  result = true

# ============================================================================
# Opponent state constraints
# ============================================================================

proc isOpponentVulnerable*(opponent: Fighter, move: Move): bool =
  ## Is opponent in a state where this move is more likely to work?
  case move.category
  of Throw, Takedown:
    # Easier when opponent off-balance or extended
    opponent.pos.balance < 0.6 or
    opponent.leftArm.extended or opponent.rightArm.extended
  of Sweep, Trip:
    # Easier when opponent weighted wrong
    opponent.pos.balance < 0.7
  of Lock, Choke:
    # Need limb or neck access
    not opponent.leftArm.free or not opponent.rightArm.free
  else:
    true  # Most strikes don't depend on opponent state

proc canOpponentRecover*(opponent: Fighter): bool =
  ## Can opponent recover from bad position?
  opponent.pos.balance >= 0.4 and opponent.fatigue < 0.85

# ============================================================================
# Terminal state detection
# ============================================================================

proc isTerminalPosition*(state: FightState): bool =
  ## Check if this is a fight-ending position
  # Check fighter A
  if state.a.pos.balance < 0.2: return true  # A falling
  if state.a.damage > 0.8: return true       # A incapacitated
  if state.a.fatigue > 0.95: return true     # A exhausted
  if not hasFreeLimbs(state.a, 1) and state.b.control in {Mount, BackControl, SideControl}:
    return true  # A fully controlled

  # Check fighter B
  if state.b.pos.balance < 0.2: return true  # B falling
  if state.b.damage > 0.8: return true       # B incapacitated
  if state.b.fatigue > 0.95: return true     # B exhausted
  if not hasFreeLimbs(state.b, 1) and state.a.control in {Mount, BackControl, SideControl}:
    return true  # B fully controlled

  # Check for dominant locks/chokes
  if state.a.control in {Lock, Choke} and state.b.pos.balance < 0.5:
    return true
  if state.b.control in {Lock, Choke} and state.a.pos.balance < 0.5:
    return true

  result = false

proc determineWinner*(state: FightState): FighterID =
  ## Determine who won in a terminal state
  # Compare overall states
  let aScore = state.a.pos.balance + (1.0 - state.a.damage) + (1.0 - state.a.fatigue)
  let bScore = state.b.pos.balance + (1.0 - state.b.damage) + (1.0 - state.b.fatigue)

  # Factor in control
  if state.a.control in {Mount, BackControl, Lock, Choke}: return FighterA
  if state.b.control in {Mount, BackControl, Lock, Choke}: return FighterB

  # Overall condition
  if aScore > bScore: FighterA else: FighterB
