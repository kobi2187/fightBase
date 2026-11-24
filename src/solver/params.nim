## Every number the fight model uses, in one place.
##
## These are ASSUMPTIONS, not measurements. The solver finds the optimal play
## *for these numbers*; `fightsolve sensitivity` and the playbook's
## robustness column show which conclusions survive when they are perturbed.
## Treat any conclusion that flips under a modest perturbation as an artefact
## of the guesses.
##
## Conventions
## - Probabilities are per beat (one exchange, roughly a second).
## - "x mult" parameters multiply a probability or a force; probabilities are
##   clamped to [0, `maxProb`].
## - Forces are in newtons as in the repo's biomechanics documents
##   (biomechanical_movement_library.md); `forceScale` converts them to the
##   same scale as the target thresholds in src/vulnerabilities.nim.

import std/[json, strutils, strformat, tables]
import core

type
  ActionTable* = array[Action, float]
  MechTable* = array[Mechanics, float]

  Params* = object
    # ---- framing ---------------------------------------------------------
    stopChance*: float      ## per-beat chance the encounter ends without a finish
    maxProb*: float         ## cap on any single success probability
    harmPerLevel*: float    ## self-defense: safety lost per damage level you carry when it ends
    harmDown*: float        ## self-defense: safety lost if it ends with you down or underneath
    harmPinned*: float      ## self-defense: extra loss if it ends with you mounted, back taken or held from behind
    decisionWeight*: float  ## sport: decision shift per damage level of difference
    decisionTop*: float     ## sport: decision shift for top position / standing over a downed opponent
    decisionDominant*: float ## sport: decision shift for mount or back control
    refStandUp*: float      ## sport: P(referee restarts standing | both fighters stall)

    # ---- global calibration knobs ----------------------------------------
    forceScale*: float      ## technique force -> target-threshold scale
    effBase*: float         ## effect strength when the force just reaches a zone's threshold
    effSlope*: float        ## effect strength gained per doubling of force over the threshold
    precisionScale*: float  ## multiplier on the chance a landed strike hits its zone squarely
    glanceForce*: float     ## fraction of force delivered by a strike that lands off-target
    hitScale*: float        ## multiplier on all strike land chances
    damageScale*: float     ## multiplier on damage chances
    stunScale*: float       ## multiplier on stun chances
    legsScale*: float       ## multiplier on leg-injury chances
    grappleScale*: float    ## multiplier on takedowns, throws, grabs and passes
    submissionScale*: float ## multiplier on choke/submission chances

    # ---- techniques (per action) -------------------------------------------
    hitLong*: ActionTable   ## land chance vs a passive opponent at kicking range (0 = can't)
    hitMid*: ActionTable    ## ... at punching range
    hitClose*: ActionTable  ## ... at elbow/knee range
    hitClinch*: ActionTable ## ... tied up (even grips)
    hitBehind*: ActionTable ## ... striking backwards while held from behind
    hitOver*: ActionTable   ## ... between a standing and a downed fighter
    force*: ActionTable     ## force at full power (N)
    commit*: ActionTable    ## P(off-balance | the technique missed or failed)

    # ---- body mechanics -----------------------------------------------------
    unloadedPower*: float   ## x mult on force of a rotational strike from the unloaded side (it is also one step slower)
    offPower*: float        ## x mult on force while off-balance
    legsPower*: float       ## x mult on kick force and footwork with hurt legs
    advanceForce*: float    ## x mult on force vs a fighter stepping into the strike
    interceptHit*: float    ## x mult on straight strikes (linear/whip/push) vs a committing attack
    knockdown*: float       ## P(knockdown | standing strike dealt 2 levels)
    stagger*: float         ## P(target off-balance | strike dealt damage)
    pushOff*: float         ## P(target off-balance | push/teep landed)
    interruptLight*: float  ## a faster light strike (linear/whip/push) that lands cuts the slower action's success by this fraction
    interruptHeavy*: float  ## same for any other faster technique that succeeds

    # ---- defence vs mechanics ----------------------------------------------
    coverVs*: MechTable     ## x mult on hit chance vs a covering fighter (head/body targets)
    coverForce*: float      ## x mult on force absorbed by a cover
    slipVs*: MechTable      ## x mult on hit chance vs a fighter slipping / stepping offline
    parryVs*: MechTable     ## x mult on hit chance vs a fighter deflecting
    counterVs*: MechTable   ## x mult on hit chance vs a fighter set to counter
    counterHit*: float      ## P(counter lands | the opponent attacked with a strike)
    slipAngle*: float       ## P(take the outside angle | slipped a strike)
    parryOff*: float        ## P(attacker off-balance | deflected)
    feintDraw*: float       ## P(a fighter waiting to counter/parry/slip bites on a feint and ends off-balance)
    retreatHit*: float      ## x mult on hand strikes vs a retreating fighter
    retreatKick*: float     ## x mult on kicks vs a retreating fighter
    advanceHit*: float      ## x mult on hit chance vs a fighter stepping in
    jamKick*: float         ## x mult on kick hit chance and force vs a fighter stepping into it
    circleHit*: float       ## x mult on hit chance vs a circling fighter
    shootDuck*: float       ## x mult on hand strikes vs a fighter changing levels to shoot
    kneeVsShoot*: float     ## x mult on knees/kicks vs a fighter shooting in
    sprawlExposed*: float   ## x mult on hit chance vs a fighter who sprawled at nothing

    # ---- condition --------------------------------------------------------
    offAtk*: float          ## x mult on an off-balance fighter's own success chances
    offDef*: float          ## x mult on strikes landing on an off-balance fighter
    offGrapple*: float      ## x mult on takedowns/throws/grabs vs an off-balance fighter
    stunAtk*: float         ## x mult on a stunned fighter's success chances
    stunDef*: float         ## x mult on strikes landing on a stunned fighter
    stunGrapple*: float     ## x mult on grappling vs a stunned fighter
    damagePenalty*: float   ## own success x (1 - this * damage level)
    chinPenalty*: float     ## incoming damage chances x (1 + this * damage level)
    legsMove*: float        ## x mult on footwork success (circle, flee, catch) with hurt legs

    # ---- angles -------------------------------------------------------------
    angleAtk*: float        ## x mult on success when attacking from the outside angle
    angleDef*: float        ## x mult on success when attacking a fighter who holds the angle
    angleKeep*: float       ## P(an angle survives a beat in which nobody renews it)
    circleBase*: float      ## P(circling takes the angle)
    circleVsCircle*: float  ## x mult when both fighters circle

    # ---- escaping (self-defense) ---------------------------------------------
    fleeBase*: float        ## P(getting away from kicking range vs an attacker who does not chase)
    fleeVsChase*: float     ## x mult when the attacker steps after you
    fleeOver*: float        ## P(getting away while the attacker is down)
    fleeAttackerHurt*: float ## x mult on fleeing when the attacker is stunned/off-balance
    fleeAttackerLegs*: float ## x mult on fleeing when the attacker's legs are hurt
    fleeCaughtBehind*: float ## P(attacker ends up behind you | a flight failed)

    # ---- takedowns, grabs, clinch ---------------------------------------------
    shootLong*: float       ## takedown/tackle success from kicking range vs a passive opponent
    shootMid*: float        ## ... from punching range
    shootClose*: float      ## ... from close range
    sprawlStop*: float      ## x mult on takedown success vs a sprawl
    sprawlBack*: float      ## P(sprawler takes the back | sprawl stuffed the shot)
    guillotine*: float      ## P(sprawler finishes with a front choke | sprawl stuffed the shot)
    shootVsCommit*: float   ## x mult on takedowns timed under a haymaker/round kick
    shootVsRetreat*: float  ## x mult on takedowns vs a retreating fighter
    shootVsAdvance*: float  ## x mult on takedowns vs a fighter stepping in
    shootBoth*: float       ## x mult when both fighters shoot
    grabClose*: float       ## P(grab/tie-up) from close range
    grabMid*: float         ## P(grab/tie-up) from punching range
    grabVsRetreat*: float   ## x mult on grabs vs a retreating fighter
    pummelGain*: float      ## P(win the dominant grip from an even clinch)
    pummelRecover*: float   ## P(get back to even from an inferior grip)
    domStrike*: float       ## x mult on clinch strikes from the dominant grip
    subStrike*: float       ## x mult on clinch strikes from the inferior grip
    throwDom*: float        ## throw/trip success from the dominant grip
    throwEven*: float       ## ... from an even clinch
    throwSub*: float        ## ... from the inferior grip
    throwVsKnee*: float     ## x mult on throws vs a fighter standing on one leg to knee
    throwVsCover*: float    ## x mult on throws vs a fighter posturing up
    breakBase*: float       ## P(breaking away vs a fighter who wants to hold)
    breakVsDom*: float      ## x mult on breaking away from a dominant grip
    chokeClinch*: float     ## P(front choke/headlock finish from the dominant grip)
    chokeBehind*: float     ## P(rear choke finish while behind)
    chokeVsCover*: float    ## x mult on chokes vs a fighter protecting the neck
    throwBehind*: float     ## P(dragging/slamming down a fighter held from behind)
    turnBase*: float        ## P(turning to face a fighter holding you from behind)
    turnVsHold*: float      ## x mult on turning vs a fighter concentrating on control

    # ---- one fighter down ------------------------------------------------------
    followBase*: float      ## P(following a downed fighter into top position)
    followVsGetUp*: float   ## ... when they are getting up at that moment
    getUpVsStrike*: float   ## P(getting up while the standing fighter attacks)

    # ---- ground ----------------------------------------------------------------
    poundGuard*: float      ## ground strike land chance from top in guard
    poundMount*: float      ## ... from mount
    poundBack*: float       ## ... from back control
    passGuard*: float       ## P(pass guard to mount)
    passMount*: float       ## P(take the back from mount)
    subMount*: float        ## P(submission from mount)
    subBack*: float         ## P(choke from back control)
    guardSub*: float        ## P(submission from bottom guard)
    sweep*: float           ## P(sweep from guard to top)
    escapeMount*: float     ## P(escape mount to guard)
    escapeBack*: float      ## P(escape back control to guard)
    escapeGuard*: float     ## P(stand up from bottom guard)
    disengage*: float       ## P(top fighter gets up and away)
    holdControl*: float     ## x mult on bottom escapes/sweeps/subs vs a top fighter holding
    coverGround*: float     ## x mult on strikes and submissions vs a bottom fighter covering
    poundExposes*: float    ## x mult on sweeps/guard subs vs a top fighter throwing strikes
    passExposes*: float     ## x mult on sweeps/guard subs vs a top fighter passing
    subFailEscape*: float   ## P(bottom fighter improves position | top submission failed)
    guardSubFailPass*: float ## P(top passes to mount | guard submission failed)
    standUpBack*: float     ## P(top takes the back | a stand-up from guard failed)
    mountTurnBack*: float   ## P(top takes the back | a mount escape failed)

