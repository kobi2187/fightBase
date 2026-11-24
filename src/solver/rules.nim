## Rules of the model: which actions are legal in a position, and how one
## pair of simultaneous actions resolves into an explicit probability
## distribution over next positions.
##
## Resolution of a beat
## 1. Each fighter's action produces a primary event. A strike misses, or
##    lands and has an effect on its target zone (damage, a stun, hurt legs)
##    computed by `body.nim` from the strike's force and the zone's
##    threshold. Grappling actions succeed or fail.
## 2. Initiative: the action with the higher speed resolves first and, if it
##    succeeds, cuts the slower action's chance. A rotational strike thrown
##    from the unloaded side is one step slower (it needs a wind-up).
##    Equal speeds resolve independently (a trade).
## 3. Secondary coin flips: knockdowns, ending off-balance, taking an angle,
##    being caught while running.
## 4. The new position follows a fixed priority (finish > escape >
##    knockdown > takedown > grab > footwork). Damage is added (reaching the
##    last level incapacitates), stuns and hurt legs are recorded, and each
##    fighter's hips are re-loaded according to the strike they threw.
##
## The rules never refer to "A" or "B" directly, only to a fighter and their
## opponent; the only asymmetry is who may flee in self-defense mode. The test
## suite checks the mirror symmetry in sport mode on every state and pair.

import core, params, body

type
  EventTag* = enum
    ## What happened during a beat, for statistics and the playbook.
    etLanded       ## a strike landed
    etDamaged      ## ... and dealt at least one damage level
    etStunned      ## ... and stunned the opponent
    etLegs         ## ... and hurt the opponent's legs
    etKnockdown    ## knocked the opponent down
    etTakedown     ## a takedown/tackle succeeded
    etStuffed      ## sprawled on and lost the back
    etThrow        ## a throw/trip/slam succeeded
    etGrab         ## got hold of the opponent
    etAngle        ## took the outside angle
    etDeflect      ## made a strike miss by slipping or parrying
    etCountered    ## landed a counter on an attacking opponent
    etFeinted      ## drew a reaction with a feint
    etEscaped      ## got away
    etTurned       ## turned out of a hold from behind
    etSubmission   ## finished with a choke/submission
    etSweep        ## swept from bottom
    etPass         ## improved top position
    etEscape       ## escaped a bottom position

  Outcome* = object
    p*: float
    target*: int32   ## >= 0: `encode(State)`; < 0: `terminalCode`
    tags*: array[Who, set[EventTag]]

  EvKind = enum
    evNone, evMiss, evLand, evSuccess, evFail, evStuffed, evChoked

  Ev = object
    kind: EvKind
    dmg: int
    stun, legs: bool
    p: float

  Raw = object
    ## A resolved beat before damage and terminal checks.
    p: float
    pos: Pos
    dmgTaken: array[Who, int]
    stun, legs, off: array[Who, bool]
    term: int                 ## -1, or ord(Terminal)
    tags: array[Who, set[EventTag]]

  Ctx* = object
    s*: State
    act*: array[Who, Action]
    d*: Dims
    mode*: Mode

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

proc clampP(p: Params, x: float): float {.inline.} = clamp(x, 0.0, p.maxProb)

proc hitAt*(p: Params, a: Action, r: Range): float =
  p.hitScale * (case r
    of rLong: p.hitLong[a]
    of rMid: p.hitMid[a]
    of rClose: p.hitClose[a])

proc skill(p: Params, c: Ctx, w: Who): float =
  ## Multiplier on a fighter's own chance to make anything work.
  let f = c.s.f[w]
  result = max(0.0, 1.0 - p.damagePenalty * f.dmg.float)
  case f.cond
  of cOff: result *= p.offAtk
  of cStunned: result *= p.stunAtk
  of cOk: discard

proc exposure(p: Params, c: Ctx, w: Who): float =
  ## Multiplier on strikes landing on this fighter.
  case c.s.f[w].cond
  of cOff: p.offDef
  of cStunned: p.stunDef
  of cOk: 1.0

proc grappleVuln(p: Params, c: Ctx, w: Who): float =
  case c.s.f[w].cond
  of cOff: p.offGrapple
  of cStunned: p.stunGrapple
  of cOk: 1.0

proc moveMult(p: Params, c: Ctx, w: Who): float =
  if c.s.f[w].legs: p.legsMove else: 1.0

proc chin(p: Params, c: Ctx, w: Who): float =
  1.0 + p.chinPenalty * c.s.f[w].dmg.float

proc angleMult(p: Params, c: Ctx, w: Who): float =
  if c.s.pos in StandingPositions:
    if c.s.pos.hasAngle(w): return p.angleAtk
    if c.s.pos.hasAngle(w.other): return p.angleDef
  1.0

proc loaded*(f: Fighter, a: Action): bool =
  ## Is the side this rotational technique uses wound up?
  let t = tech[a]
  if t.mech != mkRotational: return true
  case t.side
  of sdRear: f.coil == coRear
  of sdLead: f.coil == coLead
  of sdNone: true

proc effSpeed*(p: Params, c: Ctx, w: Who): int =
  ## A rotational strike from the unloaded side needs a wind-up: one step
  ## slower (unless the model variant ignores hip loading).
  let a = c.act[w]
  result = tech[a].speed
  if p.unloadedPower < 0.999 and not loaded(c.s.f[w], a): result = max(0, result - 1)

proc nextCoil*(f: Fighter, a: Action): Coil =
  ## Throwing a rotational strike unwinds its side and loads the other.
  let t = tech[a]
  if t.mech != mkRotational: return f.coil
  case t.side
  of sdRear: coLead
  of sdLead: coRear
  of sdNone: f.coil

