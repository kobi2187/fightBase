## Combination System - Pre-planned strike sequences
## A combo is a sequence where individual strikes may fail but fighter maintains
## position, stance, balance, and continues the flow

import fight_types
import std/[options]

type
  ComboStrike* = object
    ## One strike within a combo
    moveId*: string              # Which move to execute
    optional*: bool              # Can skip if not viable
    successBranch*: Option[int]  # Index of next strike if this succeeds
    failBranch*: Option[int]     # Index of next strike if this misses
    maintainMomentum*: bool      # Keep moving even if misses

  Combo* = object
    ## A pre-planned combination of strikes
    id*: string
    name*: string
    strikes*: seq[ComboStrike]
    requiresSetup*: proc(state: FightState, who: FighterID): bool {.closure.}

    # Combo properties
    maintainsBalance*: bool      # Designed to keep balance throughout
    maintainsStance*: bool       # Returns to same stance
    flowBased*: bool             # Rhythm-based, misses don't stop flow
    commitmentLevel*: float      # 0.0-1.0, overall commitment

    # Tactical properties
    purpose*: ComboPurpose
    optionsAfter*: int           # Options created if combo completes
    exposureDuring*: float       # Average exposure during combo

  ComboPurpose* = enum
    cpPressure      # Pressure opponent, create openings
    cpDamage        # Maximum damage output
    cpSetup         # Set up a finish
    cpCounter       # Counter-attack sequence
    cpEscape        # Create space and escape
    cpControl       # Gain positional control

# ============================================================================
# Example Combos
# ============================================================================

proc createJabCrossHook*(): Combo =
  ## Classic boxing combo - flow-based, maintains balance
  ## Jab sets up, cross commits, hook finishes
  ## Even if jab/cross miss, hook still comes

  result = Combo(
    id: "jab_cross_hook",
    name: "Jab-Cross-Hook",
    strikes: @[
      # 1. Jab (probe)
      ComboStrike(
        moveId: "straight_strike",  # Using general straight strike
        optional: false,
        successBranch: some(1),     # → cross if lands
        failBranch: some(1),        # → cross even if misses
        maintainMomentum: true
      ),
      # 2. Cross (commitment)
      ComboStrike(
        moveId: "straight_strike",  # Same move, other hand
        optional: false,
        successBranch: some(2),     # → hook if lands
        failBranch: some(2),        # → hook even if misses (flow)
        maintainMomentum: true
      ),
      # 3. Hook (finish)
      ComboStrike(
        moveId: "arc_strike",       # Would be defined in general_moves
        optional: false,
        successBranch: none(int),   # End of combo
        failBranch: none(int),      # End of combo
        maintainMomentum: false     # Can stop after
      )
    ],
    maintainsBalance: true,         # Well-designed combo
    maintainsStance: true,          # Returns to orthodox/southpaw
    flowBased: true,                # Rhythm-based, misses OK
    commitmentLevel: 0.5,           # Moderate commitment
    purpose: cpPressure,            # Creates pressure and openings
    optionsAfter: 12,               # Many follow-up options
    exposureDuring: 0.3             # Some exposure but manageable
  )

  result.requiresSetup = proc(state: FightState, who: FighterID): bool =
    let fighter = if who == FighterA: state.a else: state.b
    # Need medium range, both hands free, decent balance
    result = state.distance in [Short, Medium] and
             fighter.leftArm.free and
             fighter.rightArm.free and
             fighter.pos.balance > 0.6 and
             fighter.fatigue < 0.7

proc createLowKickCross*(): Combo =
  ## Muay Thai classic - low kick to compromise base, then cross
  ## If kick misses, still throw cross (they're defending low)

  result = Combo(
    id: "low_kick_cross",
    name: "Low Kick → Cross",
    strikes: @[
      # 1. Low Kick (compromise mobility)
      ComboStrike(
        moveId: "low_kick",
        optional: false,
        successBranch: some(1),     # → cross (they're hurt)
        failBranch: some(1),        # → cross (they're defending low, head open)
        maintainMomentum: true
      ),
      # 2. Cross (high target while they protect low)
      ComboStrike(
        moveId: "straight_strike",
        optional: false,
        successBranch: none(int),
        failBranch: none(int),
        maintainMomentum: false
      )
    ],
    maintainsBalance: true,
    maintainsStance: true,
    flowBased: true,
    commitmentLevel: 0.6,           # Kick is fairly committed
    purpose: cpSetup,               # Sets up the cross
    optionsAfter: 10,
    exposureDuring: 0.45
  )

  result.requiresSetup = proc(state: FightState, who: FighterID): bool =
    let fighter = if who == FighterA: state.a else: state.b
    result = state.distance in [Short, Medium] and
             fighter.rightLeg.free and
             fighter.rightArm.free and
             fighter.pos.balance > 0.7 and
             fighter.fatigue < 0.65

