## Every number the fight model uses, in one place.
##
## These are ASSUMPTIONS, not measurements. The solver finds the optimal play
## *for these numbers*; `fightsolve sensitivity` shows which conclusions
## survive when they are perturbed, and `fightsolve calibrate` fits the few
## global knobs to real fight-outcome statistics. Treat any conclusion that
## flips under a modest perturbation as an artefact of the guesses.
##
## Conventions
## - Probabilities are per beat (one exchange, roughly a second or two).
## - "x mult" parameters multiply a probability; results are clamped to
##   [0, `maxProb`].
## - Damage and fatigue are discrete levels (see `Dims`); the defaults are
##   written for 4 damage levels and 3 fatigue levels and are rescaled
##   automatically for other resolutions (`effective`).

import std/[json, strutils, strformat, tables]
import core

type
  ActionTable* = array[Action, float]

  Params* = object
    # ---- fight framing -------------------------------------------------
    stopChance*: float      ## per-beat chance the fight is stopped and goes to a decision
    decisionWeight*: float  ## decision win-probability shift per damage level of difference
    decisionTop*: float     ## decision shift for being on top in guard or standing over a downed opponent
    decisionDominant*: float ## decision shift for holding mount or back control
    maxProb*: float         ## cap on any single success probability

    # ---- striking ------------------------------------------------------
    hitLong*: ActionTable   ## land probability vs a passive opponent at kicking range (0 = can't)
    hitMid*: ActionTable    ## ... at punching range
    hitClose*: ActionTable  ## ... at elbow/knee range
    hitClinch*: ActionTable ## ... in an even clinch
    dmg1*: ActionTable      ## P(+1 damage level | landed)
    dmg2*: ActionTable      ## P(+2 damage levels | landed)
    commit*: ActionTable    ## P(attacker ends off-balance | technique missed or failed)
    cost*: ActionTable      ## P(fatigue +1) when performing the action
    recover*: ActionTable   ## P(fatigue -1) when performing the action
    damageScale*: float     ## global multiplier on all damage probabilities (calibration knob)
    hitScale*: float        ## global multiplier on all strike land chances (calibration knob)

    knockdown*: float       ## P(knockdown | standing strike dealt +2 levels)
    stagger*: float         ## P(target off-balance | strike dealt damage)
    teepOff*: float         ## P(target off-balance | teep landed)
    interruptLight*: float  ## a faster jab/teep that lands cuts the slower action's success by this fraction
    interruptHeavy*: float  ## same for any other faster technique that succeeds

    # ---- standing defence ---------------------------------------------
    coverHit*: float        ## x mult on hit chance vs a covering fighter
    coverDmg*: float        ## x mult on damage chances vs a covering fighter
    slipPunch*: float       ## x mult on punch hit chance vs a slipping fighter
    slipKick*: float        ## x mult on kick hit chance vs a slipping fighter
    slipAngle*: float       ## P(slipper takes the angle | the punch missed)
    retreatHit*: float      ## x mult on punch hit chance vs a retreating fighter
    retreatKick*: float     ## x mult on kick/teep hit chance vs a retreating fighter
    advanceHit*: float      ## x mult on hit chance vs a fighter stepping in
    advanceDmg*: float      ## x mult on damage vs a fighter stepping in
    jamKick*: float         ## x mult on kick hit chance and damage vs a fighter stepping into it
    circleHit*: float       ## x mult on hit chance vs a circling fighter
    shootDuck*: float       ## x mult on punch hit chance vs a fighter changing levels to shoot
    sprawlExposed*: float   ## x mult on hit chance vs a fighter who sprawled at nothing
    counterHit*: float      ## P(a counter lands | the opponent threw a strike)
    counterDef*: float      ## x mult on a strike's hit chance vs a fighter waiting to counter
    feintDraw*: float       ## P(a fighter waiting to counter or slip bites on a feint and ends off-balance)

    # ---- angles, balance, condition -------------------------------------
    angleAtk*: float        ## x mult on success when attacking from the angle
    angleDef*: float        ## x mult on success when attacking a fighter who holds the angle
    angleKeep*: float       ## P(an angle survives a beat in which nobody renews it)
    circleBase*: float      ## P(circling takes the angle)
    circleVsCircle*: float  ## x mult when both fighters circle
    offAtk*: float          ## x mult on an off-balance fighter's own success chances
    offDef*: float          ## x mult on strikes landing on an off-balance fighter
    offGrapple*: float      ## x mult on takedowns/throws/clinch entries vs an off-balance fighter
    fatiguePenalty*: float  ## own success x (1 - this * fatigue level)
    fatigueDefense*: float  ## incoming hit chance x (1 + this * fatigue level)
    damagePenalty*: float   ## own success x (1 - this * damage level)
    chinPenalty*: float     ## incoming damage chances x (1 + this * damage level)

    # ---- takedowns and clinch entry ----------------------------------
    shootLong*: float       ## takedown success from kicking range vs a passive opponent
    shootMid*: float        ## ... from punching range
    shootClose*: float      ## ... from elbow/knee range
    sprawlStop*: float      ## x mult on takedown success vs a sprawl
    sprawlBack*: float      ## P(sprawler takes the back | sprawl stuffed the shot)
    guillotine*: float      ## P(sprawler finishes with a front choke | sprawl stuffed the shot)
    shootVsCommit*: float   ## x mult on takedowns timed under a cross/hook
    shootVsKick*: float     ## x mult on takedowns vs a kick (catch the leg)
    shootVsRetreat*: float  ## x mult on takedowns vs a retreating fighter
    shootVsAdvance*: float  ## x mult on takedowns vs a fighter stepping in
    shootBoth*: float       ## x mult when both fighters shoot
    clinchBase*: float      ## clinch entry success from close range
    clinchMid*: float       ## clinch entry success from punching range
    clinchVsRetreat*: float ## x mult on clinch entry vs a retreating fighter

    # ---- clinch --------------------------------------------------------
    pummelGain*: float      ## P(win dominant ties from an even clinch)
    pummelRecover*: float   ## P(get back to even from an inferior clinch)
    kneeDom*: float         ## x mult on knees from dominant ties
    kneeSub*: float         ## x mult on knees from inferior ties
    kneeVsPummel*: float    ## x mult on knees vs a fighter busy pummelling
    throwDom*: float        ## throw/trip success from dominant ties
    throwEven*: float       ## ... from an even clinch
    throwSub*: float        ## ... from inferior ties
    throwVsKnee*: float     ## x mult on throws vs a fighter standing on one leg to knee
    throwVsCover*: float    ## x mult on throws vs a fighter posturing up
    breakBase*: float       ## P(breaking the clinch vs a fighter who wants to hold it)
    breakVsDom*: float      ## x mult on breaking away from dominant ties

    # ---- one fighter down ----------------------------------------------
    followBase*: float      ## P(following a downed fighter into top position)
    followVsGetUp*: float   ## ... when they are getting up at that moment
    upkickHit*: float       ## upkick land chance vs a fighter following you down
    refStandUp*: float      ## P(referee restarts standing | both fighters stall, one down or on the ground)

    # ---- ground ----------------------------------------------------------
    poundGuard*: float      ## ground strike land chance from top in guard
    poundMount*: float      ## ... from mount
    poundBack*: float       ## ... from back control
    passGuard*: float       ## P(pass guard to mount)
    passMount*: float       ## P(take the back from mount)
    subMount*: float        ## P(submission from mount)
    subBack*: float         ## P(submission from back control)
    guardSub*: float        ## P(submission from bottom guard)
    submissionScale*: float ## global multiplier on submission chances (calibration knob)
    grappleScale*: float    ## global multiplier on takedowns, throws, clinch entries and passes (calibration knob)
    sweep*: float           ## P(sweep from guard to top)
    escapeMount*: float     ## P(escape mount to guard)
    escapeBack*: float      ## P(escape back control to guard)
    escapeGuard*: float     ## P(stand up from bottom guard)
    standUpBack*: float     ## P(top takes the back | a stand-up from guard failed)
    mountTurnBack*: float   ## P(top takes the back | a mount escape failed: the bottom fighter turned)
    disengage*: float       ## P(top fighter disengages back to standing)
    holdControl*: float     ## x mult on bottom escapes/sweeps/subs vs a top fighter holding
    coverGround*: float     ## x mult on strikes and submissions vs a bottom fighter covering
    poundExposes*: float    ## x mult on sweeps/guard subs vs a top fighter throwing strikes
    passExposes*: float     ## x mult on sweeps/guard subs vs a top fighter passing
    subFailEscape*: float   ## P(bottom fighter improves position | top submission failed)
    guardSubFailPass*: float ## P(top passes to mount | guard submission failed)
    bottomFatigue*: float   ## extra P(fatigue +1) per beat under mount or back control