proc forceOf(p: Params, c: Ctx, w: Who, a: Action): float =
  let f = c.s.f[w]
  result = p.force[a] * max(0.0, 1.0 - p.damagePenalty * f.dmg.float)
  if not loaded(f, a): result *= p.unloadedPower
  case f.cond
  of cOff: result *= p.offPower
  of cStunned: result *= p.stunAtk
  of cOk: discard
  if a in Kicks and f.legs: result *= p.legsPower

proc targetZone(c: Ctx, w: Who, a: Action): VulnerabilityZone =
  ## A stunned (bent-over) or downed opponent exposes a different target.
  let o = w.other
  if c.s.f[o].cond == cStunned or c.s.pos.isDown(o): tech[a].downZone
  else: tech[a].zone

proc combineOff(ps: openArray[float]): float =
  var stay = 1.0
  for x in ps: stay *= (1.0 - clamp(x, 0.0, 1.0))
  1.0 - stay

iterator coin(p: float): (bool, float) =
  ## Both sides of a biased coin, skipping impossible ones.
  if p > 0.0: yield (true, min(p, 1.0))
  if p < 1.0: yield (false, 1.0 - max(p, 0.0))

proc impactEvents(p: Params, c: Ctx, w: Who, z: VulnerabilityZone, force: float,
                  stunMult, legsMult: float): array[3, array[2, array[2, float]]] =
  ## What one landed impact of `force` on zone `z` does: solid with the
  ## zone's precision, otherwise glancing. Returns P[dmg][stun][legs].
  let o = w.other
  var prec = zonePrecision[z] * p.precisionScale
  if c.s.f[o].cond == cStunned or c.s.pos.isDown(o): prec *= 1.3   # a still target
  prec = clamp(prec, 0.0, 1.0)
  let needed = zoneProfiles[z].force
  for (q, f) in [(prec, force), (1.0 - prec, force * p.glanceForce)]:
    if q <= 0.0: continue
    let e = effectStrength(f, needed, p.effBase, p.effSlope)
    for eff in strikeEffects(z, e, p.damageScale * chin(p, c, o), stunMult, legsMult):
      result[eff.dmg][ord(eff.stun)][ord(eff.legs)] += q * eff.p

proc strikeEvents(p: Params, c: Ctx, w: Who, a: Action, landP, forceMult: float): seq[Ev] =
  let pl = clampP(p, landP)
  if pl < 1.0: result.add Ev(kind: evMiss, p: 1.0 - pl)
  if pl <= 0.0: return
  let z = targetZone(c, w, a)
  let force = forceOf(p, c, w, a) * forceMult * p.forceScale
  let dist = impactEvents(p, c, w, z, force, p.stunScale, p.legsScale)
  for dmg in 0 .. 2:
    for stun in 0 .. 1:
      for legs in 0 .. 1:
        let q = dist[dmg][stun][legs]
        if q > 1e-15:
          result.add Ev(kind: evLand, dmg: dmg, stun: stun == 1, legs: legs == 1, p: pl * q)

proc binaryEvents(p: Params, success: float): seq[Ev] =
  let ps = clampP(p, success)
  if ps > 0.0: result.add Ev(kind: evSuccess, p: ps)
  if ps < 1.0: result.add Ev(kind: evFail, p: 1.0 - ps)

proc succeeded(e: Ev): bool {.inline.} = e.kind in {evLand, evSuccess}

proc interruptFactor(p: Params, faster: Action): float =
  1.0 - (if tech[faster].mech in {mkLinear, mkWhip, mkPush}: p.interruptLight
         else: p.interruptHeavy)

template forOrdered(c: Ctx, p: Params, dist: untyped, body: untyped) =
  ## Enumerate the joint primary events of both fighters with initiative:
  ## the faster action resolves first and, on success, disrupts the slower.
  ## Inside `body`: `ev: array[Who, Ev]` and `prob: float`.
  let sa = effSpeed(p, c, wA)
  let sb = effSpeed(p, c, wB)
  if sa == sb:
    for ea in dist(p, c, wA, 1.0):
      for eb in dist(p, c, wB, 1.0):
        var ev {.inject.}: array[Who, Ev]
        ev[wA] = ea
        ev[wB] = eb
        let prob {.inject.} = ea.p * eb.p
        body
  else:
    let first = if sa > sb: wA else: wB
    let second = first.other
    for e1 in dist(p, c, first, 1.0):
      let k = if e1.succeeded: interruptFactor(p, c.act[first]) else: 1.0
      for e2 in dist(p, c, second, k):
        var ev {.inject.}: array[Who, Ev]
        ev[first] = e1
        ev[second] = e2
        let prob {.inject.} = e1.p * e2.p
        body

proc recordLand(p: Params, w: Who, e: Ev, raw: var Raw, offSrc: var array[Who, seq[float]],
                kdRisk: var array[Who, bool]) =
  ## Book-keeping shared by every position: what a landed strike did.
  let o = w.other
  raw.tags[w].incl etLanded
  raw.dmgTaken[o] += e.dmg
  if e.dmg > 0:
    raw.tags[w].incl etDamaged
    offSrc[o].add p.stagger
  if e.dmg >= 2: kdRisk[o] = true
  if e.stun:
    raw.stun[o] = true
    raw.tags[w].incl etStunned
  if e.legs:
    raw.legs[o] = true
    raw.tags[w].incl etLegs

# ---------------------------------------------------------------------------
# Legal actions
# ---------------------------------------------------------------------------