proc defaultParams*(): Params =
  result = Params(
    stopChance: 0.04, maxProb: 0.95,
    harmPerLevel: 0.2, harmDown: 0.15, harmPinned: 0.15,
    decisionWeight: 0.15, decisionTop: 0.06, decisionDominant: 0.12, refStandUp: 0.3,
    forceScale: 0.35, effBase: 0.2, effSlope: 0.2, precisionScale: 1.0,
    glanceForce: 0.3, hitScale: 1.0, damageScale: 1.0, stunScale: 1.0,
    legsScale: 1.0, grappleScale: 1.0, submissionScale: 1.0,
    unloadedPower: 0.55, offPower: 0.6, legsPower: 0.5, advanceForce: 1.3,
    interceptHit: 1.3, knockdown: 0.5, stagger: 0.35, pushOff: 0.5,
    interruptLight: 0.25, interruptHeavy: 0.5,
    coverForce: 0.6, counterHit: 0.45, slipAngle: 0.5, parryOff: 0.4,
    feintDraw: 0.6, retreatHit: 0.5, retreatKick: 0.8, advanceHit: 1.2,
    jamKick: 0.6, circleHit: 0.85, shootDuck: 0.6, kneeVsShoot: 1.4,
    sprawlExposed: 1.15,
    offAtk: 0.7, offDef: 1.3, offGrapple: 1.5, stunAtk: 0.4, stunDef: 1.5,
    stunGrapple: 1.8, damagePenalty: 0.08, chinPenalty: 0.2, legsMove: 0.4,
    angleAtk: 1.3, angleDef: 0.75, angleKeep: 0.5, circleBase: 0.45,
    circleVsCircle: 0.5,
    fleeBase: 0.6, fleeVsChase: 0.5, fleeOver: 0.85, fleeAttackerHurt: 1.6,
    fleeAttackerLegs: 1.8, fleeCaughtBehind: 0.3,
    shootLong: 0.15, shootMid: 0.30, shootClose: 0.40, sprawlStop: 0.25,
    sprawlBack: 0.25, guillotine: 0.12, shootVsCommit: 1.4, shootVsRetreat: 0.5,
    shootVsAdvance: 1.2, shootBoth: 0.5, grabClose: 0.55, grabMid: 0.3,
    grabVsRetreat: 0.3, pummelGain: 0.35, pummelRecover: 0.45, domStrike: 1.5,
    subStrike: 0.5, throwDom: 0.40, throwEven: 0.22, throwSub: 0.08,
    throwVsKnee: 1.4, throwVsCover: 0.7, breakBase: 0.6, breakVsDom: 0.6,
    chokeClinch: 0.15, chokeBehind: 0.25, chokeVsCover: 0.4, throwBehind: 0.35,
    turnBase: 0.35, turnVsHold: 0.6,
    followBase: 0.85, followVsGetUp: 0.45, getUpVsStrike: 0.5,
    poundGuard: 0.30, poundMount: 0.55, poundBack: 0.45,
    passGuard: 0.22, passMount: 0.15, subMount: 0.18, subBack: 0.30,
    guardSub: 0.07, sweep: 0.15, escapeMount: 0.22, escapeBack: 0.20,
    escapeGuard: 0.25, disengage: 0.7, holdControl: 0.6, coverGround: 0.6,
    poundExposes: 1.3, passExposes: 1.3, subFailEscape: 0.35,
    guardSubFailPass: 0.25, standUpBack: 0.15, mountTurnBack: 0.2)

  # Incoming-strike multipliers by how the strike generates force.
  #                       none  linear rotational whip  push  drop
  result.coverVs     = [mkNone: 1.0, mkLinear: 0.6, mkRotational: 0.65, mkWhip: 0.8, mkPush: 1.0, mkDrop: 0.8]
  result.slipVs      = [mkNone: 1.0, mkLinear: 0.4, mkRotational: 0.35, mkWhip: 0.6, mkPush: 0.6, mkDrop: 1.0]
  result.parryVs     = [mkNone: 1.0, mkLinear: 0.35, mkRotational: 0.5, mkWhip: 0.7, mkPush: 0.3, mkDrop: 1.0]
  result.counterVs   = [mkNone: 1.0, mkLinear: 0.7, mkRotational: 0.6, mkWhip: 0.8, mkPush: 0.8, mkDrop: 1.0]

  # Land chance vs a passive opponent, by position.
  for (a, l, m, c) in [(aFingerJab, 0.0, 0.35, 0.45), (aJab, 0.0, 0.55, 0.45),
                       (aCross, 0.0, 0.45, 0.40), (aHook, 0.0, 0.25, 0.45),
                       (aHaymaker, 0.0, 0.40, 0.45), (aBodyHook, 0.0, 0.0, 0.45),
                       (aElbow, 0.0, 0.0, 0.40), (aGroinKick, 0.35, 0.40, 0.0),
                       (aObliqueKick, 0.45, 0.45, 0.0), (aLowKick, 0.45, 0.45, 0.0),
                       (aRoundKick, 0.40, 0.45, 0.0), (aTeep, 0.50, 0.50, 0.0),
                       (aKnee, 0.0, 0.0, 0.35), (aHeadbutt, 0.0, 0.0, 0.30),
                       (aPush, 0.0, 0.50, 0.70)]:
    result.hitLong[a] = l
    result.hitMid[a] = m
    result.hitClose[a] = c
  for (a, h) in [(aKnee, 0.40), (aElbow, 0.40), (aHeadbutt, 0.40), (aStomp, 0.45),
                 (aFingerJab, 0.45)]:
    result.hitClinch[a] = h
  for (a, h) in [(aElbow, 0.45), (aHeadbutt, 0.35), (aStomp, 0.50), (aGroinKick, 0.35)]:
    result.hitBehind[a] = h
  for (a, h) in [(aStomp, 0.55), (aUpkick, 0.30)]:
    result.hitOver[a] = h

  # Force at full power (N), following the biomechanics documents where they
  # give a number: palm strike 800, shovel hook 600, whip kick 900, oblique
  # kick 400, stop kick 200-400, relaxed whip strike 450.
  for (a, f) in [(aCounter, 450.0), (aFingerJab, 100.0), (aJab, 300.0),
                 (aCross, 800.0), (aHook, 600.0), (aHaymaker, 900.0),
                 (aBodyHook, 600.0), (aElbow, 700.0), (aGroinKick, 500.0),
                 (aObliqueKick, 400.0), (aLowKick, 900.0), (aRoundKick, 900.0),
                 (aTeep, 400.0), (aKnee, 800.0), (aHeadbutt, 500.0),
                 (aStomp, 700.0), (aPush, 300.0), (aUpkick, 500.0),
                 (aPound, 500.0), (aThrow, 600.0)]:
    result.force[a] = f

  for (a, c) in [(aHaymaker, 0.6), (aRoundKick, 0.45), (aLowKick, 0.3),
                 (aCross, 0.1), (aHook, 0.2), (aBodyHook, 0.2), (aKnee, 0.1),
                 (aGroinKick, 0.15), (aTeep, 0.1), (aObliqueKick, 0.05),
                 (aElbow, 0.1), (aStomp, 0.15), (aShoot, 0.4), (aThrow, 0.4),
                 (aGrab, 0.15), (aPush, 0.1), (aCounter, 0.05)]:
    result.commit[a] = c