proc defaultParams*(): Params =
  result = Params(
    stopChance: 0.02, decisionWeight: 0.15, decisionTop: 0.06,
    decisionDominant: 0.12, maxProb: 0.95,
    damageScale: 1.0, hitScale: 1.0, submissionScale: 1.0, grappleScale: 1.0,
    jamKick: 0.6,
    shootLong: 0.15, refStandUp: 0.3, counterHit: 0.5, counterDef: 0.6,
    feintDraw: 0.6, clinchMid: 0.3, guillotine: 0.12, standUpBack: 0.15,
    mountTurnBack: 0.2,
    knockdown: 0.5, stagger: 0.35, teepOff: 0.4,
    interruptLight: 0.25, interruptHeavy: 0.5,
    coverHit: 0.7, coverDmg: 0.5, slipPunch: 0.4, slipKick: 1.1, slipAngle: 0.5,
    retreatHit: 0.5, retreatKick: 0.8, advanceHit: 1.2, advanceDmg: 1.3,
    circleHit: 0.85, shootDuck: 0.6, sprawlExposed: 1.15,
    angleAtk: 1.3, angleDef: 0.75, angleKeep: 0.5, circleBase: 0.45,
    circleVsCircle: 0.5, offAtk: 0.7, offDef: 1.3, offGrapple: 1.5,
    fatiguePenalty: 0.15, fatigueDefense: 0.1, damagePenalty: 0.08,
    chinPenalty: 0.2,
    shootMid: 0.30, shootClose: 0.40, sprawlStop: 0.25, sprawlBack: 0.25,
    shootVsCommit: 1.4, shootVsKick: 1.5, shootVsRetreat: 0.5,
    shootVsAdvance: 1.2, shootBoth: 0.5, clinchBase: 0.55, clinchVsRetreat: 0.3,
    pummelGain: 0.35, pummelRecover: 0.45, kneeDom: 1.5, kneeSub: 0.5,
    kneeVsPummel: 1.15, throwDom: 0.40, throwEven: 0.22, throwSub: 0.08,
    throwVsKnee: 1.4, throwVsCover: 0.7, breakBase: 0.6, breakVsDom: 0.6,
    followBase: 0.85, followVsGetUp: 0.45, upkickHit: 0.30,
    poundGuard: 0.30, poundMount: 0.55, poundBack: 0.45,
    passGuard: 0.22, passMount: 0.15, subMount: 0.18, subBack: 0.30,
    guardSub: 0.07, sweep: 0.15, escapeMount: 0.22, escapeBack: 0.20,
    escapeGuard: 0.25, disengage: 0.7, holdControl: 0.6, coverGround: 0.6,
    poundExposes: 1.3, passExposes: 1.3, subFailEscape: 0.35,
    guardSubFailPass: 0.25, bottomFatigue: 0.15)

  result.hitLong[aKick] = 0.40
  result.hitLong[aTeep] = 0.45
  result.hitMid[aJab] = 0.55
  result.hitMid[aCross] = 0.45
  result.hitMid[aHook] = 0.25
  result.hitMid[aKick] = 0.45
  result.hitMid[aTeep] = 0.50
  result.hitClose[aJab] = 0.45
  result.hitClose[aCross] = 0.40
  result.hitClose[aHook] = 0.45
  result.hitClose[aKnee] = 0.30
  result.hitClinch[aKnee] = 0.40

  for (a, d1, d2) in [(aJab, 0.15, 0.0), (aCross, 0.40, 0.08), (aHook, 0.40, 0.12),
                      (aKick, 0.40, 0.10), (aTeep, 0.10, 0.0), (aKnee, 0.40, 0.10),
                      (aUpkick, 0.35, 0.10), (aPound, 0.30, 0.05), (aThrow, 0.25, 0.05),
                      (aCounter, 0.45, 0.12)]:
    result.dmg1[a] = d1
    result.dmg2[a] = d2

  for (a, c) in [(aCross, 0.10), (aHook, 0.20), (aKick, 0.35), (aTeep, 0.10),
                 (aKnee, 0.10), (aShoot, 0.40), (aThrow, 0.40), (aCounter, 0.05)]:
    result.commit[a] = c

  for (a, c) in [(aAdvance, 0.03), (aRetreat, 0.02), (aCircle, 0.04), (aJab, 0.05),
                 (aCross, 0.10), (aHook, 0.12), (aKick, 0.20), (aTeep, 0.08),
                 (aSlip, 0.05), (aCounter, 0.08), (aFeint, 0.03), (aShoot, 0.30), (aSprawl, 0.15), (aClinch, 0.10),
                 (aKnee, 0.12), (aPummel, 0.10), (aThrow, 0.25), (aBreak, 0.05),
                 (aFollow, 0.10), (aGetUp, 0.10), (aUpkick, 0.08), (aPound, 0.12),
                 (aPass, 0.15), (aSubmit, 0.25), (aDisengage, 0.05),
                 (aEscape, 0.20), (aSweep, 0.20), (aGuardSub, 0.20)]:
    result.cost[a] = c

  for (a, r) in [(aAdvance, 0.05), (aRetreat, 0.15), (aCircle, 0.05), (aCover, 0.12),
                 (aBreak, 0.10), (aBackOff, 0.25), (aHold, 0.20), (aDisengage, 0.10)]:
    result.recover[a] = r