proc legalActions*(p: Params, s: State, w: Who, arsenal: set[Action], d: Dims,
                   mode = mSelfDefense): seq[Action] =
  let pos = s.pos
  var cand: set[Action]
  if pos in StandingPositions:
    let r = pos.rangeOf
    cand = {aRetreat, aCover, aCounter, aFeint, aShoot, aSprawl}
    if r != rClose: cand.incl aAdvance
    if r != rLong: cand = cand + {aCircle, aSlip, aParry, aGrab}
    if r == rLong: cand.incl aFlee
    for a in StandingStrikes + {aHeadbutt, aPush}:
      if hitAt(p, a, r) > 0.0: cand.incl a
  elif pos in ClinchPositions:
    cand = {aPummel, aThrow, aBreak, aCover}
    for a in Action:
      if p.hitClinch[a] > 0.0: cand.incl a
    if pos.clinchLevel(w) > 0: cand.incl aChoke
  elif pos in BehindPositions:
    if pos.advantaged == ord(w):
      cand = {aChoke, aThrow, aHold, aBreak}
    else:
      cand = {aTurn, aCover}
      for a in Action:
        if p.hitBehind[a] > 0.0: cand.incl a
  elif pos in OverPositions:
    if pos.isDown(w): cand = {aGetUp, aUpkick, aCover}
    else: cand = {aFollow, aBackOff, aStomp, aFlee}
  else:
    let k = pos.groundKind
    if pos.isTop(w):
      cand = {aPound, aHold, aDisengage}
      if k in {gGuard, gMount}: cand.incl aPass
      if k in {gMount, gBack}: cand.incl aChoke
    else:
      cand = {aEscape, aCover}
      if k == gGuard: cand = cand + {aSweep, aGuardSub}
  cand = cand * (arsenal + CoreActions)
  # Only the defender runs, and only in self-defense.
  if mode != mSelfDefense or w != wA: cand.excl aFlee
  let f = s.f[w]
  if f.cond != cOk: cand = cand - HeavyActions
  if f.legs: cand = cand - {aRoundKick, aLowKick}
  if f.cond == cStunned:
    let still = cand * StunnedActions
    if still.card > 0: cand = still
    elif (cand * CoreActions).card > 0: cand = cand * CoreActions
  for a in Action:
    if a in cand: result.add a

# ---------------------------------------------------------------------------
# Standing
# ---------------------------------------------------------------------------

proc standingDist(p: Params, c: Ctx, w: Who, interrupt: float): seq[Ev] =
  let a = c.act[w]
  let o = w.other
  let oa = c.act[o]
  let r = c.s.pos.rangeOf
  if a in StandingStrikes + {aHeadbutt, aPush}:
    let mech = tech[a].mech
    var m = skill(p, c, w) * exposure(p, c, o) * angleMult(p, c, w) * interrupt
    var fm = 1.0
    let low = targetZone(c, w, a) in LegZones + {vzGroin}
    case oa
    of aCover:
      if not low:
        m *= p.coverVs[mech]
        fm *= p.coverForce
    of aSlip:
      if a notin Kicks: m *= p.slipVs[mech]
    of aParry:
      m *= (if a in Kicks: 0.5 * (1.0 + p.parryVs[mech]) else: p.parryVs[mech])
    of aCounter:
      m *= p.counterVs[mech]
    of aRetreat, aFlee:
      m *= (if a in Kicks: p.retreatKick else: p.retreatHit)
    of aAdvance:
      if a in {aLowKick, aRoundKick, aGroinKick}:
        m *= p.jamKick
        fm *= p.jamKick
      else:
        m *= p.advanceHit
        fm *= p.advanceForce
    of aCircle: m *= p.circleHit
    of aShoot:
      if a in Punches: m *= p.shootDuck
      elif a == aKnee: m *= p.kneeVsShoot
    of aSprawl: m *= p.sprawlExposed
    else: discard
    if oa in Committing and mech in {mkLinear, mkWhip, mkPush}:
      m *= p.interceptHit
    return strikeEvents(p, c, w, a, hitAt(p, a, r) * m, fm)
  case a
  of aShoot:
    var m = skill(p, c, w) * angleMult(p, c, w) * grappleVuln(p, c, o) * interrupt
    case oa
    of aSprawl: m *= p.sprawlStop
    of aRetreat, aFlee: m *= p.shootVsRetreat
    of aAdvance: m *= p.shootVsAdvance
    of aHaymaker, aRoundKick, aLowKick: m *= p.shootVsCommit
    of aShoot: m *= p.shootBoth
    else: discard
    let base = case r
      of rLong: p.shootLong
      of rMid: p.shootMid
      of rClose: p.shootClose
    let ps = clampP(p, base * m)
    if ps > 0.0: result.add Ev(kind: evSuccess, p: ps)
    if ps < 1.0:
      let q = 1.0 - ps
      if oa == aSprawl:
        let choke = clamp(p.guillotine, 0.0, 1.0)
        let back = (1.0 - choke) * p.sprawlBack
        if choke > 0.0: result.add Ev(kind: evChoked, p: q * choke)
        if back > 0.0: result.add Ev(kind: evStuffed, p: q * back)
        if 1.0 - choke - back > 0.0: result.add Ev(kind: evFail, p: q * (1.0 - choke - back))
      else:
        result.add Ev(kind: evFail, p: q)
  of aGrab:
    if oa == aGrab:
      result.add Ev(kind: evSuccess, p: 1.0)
    else:
      var m = skill(p, c, w) * angleMult(p, c, w) * grappleVuln(p, c, o) * interrupt
      if oa in {aRetreat, aFlee}: m *= p.grabVsRetreat
      result = binaryEvents(p, (if r == rClose: p.grabClose else: p.grabMid) * m)
  of aCircle:
    var m = skill(p, c, w) * moveMult(p, c, w) * interrupt
    if oa == aCircle: m *= p.circleVsCircle
    result = binaryEvents(p, p.circleBase * m)
  of aCounter:
    if oa in StandingStrikes:
      let land = p.hitScale * p.counterHit * skill(p, c, w) * exposure(p, c, o) *
                 angleMult(p, c, w) * interrupt
      result = strikeEvents(p, c, w, aCounter, land, 1.0)
    else:
      result.add Ev(kind: evNone, p: 1.0)   # nothing to counter
  of aFeint:
    if oa in {aCounter, aParry, aSlip}:
      result = binaryEvents(p, p.feintDraw * skill(p, c, w))
    else:
      result.add Ev(kind: evNone, p: 1.0)
  of aFlee:
    var m = moveMult(p, c, w) * interrupt
    if c.s.f[o].cond != cOk: m *= p.fleeAttackerHurt
    if c.s.f[o].legs: m *= p.fleeAttackerLegs
    if oa in {aAdvance, aShoot}: m *= p.fleeVsChase
    result = binaryEvents(p, p.fleeBase * m)
  else:
    result.add Ev(kind: evNone, p: 1.0)

