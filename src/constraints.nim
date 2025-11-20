## Constraint checking and prerequisite validation system
## These functions determine what moves are PHYSICALLY POSSIBLE from positions
##
## IMPORTANT: This module checks POSITION constraints only (stance, balance, limbs, control)
## Fatigue and damage checks belong in move.viabilityCheck (overlay-based filtering)

import fight_types
import physics
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
  of mcClinchEntry, mcLock, mcChoke: distance == Contact
  of mcStraightStrike, mcArcStrike, mcWhipStrike: distance in {Short, Medium}
  of mcPushStrike: distance in {Short, Medium, Long}
  of mcThrow, mcTakedown: distance in {Contact, Short}
  of mcSweep, mcTrip: distance in {Contact, Short}
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

proc canUseLimb*(limb: LimbPosition, move: Move): bool =
  ## Can this specific limb execute this move (position check only)?
  if not limb.free: return false
  if limb.extended and move.category in {mcStraightStrike, mcArcStrike}: return false
  # Note: Limb damage check is in viability, not here
  result = true

# ============================================================================
# Balance and stability constraints
# ============================================================================

proc isBalanceAdequate*(fighter: Fighter, move: Move): bool =
  ## Does fighter have enough balance for this move?
  case move.category
  of mcThrow, mcTakedown: fighter.pos.balance >= 0.6
  of mcArcStrike, mcWhipStrike: fighter.pos.balance >= 0.5
  of mcSweep, mcTrip: fighter.pos.balance >= 0.7
  else: fighter.pos.balance >= 0.3  # Most moves work with low balance

proc canPivot*(fighter: Fighter): bool =
  ## Can fighter pivot/turn (position check only)?
  fighter.pos.balance >= 0.5

proc canJump*(fighter: Fighter): bool =
  ## Can fighter jump or leave ground (position check only)?
  fighter.pos.balance >= 0.7

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
  of mcClinchEntry: fighter.liveSide in {Centerline, LiveSideLeft, LiveSideRight}
  of mcThrow: fighter.liveSide != DeadSideLeft and fighter.liveSide != DeadSideRight
  else: true  # Most strikes work from any angle

# ============================================================================
# Stance and posture constraints
# ============================================================================

proc isStanceCompatible*(fighter: Fighter, move: Move): bool =
  ## Is the current stance compatible with this move?
  # Most moves work from most stances, but some have preferences
  case move.category
  of mcThrow:
    # Throws harder from narrow stance
    fighter.pos.stance != skNarrow
  of mcTakedown:
    # Takedowns need mobile stance
    fighter.pos.stance in {skOrthodox, skSouthpaw, skSquare}
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
# Combined prerequisite checks (POSITION ONLY)
# ============================================================================

proc checkBasicPrerequisites*(state: FightState, who: FighterID, move: Move): bool =
  ## Standard checks that apply to most moves (POSITION CONSTRAINTS ONLY)
  ## Fatigue/damage filtering happens in move.viabilityCheck (overlay-based)
  let fighter = if who == FighterA: state.a else: state.b

  # Basic physical constraints (position-based)
  if not isBalanceAdequate(fighter, move): return false
  if not canReachTarget(fighter, move, state.distance): return false
  if not hasFreeLimbs(fighter, 1): return false
  if not isStanceCompatible(fighter, move): return false

  # Physics-based constraints (momentum, biomechanics)
  if not validateMovePhysics(fighter, move): return false

  # Category-specific checks
  case move.category
  of mcStraightStrike, mcArcStrike, mcWhipStrike, mcPushStrike:
    if not canStrike(fighter): return false
  of mcClinchEntry, mcThrow, mcTakedown, mcLock, mcChoke:
    if not canGrapple(fighter, state.distance): return false
  else:
    discard

  result = true

# ============================================================================
# Opponent state constraints (position-based)
# ============================================================================

proc isOpponentVulnerable*(opponent: Fighter, move: Move): bool =
  ## Is opponent in a state where this move is more likely to work?
  case move.category
  of mcThrow, mcTakedown:
    # Easier when opponent off-balance or extended
    opponent.pos.balance < 0.6 or
    opponent.leftArm.extended or opponent.rightArm.extended
  of mcSweep, mcTrip:
    # Easier when opponent weighted wrong
    opponent.pos.balance < 0.7
  of mcLock, mcChoke:
    # Need limb or neck access
    not opponent.leftArm.free or not opponent.rightArm.free
  else:
    true  # Most strikes don't depend on opponent state

# ============================================================================
# Terminal state detection (requires overlays for damage/fatigue)
# ============================================================================

proc isTerminalPosition*(state: FightState): bool =
  ## Check if this is a fight-ending position (POSITION ONLY)
  ## Note: Damage/fatigue checks should be done with overlays in simulator
  # Check fighter A
  if state.a.pos.balance < 0.2: return true  # A falling
  if not hasFreeLimbs(state.a, 1) and state.b.control in {Mount, BackControl, SideControl}:
    return true  # A fully controlled

  # Check fighter B
  if state.b.pos.balance < 0.2: return true  # B falling
  if not hasFreeLimbs(state.b, 1) and state.a.control in {Mount, BackControl, SideControl}:
    return true  # B fully controlled

  # Check for dominant locks/chokes
  if state.a.control in {Lock, Choke} and state.b.pos.balance < 0.5:
    return true
  if state.b.control in {Lock, Choke} and state.a.pos.balance < 0.5:
    return true

  result = false

proc isTerminalWithOverlays*(state: FightState, overlayA: RuntimeOverlay, overlayB: RuntimeOverlay): bool =
  ## Check terminal condition including overlay data
  # Position-based terminal
  if isTerminalPosition(state): return true

  # Overlay-based terminal (damage/fatigue)
  if overlayA.damage > 0.8: return true       # A incapacitated
  if overlayA.fatigue > 0.95: return true     # A exhausted
  if overlayB.damage > 0.8: return true       # B incapacitated
  if overlayB.fatigue > 0.95: return true     # B exhausted

  result = false

proc determineWinner*(state: FightState): FighterID =
  ## Determine who won in a terminal state (position-based)
  ## For overlay-aware winner determination, use determineWinnerWithOverlays
  # Factor in control
  if state.a.control in {Mount, BackControl, Lock, Choke}: return FighterA
  if state.b.control in {Mount, BackControl, Lock, Choke}: return FighterB

  # Overall balance condition
  if state.a.pos.balance > state.b.pos.balance: FighterA else: FighterB

proc determineWinnerWithOverlays*(state: FightState, overlayA: RuntimeOverlay, overlayB: RuntimeOverlay): FighterID =
  ## Determine winner considering both position and overlays
  # Compare overall states (position + overlay)
  let aScore = state.a.pos.balance + (1.0 - overlayA.damage) + (1.0 - overlayA.fatigue)
  let bScore = state.b.pos.balance + (1.0 - overlayB.damage) + (1.0 - overlayB.fatigue)

  # Factor in control
  if state.a.control in {Mount, BackControl, Lock, Choke}: return FighterA
  if state.b.control in {Mount, BackControl, Lock, Choke}: return FighterB

  # Overall condition
  if aScore > bScore: FighterA else: FighterB