proc createParryCounter*(): Combo =
  ## Defensive counter combo - parry their strike, immediately counter
  ## If parry fails (nothing to parry), don't throw counter

  result = Combo(
    id: "parry_counter",
    name: "Parry-Counter",
    strikes: @[
      # 1. Parry (defensive)
      ComboStrike(
        moveId: "parry_left",
        optional: false,
        successBranch: some(1),     # → counter if parry worked
        failBranch: none(int),      # Stop if nothing to parry
        maintainMomentum: false
      ),
      # 2. Counter strike (capitalize on opening)
      ComboStrike(
        moveId: "straight_strike",
        optional: true,             # Only if parry succeeded
        successBranch: none(int),
        failBranch: none(int),
        maintainMomentum: false
      )
    ],
    maintainsBalance: true,
    maintainsStance: true,
    flowBased: false,               # Reactive, not rhythm-based
    commitmentLevel: 0.2,           # Low commitment (defensive)
    purpose: cpCounter,
    optionsAfter: 15,               # Defensive position creates options
    exposureDuring: 0.1             # Very safe
  )

  result.requiresSetup = proc(state: FightState, who: FighterID): bool =
    let fighter = if who == FighterA: state.a else: state.b
    # Just need hands free and decent position
    result = fighter.leftArm.free and
             fighter.rightArm.free and
             fighter.pos.balance > 0.5

# ============================================================================
# Combo Execution System
# ============================================================================

type
  ComboState* = object
    ## Tracks execution of a combo
    combo*: Combo
    currentStrikeIndex*: int
    strikeResults*: seq[bool]     # true = success, false = miss
    totalTimeCost*: float
    totalEnergyCost*: float
    balanceMaintained*: bool      # Did we keep balance throughout?
    completed*: bool

proc executeComboStrike*(
  combo: Combo,
  strikeIndex: int,
  state: var FightState,
  who: FighterID,
  strikeSucceeded: bool
): Option[int] =
  ## Execute one strike in the combo, return next strike index if any
  ## Returns none(int) if combo should end

  if strikeIndex >= combo.strikes.len:
    return none(int)

  let strike = combo.strikes[strikeIndex]

  # Determine next strike based on success/failure
  if strikeSucceeded:
    result = strike.successBranch
  else:
    # If maintainMomentum is true, continue even on miss
    if strike.maintainMomentum and strike.failBranch.isSome:
      result = strike.failBranch
    else:
      # Miss and don't maintain momentum = stop combo
      result = none(int)

proc canExecuteCombo*(combo: Combo, state: FightState, who: FighterID): bool =
  ## Check if combo prerequisites are met
  if combo.requiresSetup != nil:
    result = combo.requiresSetup(state, who)
  else:
    result = true

# ============================================================================
# Combo Properties for Tactical Decisions
# ============================================================================

proc getComboRiskReward*(combo: Combo): float =
  ## Calculate risk/reward ratio for this combo
  ## Higher = better reward for the risk

  let reward = float(combo.optionsAfter) * (1.0 - combo.commitmentLevel)
  let risk = combo.exposureDuring * combo.commitmentLevel

  if risk < 0.01:
    result = reward * 100.0  # Very safe combo
  else:
    result = reward / risk

proc isComboFlowBased*(combo: Combo): bool =
  ## Flow-based combos maintain momentum even on misses
  result = combo.flowBased

proc comboMaintainsPosition*(combo: Combo): bool =
  ## Does this combo maintain good position/balance?
  result = combo.maintainsBalance and combo.maintainsStance

# ============================================================================
# Global Combo Registry
# ============================================================================

var ALL_COMBOS*: seq[Combo] = @[]

proc registerCombo*(combo: Combo) =
  ALL_COMBOS.add(combo)

proc registerAllCombos*() =
  ## Register all predefined combos
  registerCombo(createJabCrossHook())
  registerCombo(createLowKickCross())
  registerCombo(createParryCounter())

# ============================================================================
# Combo vs Individual Moves
# ============================================================================

## KEY DISTINCTION:
##
## INDIVIDUAL MOVES (ActionSequence):
##   - Simultaneous or quick succession
##   - Selected on-the-fly during simulation
##   - Time budget (0.6s per ply)
##   - Limb and type constraints
##   - Example: Slip + Parry + Counter (all in one ply)
##
## COMBOS:
##   - Pre-planned sequences spanning multiple plies
##   - Flow-based, maintain momentum through misses
##   - Each strike gets its own execution check
##   - Balance and stance maintained throughout
##   - Example: Jab(ply 1) → Cross(ply 2) → Hook(ply 3)
##
## Both can exist:
##   - A ply could contain: (Slip + Jab) as simultaneous ActionSequence
##   - That Jab could be part of a Jab-Cross-Hook combo
##   - Next ply would execute: (Cross) from the combo
##   - If Cross misses but maintainMomentum=true, next ply: (Hook)