# ---------------------------------------------------------------------------
# Effective parameters (global knobs folded in)
# ---------------------------------------------------------------------------

proc effective*(p: Params): Params =
  ## Fold the grappling and submission knobs into the individual chances.
  result = p
  for x in [addr result.subMount, addr result.subBack, addr result.guardSub,
            addr result.guillotine, addr result.chokeClinch, addr result.chokeBehind]:
    x[] = x[] * p.submissionScale
  result.submissionScale = 1.0
  for x in [addr result.shootLong, addr result.shootMid, addr result.shootClose,
            addr result.throwDom, addr result.throwEven, addr result.throwSub,
            addr result.grabClose, addr result.grabMid, addr result.passGuard,
            addr result.passMount, addr result.throwBehind]:
    x[] = x[] * p.grappleScale
  result.grappleScale = 1.0

# ---------------------------------------------------------------------------
# Named access, for sensitivity analysis, calibration and JSON files
# ---------------------------------------------------------------------------

proc paramNames*(p: Params, includeZero = false): seq[string] =
  ## Scalars ("knockdown"), table entries ("hitMid.Jab", "coverVs.Linear").
  ## Zero table entries mean "not applicable" and are skipped unless asked for.
  for k, v in p.fieldPairs:
    when v is float:
      result.add k
    elif v is ActionTable:
      for a in Action:
        if includeZero or v[a] != 0.0:
          result.add k & "." & a.name
    elif v is MechTable:
      for m in Mechanics:
        if m != mkNone: result.add k & "." & ($m)[2 .. ^1]

