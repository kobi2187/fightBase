## Physics-based validation for moves based on momentum and biomechanical state

import fight_types
import std/math

# ============================================================================
# Momentum management
# ============================================================================

proc applyMomentumDecay*(fighter: var Fighter) =
  ## Apply natural decay to momentum each turn
  fighter.momentum.linear *= fighter.momentum.decayRate
  fighter.momentum.rotational *= fighter.momentum.decayRate

  # Zero out very small values
  if abs(fighter.momentum.linear) < 0.01:
    fighter.momentum.linear = 0.0
  if abs(fighter.momentum.rotational) < 1.0:
    fighter.momentum.rotational = 0.0

proc addMomentum*(fighter: var Fighter, linear, rotational: float) =
  ## Add momentum from a move
  fighter.momentum.linear += linear
  fighter.momentum.rotational += rotational

proc applyRecovery*(fighter: var Fighter) =
  ## Decrement recovery frames
  if fighter.biomech.recoveryFrames > 0:
    dec fighter.biomech.recoveryFrames
    if fighter.biomech.recoveryFrames == 0:
      fighter.biomech.recovering = false

proc setRecovering*(fighter: var Fighter, frames: int) =
  ## Put fighter into recovery state
  fighter.biomech.recovering = true
  fighter.biomech.recoveryFrames = frames

# ============================================================================
# Biomechanical state updates
# ============================================================================

proc updateBiomechanics*(fighter: var Fighter, effect: PhysicsEffect) =
  ## Update biomechanical state based on move physics
  fighter.biomech.hipRotation += effect.hipRotationDelta
  fighter.biomech.torsoRotation += effect.torsoRotationDelta
  fighter.biomech.weightDistribution = clamp(
    fighter.biomech.weightDistribution + effect.weightShift,
    0.0, 1.0
  )

  # Clamp rotations to realistic limits
  fighter.biomech.hipRotation = clamp(fighter.biomech.hipRotation, -180.0, 180.0)
  fighter.biomech.torsoRotation = clamp(fighter.biomech.torsoRotation, -90.0, 90.0)

proc naturalBiomechanicalDecay*(fighter: var Fighter) =
  ## Body naturally returns toward neutral position
  # Hips drift back to neutral
  if fighter.biomech.hipRotation > 0:
    fighter.biomech.hipRotation = max(0.0, fighter.biomech.hipRotation - 10.0)
  elif fighter.biomech.hipRotation < 0:
    fighter.biomech.hipRotation = min(0.0, fighter.biomech.hipRotation + 10.0)

  # Torso returns to neutral
  if fighter.biomech.torsoRotation > 0:
    fighter.biomech.torsoRotation = max(0.0, fighter.biomech.torsoRotation - 15.0)
  elif fighter.biomech.torsoRotation < 0:
    fighter.biomech.torsoRotation = min(0.0, fighter.biomech.torsoRotation + 15.0)

  # Weight distribution returns toward balanced
  if fighter.biomech.weightDistribution > 0.5:
    fighter.biomech.weightDistribution = max(0.5, fighter.biomech.weightDistribution - 0.1)
  elif fighter.biomech.weightDistribution < 0.5:
    fighter.biomech.weightDistribution = min(0.5, fighter.biomech.weightDistribution + 0.1)

# ============================================================================
# Physics-based move validation
# ============================================================================

proc hasExcessiveMomentum*(fighter: Fighter): bool =
  ## Check if fighter has too much momentum to control movements
  abs(fighter.momentum.linear) > 2.0 or abs(fighter.momentum.rotational) > 90.0