proc resolveStanding(p: Params, c: Ctx, raws: var seq[Raw]) =
  let pos = c.s.pos
  let r = pos.rangeOf
  forOrdered(c, p, standingDist):
    var base = Raw(p: prob, term: -1)
    var offSrc: array[Who, seq[float]]
    var kdRisk, takedown, stuffedBy, chokedBy, grabbed, circled, escaped, caught: array[Who, bool]
    var slipChance: array[Who, float]
    var pushed, shotFailed = false
    var intent = 0
    for w in Who:
      let o = w.other
      let a = c.act[w]
      case a
      of aAdvance: dec intent
      of aRetreat: inc intent
      else: discard
      let e = ev[w]
      case e.kind
      of evLand:
        recordLand(p, w, e, base, offSrc, kdRisk)
        if tech[a].mech == mkPush:
          pushed = true
          offSrc[o].add p.pushOff
        if a == aCounter: base.tags[w].incl etCountered
      of evMiss:
        offSrc[w].add p.commit[a]
        if a in StandingStrikes:
          case c.act[o]
          of aSlip:
            if a notin Kicks:
              slipChance[o] = p.slipAngle
              base.tags[o].incl etDeflect
          of aParry:
            offSrc[w].add p.parryOff
            base.tags[o].incl etDeflect
          else: discard
      of evSuccess:
        case a
        of aShoot: takedown[w] = true
        of aGrab: grabbed[w] = true
        of aCircle: circled[w] = true
        of aFlee: escaped[w] = true
        of aFeint:
          offSrc[o].add 1.0
          base.tags[w].incl etFeinted
        else: discard
      of evFail:
        offSrc[w].add p.commit[a]
        if a == aShoot: shotFailed = true
        if a == aFlee: caught[w] = true
      of evStuffed: stuffedBy[o] = true
      of evChoked: chokedBy[o] = true
      of evNone: discard

    let fleer = if caught[wA]: wA elif caught[wB]: wB else: wA
    let caughtChance = if caught[wA] or caught[wB]: p.fleeCaughtBehind else: 0.0
    for (kdA, pkA) in coin(if kdRisk[wA]: p.knockdown else: 0.0):
      for (kdB, pkB) in coin(if kdRisk[wB]: p.knockdown else: 0.0):
        for (offA, poA) in coin(combineOff(offSrc[wA])):
          for (offB, poB) in coin(combineOff(offSrc[wB])):
            for (slipA, psA) in coin(slipChance[wA]):
              for (slipB, psB) in coin(slipChance[wB]):
                for (behind, pc) in coin(caughtChance):
                  let pr = prob * pkA * pkB * poA * poB * psA * psB * pc
                  if pr <= 0.0: continue
                  var o = base
                  o.p = pr
                  o.off = [wA: offA, wB: offB]
                  let kd = [wA: kdA, wB: kdB]
                  # 1. finishes and escapes
                  if chokedBy[wA] or chokedBy[wB]:
                    let winner = if chokedBy[wA]: wA else: wB
                    o.term = ord(if winner == wA: tASub else: tBSub)
                    o.tags[winner].incl etSubmission
                    raws.add o
                    continue
                  if escaped[wA] and not kd[wA]:
                    o.term = ord(tAEscape)
                    o.tags[wA].incl etEscaped
                    raws.add o
                    continue
                  # 2. knockdowns
                  if kd[wA] and kd[wB]:
                    o.pos = pLong
                    o.off = [wA: true, wB: true]
                    raws.add o
                    continue
                  var decided = false
                  for w in Who:
                    if not decided and kd[w.other]:
                      o.pos = overPos(w)
                      o.tags[w].incl etKnockdown
                      decided = true
                  if decided:
                    raws.add o
                    continue
                  # 3. takedowns
                  if takedown[wA] and takedown[wB]:
                    o.pos = pClinch
                    raws.add o
                    continue
                  for w in Who:
                    if not decided and takedown[w]:
                      o.pos = groundPos(w, gGuard)
                      o.tags[w].incl etTakedown
                      decided = true
                    elif not decided and stuffedBy[w]:
                      o.pos = groundPos(w, gBack)
                      o.tags[w.other].incl etStuffed
                      decided = true
                  if decided:
                    raws.add o
                    continue
                  # 4. grabs
                  if grabbed[wA] or grabbed[wB]:
                    var lvl = 0
                    for w in Who:
                      if grabbed[w] and not grabbed[w.other] and
                         (pos.hasAngle(w) or c.s.f[w.other].cond != cOk or o.stun[w.other]):
                        lvl = if w == wA: 1 else: -1
                      if grabbed[w]: o.tags[w].incl etGrab
                    o.pos = clinchPos(lvl)
                    raws.add o
                    continue
                  # 5. a failed flight
                  if caught[wA] or caught[wB]:
                    o.off[fleer] = true
                    o.pos = if behind: behindPos(fleer.other) else: pMid
                    raws.add o
                    continue
                  # 6. footwork
                  var nr = r
                  var lostAngle = false
                  if pushed:
                    nr = Range(min(ord(rLong), ord(r) + 1))
                    lostAngle = true
                  elif shotFailed:
                    nr = rClose
                  elif intent > 0:
                    nr = Range(min(ord(rLong), ord(r) + 1))
                    lostAngle = true
                  elif intent < 0:
                    nr = Range(max(ord(rClose), ord(r) - 1))
                  var angle = -1
                  var renewed = false
                  if nr != rLong:
                    if circled[wA] and not circled[wB]:
                      angle = ord(wA)
                      renewed = true
                    elif circled[wB] and not circled[wA]:
                      angle = ord(wB)
                      renewed = true
                    elif circled[wA] and circled[wB]: angle = -1
                    elif slipA:
                      angle = ord(wA)
                      renewed = true
                    elif slipB:
                      angle = ord(wB)
                      renewed = true
                    else:
                      angle = pos.advantaged
                      if lostAngle: angle = -1
                  if angle >= 0 and not renewed:
                    # an existing angle nobody renewed may fade
                    if p.angleKeep < 1.0:
                      var lose = o
                      lose.p = pr * (1.0 - p.angleKeep)
                      lose.pos = standing(nr, -1)
                      raws.add lose
                    o.p = pr * p.angleKeep
                    if o.p <= 0.0: continue
                  elif angle >= 0:
                    o.tags[Who(angle)].incl etAngle
                  o.pos = standing(nr, angle)
                  raws.add o