proc tableNames*(): seq[string] =
  var p: Params
  for k, v in p.fieldPairs:
    when v is ActionTable or v is MechTable:
      result.add k

proc parseMech(s: string): Mechanics =
  for m in Mechanics:
    if cmpIgnoreCase(($m)[2 .. ^1], s) == 0: return m
  raise newException(ValueError, "unknown mechanics: " & s)

proc entryOf[T](parts: seq[string], parse: proc(s: string): T): T =
  try: parse(parts[1])
  except ValueError: raise newException(KeyError, "unknown parameter: " & parts.join("."))

proc getParam*(p: Params, name: string): float =
  let parts = name.split('.')
  for k, v in p.fieldPairs:
    when v is float:
      if parts.len == 1 and k == parts[0]: return v
    elif v is ActionTable:
      if parts.len == 2 and k == parts[0]: return v[entryOf(parts, parseAction)]
    elif v is MechTable:
      if parts.len == 2 and k == parts[0]: return v[entryOf(parts, parseMech)]
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
        v[entryOf(parts, parseAction)] = value
        return
    elif v is MechTable:
      if parts.len == 2 and k == parts[0]:
        v[entryOf(parts, parseMech)] = value
        return
  raise newException(KeyError, "unknown parameter: " & name)

proc isProbability*(name: string): bool =
  ## Multipliers, forces and scales may exceed 1; probabilities are kept in
  ## [0, 1] when perturbed.
  let base = name.split('.')[0]
  if base in ["force", "coverVs", "slipVs", "parryVs", "counterVs"]: return false
  const mults = ["slipKick", "advanceHit", "advanceForce", "interceptHit",
                 "sprawlExposed", "angleAtk", "offDef", "offGrapple", "stunDef",
                 "stunGrapple", "shootVsCommit", "shootVsAdvance", "domStrike",
                 "throwVsKnee", "kneeVsShoot", "poundExposes", "passExposes",
                 "fleeAttackerHurt", "fleeAttackerLegs", "forceScale", "hitScale",
                 "precisionScale",
                 "damageScale", "stunScale", "legsScale", "grappleScale",
                 "submissionScale"]
  base notin mults