proc canRedirectMomentum*(fighter: Fighter, move: Move): bool =
  ## Check if fighter can redirect current momentum for this move

  # If no significant momentum, can do anything
  if abs(fighter.momentum.linear) < 0.5 and abs(fighter.momentum.rotational) < 20.0:
    return true

  # High linear momentum limits lateral/rotational moves
  if abs(fighter.momentum.linear) > 1.5:
    # Can only do moves that continue forward or stop
    if move.physicsEffect.linearMomentum < -0.5:  # Trying to reverse direction
      return false
    if abs(move.physicsEffect.rotationalMomentum) > 45.0:  # Big rotation
      return false

  # High rotational momentum limits direction changes
  if abs(fighter.momentum.rotational) > 60.0:
    # Must continue rotation or stop
    let momentumSign = if fighter.momentum.rotational > 0: 1.0 else: -1.0
    let moveSign = if move.physicsEffect.rotationalMomentum > 0: 1.0 else: -1.0

    # If trying to rotate opposite direction, cannot do it
    if moveSign != 0.0 and moveSign != momentumSign:
      return false

  result = true

proc isBiomechanicallyViable*(fighter: Fighter, move: Move): bool =
  ## Check if move is possible given current body configuration

  # Cannot do anything while in heavy recovery
  if fighter.biomech.recovering and fighter.biomech.recoveryFrames > 2:
    # Only very light defensive moves allowed
    if move.physicsEffect.commitmentLevel > 0.2:
      return false

  # Hip rotation affects available strikes
  let absHipRot = abs(fighter.biomech.hipRotation)

  if absHipRot > 60.0:
    # Hips heavily rotated - limited options
    case move.category
    of mcStraightStrike, mcArcStrike:
      # Can only strike on the side the hips are rotated toward
      # For now, simplified: just harder to do opposite strikes
      if move.physicsEffect.hipRotationDelta * fighter.biomech.hipRotation < 0:
        # Trying to rotate opposite way - need to unwind first
        return false
    of mcThrow, mcTakedown:
      # Throws require neutral hips
      return false
    else:
      discard

  # Extreme weight distribution limits mobility
  if fighter.biomech.weightDistribution < 0.2 or fighter.biomech.weightDistribution > 0.8:
    # Weight heavily on one leg
    case move.category
    of mcSweep, mcTrip, mcThrow:
      return false  # Need balanced base
    else:
      discard

  result = true

proc canRecoverFromMomentum*(fighter: Fighter, move: Move): bool =
  ## Check if fighter can recover after this move given current momentum
  # Moves with high commitment are dangerous when you already have momentum
  if abs(fighter.momentum.linear) > 1.0 or abs(fighter.momentum.rotational) > 45.0:
    if move.physicsEffect.commitmentLevel > 0.7:
      # Too risky - already off-balance with momentum
      return false

  result = true

proc validateMovePhysics*(fighter: Fighter, move: Move): bool =
  ## Complete physics validation for a move

  # Check all physics constraints
  if not canRedirectMomentum(fighter, move):
    return false

  if not isBiomechanicallyViable(fighter, move):
    return false

  if not canRecoverFromMomentum(fighter, move):
    return false

  result = true

# ============================================================================
# Balance and momentum interaction
# ============================================================================

proc momentumAffectsBalance*(fighter: Fighter): float =
  ## Calculate balance penalty from excessive momentum
  let linearPenalty = abs(fighter.momentum.linear) * 0.1
  let rotationalPenalty = abs(fighter.momentum.rotational) * 0.001
  result = min(0.3, linearPenalty + rotationalPenalty)

proc getEffectiveBalance*(fighter: Fighter): float =
  ## Get balance adjusted for momentum
  result = fighter.pos.balance - momentumAffectsBalance(fighter)
  result = max(0.0, result)

# ============================================================================
# Initialization helpers
# ============================================================================

proc createNeutralMomentum*(): Momentum =
  ## Create momentum in neutral state
  Momentum(
    linear: 0.0,
    rotational: 0.0,
    decayRate: 0.7  # 70% remains each turn
  )

proc createNeutralBiomech*(): BiomechanicalState =
  ## Create biomechanical state in neutral position
  BiomechanicalState(
    hipRotation: 0.0,
    torsoRotation: 0.0,
    weightDistribution: 0.5,  # 50/50
    recovering: false,
    recoveryFrames: 0
  )