# ---------------------------------------------------------------------------
# Clinch
# ---------------------------------------------------------------------------

proc clinchDist(p: Params, c: Ctx, w: Who, interrupt: float): seq[Ev] =
  let a = c.act[w]
  let o = w.other
  let oa = c.act[o]
  let lvl = c.s.pos.clinchLevel(w)
  if p.hitClinch[a] > 0.0:
    let mech = tech[a].mech
    var m = skill(p, c, w) * exposure(p, c, o) * interrupt
    var fm = 1.0
    if lvl > 0: m *= p.domStrike
    elif lvl < 0: m *= p.subStrike
    if oa == aCover and targetZone(c, w, a) notin LegZones + {vzGroin}:
      m *= p.coverVs[mech]
      fm *= p.coverForce
    return strikeEvents(p, c, w, a, p.hitScale * p.hitClinch[a] * m, fm)
  case a
  of aPummel:
    let base = if lvl < 0: p.pummelRecover else: p.pummelGain
    result = binaryEvents(p, base * skill(p, c, w) * interrupt)
  of aThrow:
    var m = skill(p, c, w) * grappleVuln(p, c, o) * interrupt
    if oa == aKnee: m *= p.throwVsKnee
    if oa == aCover: m *= p.throwVsCover
    let base = if lvl > 0: p.throwDom elif lvl < 0: p.throwSub else: p.throwEven
    let ps = clampP(p, base * m)
    if ps < 1.0: result.add Ev(kind: evFail, p: 1.0 - ps)
    if ps > 0.0:
      # the landing itself can hurt
      let dist = impactEvents(p, c, w, vzBackOfHead, p.force[aThrow] * p.forceScale, p.stunScale, 0.0)
      for dmg in 0 .. 2:
        for stun in 0 .. 1:
          let q = dist[dmg][stun][0]
          if q > 1e-15: result.add Ev(kind: evSuccess, dmg: dmg, stun: stun == 1, p: ps * q)
  of aBreak:
    if oa == aBreak:
      result.add Ev(kind: evSuccess, p: 1.0)
    else:
      var m = interrupt
      if lvl < 0: m *= p.breakVsDom
      result = binaryEvents(p, p.breakBase * m)
  of aChoke:
    var m = skill(p, c, w) * grappleVuln(p, c, o) * interrupt
    if oa == aCover: m *= p.chokeVsCover
    result = binaryEvents(p, p.chokeClinch * m)
  else:
    result.add Ev(kind: evNone, p: 1.0)

proc resolveClinch(p: Params, c: Ctx, raws: var seq[Raw]) =
  let lvlA = c.s.pos.clinchLevel(wA)
  forOrdered(c, p, clinchDist):
    var base = Raw(p: prob, term: -1)
    var offSrc: array[Who, seq[float]]
    var kdRisk, threw, broke, pummelled, choked: array[Who, bool]
    for w in Who:
      let o = w.other
      let a = c.act[w]
      let e = ev[w]
      case e.kind
      of evLand: recordLand(p, w, e, base, offSrc, kdRisk)
      of evMiss, evFail: offSrc[w].add p.commit[a]
      of evSuccess:
        case a
        of aThrow:
          threw[w] = true
          base.dmgTaken[o] += e.dmg
          if e.stun: base.stun[o] = true
        of aBreak: broke[w] = true
        of aPummel: pummelled[w] = true
        of aChoke: choked[w] = true
        else: discard
      else: discard
    for (kdA, pkA) in coin(if kdRisk[wA]: p.knockdown else: 0.0):
      for (kdB, pkB) in coin(if kdRisk[wB]: p.knockdown else: 0.0):
        for (offA, poA) in coin(combineOff(offSrc[wA])):
          for (offB, poB) in coin(combineOff(offSrc[wB])):
            let pr = prob * pkA * pkB * poA * poB
            if pr <= 0.0: continue
            var o = base
            o.p = pr
            o.off = [wA: offA, wB: offB]
            if choked[wA] or choked[wB]:
              let w = if choked[wA]: wA else: wB
              o.term = ord(if w == wA: tASub else: tBSub)
              o.tags[w].incl etSubmission
            elif kdA and kdB:
              o.pos = pClose
              o.off = [wA: true, wB: true]
            elif kdB:
              o.pos = overPos(wA)
              o.tags[wA].incl etKnockdown
            elif kdA:
              o.pos = overPos(wB)
              o.tags[wB].incl etKnockdown
            elif threw[wA] and threw[wB]:
              o.pos = pClinch
              o.off = [wA: true, wB: true]
            elif threw[wA] or threw[wB]:
              let w = if threw[wA]: wA else: wB
              o.pos = overPos(w)
              o.tags[w].incl etThrow
            elif broke[wA] or broke[wB]:
              o.pos = pClose
            else:
              o.pos = clinchPos(clamp(lvlA + ord(pummelled[wA]) - ord(pummelled[wB]), -1, 1))
            raws.add o