# ---------------------------------------------------------------------------
# Resolution scaling: same physics on a finer or coarser grid
# ---------------------------------------------------------------------------

proc effective*(p: Params, d: Dims): Params =
  ## Defaults are written for 4 damage and 3 fatigue levels. On another grid,
  ## rescale so the expected number of landed strikes to a knockout, and the
  ## time to exhaustion, stay the same.
  result = p
  let ds = d.damageLevels.float / defaultDims.damageLevels.float
  let fs = (d.fatigueLevels - 1).float / (defaultDims.fatigueLevels - 1).float
  for a in Action:
    # Expected damage levels per landing scale with the grid (and damageScale).
    var d1 = p.dmg1[a] * p.damageScale * ds
    var d2 = p.dmg2[a] * p.damageScale * ds
    if d1 + d2 > 1.0:
      # Not a valid distribution any more: every landing now does at least
      # one level; keep the expected damage (capped at 2 levels).
      let expected = min(2.0, d1 + 2.0 * d2)
      d2 = clamp(expected - 1.0, 0.0, 1.0)
      d1 = 1.0 - d2
    result.dmg1[a] = d1
    result.dmg2[a] = d2
    result.cost[a] = min(1.0, p.cost[a] * fs)
    result.recover[a] = min(1.0, p.recover[a] * fs)
  result.damageScale = 1.0
  result.decisionWeight = p.decisionWeight / ds
  result.damagePenalty = p.damagePenalty / ds
  result.chinPenalty = p.chinPenalty / ds
  result.fatiguePenalty = p.fatiguePenalty / max(fs, 1e-9)
  result.fatigueDefense = p.fatigueDefense / max(fs, 1e-9)
  result.bottomFatigue = min(1.0, p.bottomFatigue * fs)
  for x in [addr result.subMount, addr result.subBack, addr result.guardSub,
            addr result.guillotine]:
    x[] = x[] * p.submissionScale
  result.submissionScale = 1.0
  for x in [addr result.shootLong, addr result.shootMid, addr result.shootClose,
            addr result.throwDom, addr result.throwEven, addr result.throwSub,
            addr result.clinchBase, addr result.clinchMid, addr result.passGuard,
            addr result.passMount]:
    x[] = x[] * p.grappleScale
  result.grappleScale = 1.0