proc perturbed*(p: Params, name: string, factor: float): Params =
  result = p
  var v = p.getParam(name) * factor
  if isProbability(name): v = clamp(v, 0.0, 1.0)
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
    elif v is MechTable:
      var t = newJObject()
      for m in Mechanics:
        if m != mkNone: t[($m)[2 .. ^1]] = %v[m]
      result[k] = t

proc applyJson*(p: var Params, j: JsonNode) =
  ## Override any subset of parameters. Unknown keys are an error so typos
  ## do not silently fall back to defaults.
  for key, val in j.pairs:
    if val.kind == JObject:
      if key notin tableNames(): raise newException(KeyError, "unknown parameter table: " & key)
      for an, av in val.pairs:
        p.setParam(key & "." & an, av.getFloat)
    elif val.kind in {JFloat, JInt}:
      p.setParam(key, val.getFloat)
    elif key in ["notes", "sources", "comment"]:
      discard
    else:
      raise newException(ValueError, "parameter " & key & " must be a number")

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

# ---------------------------------------------------------------------------
# Parameter families: related assumptions perturbed together in robustness
# checks ("what if all our defence numbers are 25% too optimistic?")
# ---------------------------------------------------------------------------

const paramFamilies* = [
  ("framing", @["stopChance", "harmPerLevel", "harmDown", "harmPinned"]),
  ("force & targets", @["forceScale", "force.*", "effBase", "effSlope", "damageScale",
                        "stunScale", "legsScale", "precisionScale", "glanceForce"]),
  ("strike accuracy", @["hitScale", "hitLong.*", "hitMid.*", "hitClose.*", "hitClinch.*",
                        "hitBehind.*", "hitOver.*"]),
  ("commitment & balance", @["commit.*", "offAtk", "offDef", "offGrapple", "offPower",
                             "stagger", "pushOff", "knockdown"]),
  ("rotation & timing", @["unloadedPower", "interruptLight", "interruptHeavy",
                          "advanceForce", "interceptHit"]),
  ("defence", @["coverVs.*", "coverForce", "slipVs.*", "parryVs.*", "counterVs.*",
                "counterHit", "slipAngle", "parryOff", "feintDraw", "retreatHit",
                "retreatKick", "advanceHit", "jamKick", "circleHit", "shootDuck",
                "kneeVsShoot", "sprawlExposed"]),
  ("stun & injury", @["stunAtk", "stunDef", "stunGrapple", "damagePenalty",
                      "chinPenalty", "legsMove", "legsPower"]),
  ("angles", @["angleAtk", "angleDef", "angleKeep", "circleBase", "circleVsCircle"]),
  ("escaping", @["fleeBase", "fleeVsChase", "fleeOver", "fleeAttackerHurt",
                 "fleeAttackerLegs", "fleeCaughtBehind"]),
  ("takedowns", @["shootLong", "shootMid", "shootClose", "sprawlStop", "sprawlBack",
                  "guillotine", "shootVsCommit", "shootVsRetreat", "shootVsAdvance",
                  "shootBoth", "grappleScale"]),
  ("clinch & holds", @["grabClose", "grabMid", "grabVsRetreat", "pummelGain",
                       "pummelRecover", "domStrike", "subStrike", "throwDom",
                       "throwEven", "throwSub", "throwVsKnee", "throwVsCover",
                       "breakBase", "breakVsDom", "chokeClinch", "chokeBehind",
                       "chokeVsCover", "throwBehind", "turnBase", "turnVsHold",
                       "submissionScale"]),
  ("down & ground", @["followBase", "followVsGetUp", "getUpVsStrike", "poundGuard",
                      "poundMount", "poundBack", "passGuard", "passMount", "subMount",
                      "subBack", "guardSub", "sweep", "escapeMount", "escapeBack",
                      "escapeGuard", "disengage", "holdControl", "coverGround",
                      "poundExposes", "passExposes", "subFailEscape",
                      "guardSubFailPass", "standUpBack", "mountTurnBack"]),
  ("sport only", @["decisionWeight", "decisionTop", "decisionDominant", "refStandUp",
                   "maxProb"]),
]

proc expandFamily*(p: Params, members: seq[string]): seq[string] =
  ## "force.*" -> every non-zero entry of that table.
  for m in members:
    if m.endsWith(".*"):
      let t = m[0 .. ^3]
      for full in p.paramNames:
        if full.startsWith(t & "."): result.add full
    else:
      result.add m

proc perturbFamily*(p: Params, members: seq[string], factor: float): Params =
  result = p
  for name in expandFamily(p, members):
    result = result.perturbed(name, factor)