# ---------------------------------------------------------------------------
# Held from behind (standing)
# ---------------------------------------------------------------------------

proc behindDist(p: Params, c: Ctx, w: Who, interrupt: float): seq[Ev] =
  let a = c.act[w]
  let o = w.other
  let oa = c.act[o]
  let controller = c.s.pos.advantaged == ord(w)
  if not controller and p.hitBehind[a] > 0.0:
    let land = p.hitScale * p.hitBehind[a] * skill(p, c, w) * exposure(p, c, o) * interrupt
    return strikeEvents(p, c, w, a, land, 1.0)
  case a
  of aChoke:
    var m = skill(p, c, w) * grappleVuln(p, c, o) * interrupt
    if oa == aCover: m *= p.chokeVsCover
    result = binaryEvents(p, p.chokeBehind * m)
  of aThrow:
    let ps = clampP(p, p.throwBehind * skill(p, c, w) * grappleVuln(p, c, o) * interrupt)
    if ps < 1.0: result.add Ev(kind: evFail, p: 1.0 - ps)
    if ps > 0.0:
      let dist = impactEvents(p, c, w, vzBackOfHead, p.force[aThrow] * p.forceScale, p.stunScale, 0.0)
      for dmg in 0 .. 2:
        for stun in 0 .. 1:
          let q = dist[dmg][stun][0]
          if q > 1e-15: result.add Ev(kind: evSuccess, dmg: dmg, stun: stun == 1, p: ps * q)
  of aBreak:
    result.add Ev(kind: evSuccess, p: 1.0)
  of aTurn:
    var m = skill(p, c, w) * moveMult(p, c, w) * grappleVuln(p, c, o) * interrupt
    if oa == aHold: m *= p.turnVsHold
    result = binaryEvents(p, p.turnBase * m)
  else:
    result.add Ev(kind: evNone, p: 1.0)

proc resolveBehind(p: Params, c: Ctx, raws: var seq[Raw]) =
  let x = Who(c.s.pos.advantaged)    # behind, in control
  let y = x.other
  forOrdered(c, p, behindDist):
    var base = Raw(p: prob, term: -1)
    var offSrc: array[Who, seq[float]]
    var kdRisk: array[Who, bool]
    var choked, threw, broke, turned = false
    for w in Who:
      let e = ev[w]
      let a = c.act[w]
      case e.kind
      of evLand: recordLand(p, w, e, base, offSrc, kdRisk)
      of evMiss, evFail: offSrc[w].add p.commit[a]
      of evSuccess:
        case a
        of aChoke: choked = true
        of aThrow:
          threw = true
          base.dmgTaken[y] += e.dmg
          if e.stun: base.stun[y] = true
        of aBreak: broke = true
        of aTurn: turned = true
        else: discard
      else: discard
    for (kdX, pkX) in coin(if kdRisk[x]: p.knockdown else: 0.0):
      for (offA, poA) in coin(combineOff(offSrc[wA])):
        for (offB, poB) in coin(combineOff(offSrc[wB])):
          let pr = prob * pkX * poA * poB
          if pr <= 0.0: continue
          var o = base
          o.p = pr
          o.off = [wA: offA, wB: offB]
          if choked:
            o.term = ord(if x == wA: tASub else: tBSub)
            o.tags[x].incl etSubmission
          elif kdX:
            o.pos = overPos(y)
            o.tags[y].incl etKnockdown
          elif threw:
            o.pos = overPos(x)
            o.tags[x].incl etThrow
          elif turned:
            # turning while the controller is hurt wins the better grip
            let hurt = c.s.f[x].cond != cOk or o.stun[x]
            o.pos = if hurt: clinchPos(if y == wA: 1 else: -1) else: pClinch
            o.tags[y].incl etTurned
          elif broke:
            o.pos = pClose
          else:
            o.pos = c.s.pos
          raws.add o

# ---------------------------------------------------------------------------
# One fighter down, the other standing over them
# ---------------------------------------------------------------------------