# ---------------------------------------------------------------------------
# Named access, for sensitivity analysis, calibration and JSON files
# ---------------------------------------------------------------------------

proc paramNames*(p: Params, includeZero = false): seq[string] =
  ## Scalar names ("knockdown") and table entries ("hitMid.Jab"). Zero table
  ## entries mean "not applicable" and are skipped unless asked for.
  for k, v in p.fieldPairs:
    when v is float:
      result.add k
    elif v is ActionTable:
      for a in Action:
        if includeZero or v[a] != 0.0:
          result.add k & "." & a.name

proc tableNames*(): seq[string] =
  var p: Params
  for k, v in p.fieldPairs:
    when v is ActionTable:
      result.add k

proc getParam*(p: Params, name: string): float =
  let parts = name.split('.')
  for k, v in p.fieldPairs:
    when v is float:
      if parts.len == 1 and k == parts[0]: return v
    elif v is ActionTable:
      if parts.len == 2 and k == parts[0]: return v[parseAction(parts[1])]
  raise newException(KeyError, "unknown parameter: " & name)

proc setParam*(p: var Params, name: string, value: float) =
  let parts = name.split('.')
  for k, v in p.fieldPairs:
    when v is float:
      if parts.len == 1 and k == parts[0]:
        v = value
        return
    elif v is ActionTable:
      if parts.len == 2 and k == parts[0]:
        v[parseAction(parts[1])] = value
        return
  raise newException(KeyError, "unknown parameter: " & name)