proc resolveOver(p: Params, c: Ctx, raws: var seq[Raw]) =
  let x = Who(c.s.pos.advantaged)      # standing
  let y = x.other                       # down
  let ax = c.act[x]
  let ay = c.act[y]
  # Strikes: the standing fighter's stomp, the downed fighter's upkick.
  var stomp = @[Ev(kind: evNone, p: 1.0)]
  if ax == aStomp:
    var m = skill(p, c, x) * exposure(p, c, y)
    var fm = 1.0
    if ay == aCover:
      m *= p.coverVs[mkDrop]
      fm *= p.coverForce
    if ay == aGetUp: m *= 0.7
    stomp = strikeEvents(p, c, x, aStomp, p.hitScale * p.hitOver[aStomp] * m, fm)
  var upkick = @[Ev(kind: evNone, p: 1.0)]
  if ay == aUpkick and ax in {aFollow, aStomp}:
    let m = skill(p, c, y) * exposure(p, c, x) * (if ax == aStomp: 0.7 else: 1.0)
    upkick = strikeEvents(p, c, y, aUpkick, p.hitScale * p.hitOver[aUpkick] * m, 1.0)
  for es in stomp:
    for eu in upkick:
      var base = Raw(p: es.p * eu.p, term: -1)
      var offSrc: array[Who, seq[float]]
      var kdRisk: array[Who, bool]
      if es.kind == evLand: recordLand(p, x, es, base, offSrc, kdRisk)
      if es.kind == evMiss: offSrc[x].add p.commit[aStomp]
      if eu.kind == evLand: recordLand(p, y, eu, base, offSrc, kdRisk)
      # Movement outcomes
      var outcomes: seq[(float, Pos, int)]   # prob, position, terminal
      case ax
      of aFlee:
        var ps = p.fleeOver * moveMult(p, c, x)
        if ay == aGetUp: ps *= 0.8
        ps = clampP(p, ps)
        if ps > 0.0: outcomes.add (ps, pLong, ord(tAEscape))
        if ps < 1.0: outcomes.add (1.0 - ps, (if ay == aGetUp: pClose else: overPos(x)), -1)
      of aFollow:
        if eu.kind == evLand:
          outcomes.add (1.0, overPos(x), -1)          # kicked off
        else:
          let ps = clampP(p, (if ay == aGetUp: p.followVsGetUp else: p.followBase) * skill(p, c, x))
          if ps > 0.0: outcomes.add (ps, groundPos(x, gGuard), -1)
          if ps < 1.0: outcomes.add (1.0 - ps, (if ay == aGetUp: pClose else: overPos(x)), -1)
      of aStomp:
        if ay == aGetUp:
          let ps = clampP(p, p.getUpVsStrike * skill(p, c, y))
          if ps > 0.0: outcomes.add (ps, pClose, -1)
          if ps < 1.0: outcomes.add (1.0 - ps, overPos(x), -1)
        else:
          outcomes.add (1.0, overPos(x), -1)
      else:  # aBackOff
        if ay == aGetUp:
          outcomes.add (1.0, pLong, -1)
        elif c.mode == mSport and p.refStandUp > 0.0:
          outcomes.add (p.refStandUp, pLong, -1)
          outcomes.add (1.0 - p.refStandUp, overPos(x), -1)
        else:
          outcomes.add (1.0, overPos(x), -1)
      for (pp, np, term) in outcomes:
        for (offX, po) in coin(combineOff(offSrc[x])):
          var o = base
          o.p = base.p * pp * po
          if o.p <= 0.0: continue
          o.pos = np
          o.off[x] = offX
          if term >= 0:
            o.term = term
            o.tags[x].incl etEscaped
          raws.add o

# ---------------------------------------------------------------------------
# Ground
# ---------------------------------------------------------------------------

proc resolveGround(p: Params, c: Ctx, raws: var seq[Raw]) =
  let pos = c.s.pos
  let x = Who(pos.advantaged)   # top
  let y = x.other               # bottom
  let k = pos.groundKind
  let ax = c.act[x]
  let ay = c.act[y]

  var top: seq[Ev]
  case ax
  of aPound:
    var m = skill(p, c, x) * exposure(p, c, y)
    var fm = 1.0
    if ay == aCover:
      m *= p.coverGround
      fm *= p.coverForce
    let base = case k
      of gGuard: p.poundGuard
      of gMount: p.poundMount
      of gBack: p.poundBack
    top = strikeEvents(p, c, x, aPound, p.hitScale * base * m, fm)
  of aPass:
    top = binaryEvents(p, (if k == gGuard: p.passGuard else: p.passMount) * skill(p, c, x))
  of aChoke:
    var m = skill(p, c, x) * grappleVuln(p, c, y)
    if ay == aCover: m *= p.coverGround
    top = binaryEvents(p, (if k == gMount: p.subMount else: p.subBack) * m)
  of aDisengage:
    top = binaryEvents(p, p.disengage * moveMult(p, c, x))
  else:
    top = @[Ev(kind: evNone, p: 1.0)]

  var bottom: seq[Ev]
  var bm = skill(p, c, y)
  if ax == aHold: bm *= p.holdControl
  case ay
  of aEscape:
    let base = case k
      of gGuard: p.escapeGuard
      of gMount: p.escapeMount
      of gBack: p.escapeBack
    bottom = binaryEvents(p, base * bm)
  of aSweep, aGuardSub:
    if ax == aPound: bm *= p.poundExposes
    if ax == aPass: bm *= p.passExposes
    bottom = binaryEvents(p, (if ay == aSweep: p.sweep else: p.guardSub) * bm)
  else:
    bottom = @[Ev(kind: evNone, p: 1.0)]

  for et in top:
    for eb in bottom:
      let prob = et.p * eb.p
      if prob <= 0.0: continue
      var base = Raw(p: prob, pos: pos, term: -1)
      var offSrc: array[Who, seq[float]]
      var kdRisk: array[Who, bool]
      if et.kind == evLand: recordLand(p, x, et, base, offSrc, kdRisk)
      if ax == aChoke and et.kind == evSuccess:
        base.term = ord(if x == wA: tASub else: tBSub)
        base.tags[x].incl etSubmission
        raws.add base
        continue
      if ay == aGuardSub and eb.kind == evSuccess:
        base.term = ord(if y == wA: tASub else: tBSub)
        base.tags[y].incl etSubmission
        raws.add base
        continue
      var np = pos
      var failCoin = 0.0
      var failPos = pos
      if ay == aSweep and eb.kind == evSuccess:
        np = groundPos(y, gGuard)
        base.tags[y].incl etSweep
      elif ay == aEscape and eb.kind == evSuccess:
        np = if k == gGuard: pLong else: groundPos(x, gGuard)
        base.tags[y].incl etEscape
      elif ax == aPass and et.kind == evSuccess:
        np = groundPos(x, if k == gGuard: gMount else: gBack)
        base.tags[x].incl etPass
      elif ax == aDisengage and et.kind == evSuccess:
        np = pLong
      elif ax == aChoke and et.kind == evFail:
        failCoin = p.subFailEscape
        failPos = groundPos(x, gGuard)
      elif ay == aGuardSub and eb.kind == evFail:
        failCoin = p.guardSubFailPass
        failPos = groundPos(x, gMount)
      elif ay == aEscape and eb.kind == evFail and k != gBack:
        # standing up from guard or turning out of mount exposes the back
        failCoin = if k == gGuard: p.standUpBack else: p.mountTurnBack
        failPos = groundPos(x, gBack)
      elif ax == aHold and ay == aCover and c.mode == mSport:
        failCoin = p.refStandUp     # stalling: the referee restarts them standing
        failPos = pLong
      for (failed, pf) in coin(failCoin):
        var o = base
        o.p = prob * pf
        o.pos = if failed: failPos else: np
        if failed:
          if ax == aChoke: o.tags[y].incl etEscape
          elif ay in {aGuardSub, aEscape}: o.tags[x].incl etPass
        raws.add o

# ---------------------------------------------------------------------------
# Damage, condition, hips, terminal checks
# ---------------------------------------------------------------------------

proc finish(p: Params, c: Ctx, raws: seq[Raw], detailed: bool): seq[Outcome] =
  let dl = c.d.damageLevels

  proc emit(res: var seq[Outcome], prob: float, target: int32,
            tags: array[Who, set[EventTag]], detailed: bool) =
    if prob <= 0.0: return
    if not detailed:
      for o in res.mitems:
        if o.target == target:
          o.p += prob
          return
    res.add Outcome(p: prob, target: target, tags: tags)

  for r in raws:
    if r.p <= 0.0: continue
    let na = c.s.f[wA].dmg + r.dmgTaken[wA]
    let nb = c.s.f[wB].dmg + r.dmgTaken[wB]
    if r.term >= 0 and Terminal(r.term) in {tASub, tBSub}:
      emit(result, r.p, terminalCode(Terminal(r.term)), r.tags, detailed)
      continue
    if na >= dl and nb >= dl:
      emit(result, r.p, terminalCode(tDraw), r.tags, detailed)
      continue
    if na >= dl:
      emit(result, r.p, terminalCode(tBKO), r.tags, detailed)
      continue
    if nb >= dl:
      emit(result, r.p, terminalCode(tAKO), r.tags, detailed)
      continue
    if r.term >= 0:      # escape
      emit(result, r.p, terminalCode(Terminal(r.term)), r.tags, detailed)
      continue
    var ns = State(pos: r.pos)
    for w in Who:
      let old = c.s.f[w]
      ns.f[w] = Fighter(
        dmg: (if w == wA: na else: nb),
        cond: (if r.stun[w]: cStunned elif r.off[w]: cOff else: cOk),
        coil: nextCoil(old, c.act[w]),
        legs: old.legs or r.legs[w])
    ns = canonical(ns)
    emit(result, r.p, int32(encode(ns, c.d)), r.tags, detailed)

proc resolve*(p: Params, s: State, actA, actB: Action, d: Dims,
              mode = mSelfDefense, detailed = false): seq[Outcome] =
  ## Distribution over what happens when A plays `actA` and B plays `actB`
  ## simultaneously in `s`. With `detailed`, outcomes are not merged by target
  ## and keep their event tags (for statistics).
  let c = Ctx(s: s, act: [actA, actB], d: d, mode: mode)
  var raws: seq[Raw]
  if s.pos in StandingPositions: resolveStanding(p, c, raws)
  elif s.pos in ClinchPositions: resolveClinch(p, c, raws)
  elif s.pos in BehindPositions: resolveBehind(p, c, raws)
  elif s.pos in OverPositions: resolveOver(p, c, raws)
  else: resolveGround(p, c, raws)
  finish(p, c, raws, detailed)

proc stopValue*(p: Params, s: State, mode: Mode): float =
  ## Value for A if the encounter ends now without a finish.
  case mode
  of mSport:
    # Judges: damage difference plus who controls the position. Because the
    # stop can come on any beat, the expected decision is the time-average
    # of this along the fight, so control time counts like on a scorecard.
    var v = 0.5 + p.decisionWeight * float(s.f[wB].dmg - s.f[wA].dmg)
    let adv = s.pos.advantaged
    if adv >= 0:
      let bonus = case s.pos
        of pGuardA, pGuardB, pOverA, pOverB, pBehindA, pBehindB: p.decisionTop
        of pMountA, pMountB, pBackA, pBackB: p.decisionDominant
        else: 0.0
      v += (if adv == ord(wA): bonus else: -bonus)
    clamp(v, 0.0, 1.0)
  of mSelfDefense:
    # Your safety: the harm you carry and how exposed you are when it ends.
    var v = 1.0 - p.harmPerLevel * s.f[wA].dmg.float
    if s.pos in {pOverB, pGuardB, pMountB, pBackB}: v -= p.harmDown
    if s.pos in {pMountB, pBackB, pBehindB}: v -= p.harmPinned
    if s.f[wA].legs: v -= 0.5 * p.harmPerLevel
    clamp(v, 0.0, 1.0)