proc isMultiplier*(name: string): bool =
  ## Multipliers may exceed 1; everything else is a probability or a
  ## per-level coefficient and is kept in [0, 1] when perturbed.
  const mults = ["slipKick", "advanceHit", "advanceDmg", "sprawlExposed",
                 "angleAtk", "offDef", "offGrapple", "shootVsCommit",
                 "shootVsKick", "shootVsAdvance", "kneeDom", "kneeVsPummel",
                 "throwVsKnee", "poundExposes", "passExposes", "damageScale",
                 "hitScale", "submissionScale", "grappleScale"]
  name in mults

proc perturbed*(p: Params, name: string, factor: float): Params =
  result = p
  var v = p.getParam(name) * factor
  if not isMultiplier(name.split('.')[0]):
    v = clamp(v, 0.0, 1.0)
  result.setParam(name, v)

proc toJson*(p: Params): JsonNode =
  result = newJObject()
  for k, v in p.fieldPairs:
    when v is float:
      result[k] = %v
    elif v is ActionTable:
      var t = newJObject()
      for a in Action:
        if v[a] != 0.0: t[a.name] = %v[a]
      result[k] = t

proc applyJson*(p: var Params, j: JsonNode) =
  ## Override any subset of parameters. Unknown keys are an error so typos
  ## do not silently fall back to defaults.
  for key, val in j.pairs:
    if val.kind == JObject:
      var known = false
      for t in tableNames():
        if t == key: known = true
      if not known: raise newException(KeyError, "unknown parameter table: " & key)
      for an, av in val.pairs:
        p.setParam(key & "." & an, av.getFloat)
    else:
      p.setParam(key, val.getFloat)

proc loadParams*(path: string): Params =
  result = defaultParams()
  result.applyJson(parseFile(path))

proc describe*(p: Params): string =
  var lines: seq[string]
  for name in p.paramNames:
    lines.add &"{name:<24} {p.getParam(name):.4f}"
  lines.join("\n")

proc diff*(a, b: Params): Table[string, (float, float)] =
  for name in a.paramNames(includeZero = true):
    let x = a.getParam(name)
    let y = b.getParam(name)
    if abs(x - y) > 1e-12: result[name] = (x, y)
