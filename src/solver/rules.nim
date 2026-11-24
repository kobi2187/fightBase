## Rules of the model: which actions are legal in a position, and how one
## pair of simultaneous actions resolves into an explicit probability
## distribution over next positions.
##
## Resolution of a beat
## 1. Each fighter's action produces a primary event (a strike misses or lands
##    for 0/1/2 damage levels; a takedown, clinch entry, throw, pass, ...
##    succeeds or fails). Probabilities depend on both actions and on both
##    fighters' condition.
## 2. Initiative: if both attack, the technique with the higher `speed`
##    resolves first; when it succeeds it cuts the slower technique's chance.
##    Equal speeds resolve independently (a trade).
## 3. Secondary coin flips: knockdowns, ending off-balance, keeping or taking
##    an angle, failed submissions giving up position.
## 4. The new position follows a fixed priority (knockdown > takedown/throw >
##    clinch > footwork), damage is added (reaching the KO level ends the
##    fight), and each fighter's fatigue moves up or down.
##
## The rules never refer to "A" or "B" directly, only to a fighter and their
## opponent, so swapping the fighters' labels swaps the result. The test suite
## checks that on every state and action pair.

import core, params

type
  EventTag* = enum
    ## What happened during a beat, for statistics (strike accuracy etc.).
    etLanded       ## a strike landed (with or without damage)
    etDamaged      ## a strike dealt at least one damage level
    etKnockdown    ## a strike knocked the opponent down
    etTakedown     ## a takedown succeeded
    etStuffed      ## sprawled on and lost the back
    etThrow        ## a clinch throw succeeded
    etClinchEntry  ## got into the clinch
    etAngle        ## took the angle
    etSubmission   ## finished with a submission
    etCountered    ## landed a counter on an attacking opponent
    etFeinted      ## drew a counter/slip with a feint
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
    p: float

  Raw = object
    ## A resolved beat before damage, fatigue and terminal checks.
    p: float
    pos: Pos
    dmgTaken: array[Who, int]
    off: array[Who, bool]
    term: int                 ## -1, or ord(Terminal) for a submission
    tags: array[Who, set[EventTag]]

  Ctx = object
    s: State
    act: array[Who, Action]
    d: Dims

# ---------------------------------------------------------------------------
# Small helpers
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
  result = max(0.0, 1.0 - p.fatiguePenalty * f.fat.float) *
           max(0.0, 1.0 - p.damagePenalty * f.dmg.float)
  if f.off: result *= p.offAtk

proc exposure(p: Params, c: Ctx, w: Who): float =
  ## Multiplier on strikes landing on this fighter.
  let f = c.s.f[w]
  result = 1.0 + p.fatigueDefense * f.fat.float
  if f.off: result *= p.offDef

proc chin(p: Params, c: Ctx, w: Who): float =
  1.0 + p.chinPenalty * c.s.f[w].dmg.float

proc angleMult(p: Params, c: Ctx, w: Who): float =
  if c.s.pos in StandingPositions:
    if c.s.pos.hasAngle(w): return p.angleAtk
    if c.s.pos.hasAngle(w.other): return p.angleDef
  1.0

proc combineOff(ps: openArray[float]): float =
  var stay = 1.0
  for x in ps: stay *= (1.0 - clamp(x, 0.0, 1.0))
  1.0 - stay

iterator coin(p: float): (bool, float) =
  ## Both sides of a biased coin, skipping impossible ones.
  if p > 0.0: yield (true, min(p, 1.0))
  if p < 1.0: yield (false, 1.0 - max(p, 0.0))

proc strikeEvents(p: Params, c: Ctx, w: Who, landP, d1, d2, dmgMult: float): seq[Ev] =
  let o = w.other
  var l = d1 * dmgMult * chin(p, c, o)
  var h = d2 * dmgMult * chin(p, c, o)
  if l + h > 1.0:
    let k = 1.0 / (l + h)
    l *= k
    h *= k
  let pl = clampP(p, landP)
  if pl < 1.0: result.add Ev(kind: evMiss, p: 1.0 - pl)
  if pl > 0.0:
    if 1.0 - l - h > 1e-15: result.add Ev(kind: evLand, dmg: 0, p: pl * (1.0 - l - h))
    if l > 0.0: result.add Ev(kind: evLand, dmg: 1, p: pl * l)
    if h > 0.0: result.add Ev(kind: evLand, dmg: 2, p: pl * h)

proc binaryEvents(p: Params, success: float): seq[Ev] =
  let ps = clampP(p, success)
  if ps > 0.0: result.add Ev(kind: evSuccess, p: ps)
  if ps < 1.0: result.add Ev(kind: evFail, p: 1.0 - ps)

proc succeeded(e: Ev): bool {.inline.} = e.kind in {evLand, evSuccess}

proc interruptFactor(p: Params, faster: Action): float =
  1.0 - (if faster in LightStrikes: p.interruptLight else: p.interruptHeavy)

template forOrdered(c: Ctx, p: Params, dist: untyped, body: untyped) =
  ## Enumerate the joint primary events of both fighters with initiative:
  ## the faster action resolves first and, on success, disrupts the slower.
  ## Inside `body`: `ev: array[Who, Ev]` and `prob: float`.
  let sa = speed[c.act[wA]]
  let sb = speed[c.act[wB]]
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

# ---------------------------------------------------------------------------
# Legal actions
# ---------------------------------------------------------------------------

proc legalActions*(p: Params, s: State, w: Who, arsenal: set[Action], d: Dims): seq[Action] =
  let pos = s.pos
  var cand: set[Action]
  if pos in StandingPositions:
    let r = pos.rangeOf
    cand = {aRetreat, aCover, aCounter, aFeint, aShoot, aSprawl}
    if r != rClose: cand.incl aAdvance
    if r != rLong: cand = cand + {aCircle, aSlip, aClinch}
    for a in StandingStrikes + {aKnee}:
      if hitAt(p, a, r) > 0.0: cand.incl a
  elif pos in ClinchPositions:
    cand = {aKnee, aPummel, aThrow, aBreak, aCover}
  elif pos in OverPositions:
    cand = if pos.isDown(w): {aGetUp, aUpkick, aCover} else: {aFollow, aBackOff}
  else:
    let k = pos.groundKind
    if pos.isTop(w):
      cand = {aPound, aHold, aDisengage}
      if k in {gGuard, gMount}: cand.incl aPass
      if k in {gMount, gBack}: cand.incl aSubmit
    else:
      cand = {aEscape, aCover}
      if k == gGuard: cand = cand + {aSweep, aGuardSub}
  cand = cand * (arsenal + CoreActions)
  let f = s.f[w]
  if f.off or f.fat >= d.fatigueLevels - 1:
    cand = cand - HeavyActions
  for a in Action:
    if a in cand: result.add a

# ---------------------------------------------------------------------------
# Standing exchanges
# ---------------------------------------------------------------------------

proc standingDist(p: Params, c: Ctx, w: Who, interrupt: float): seq[Ev] =
  let a = c.act[w]
  let o = w.other
  let oa = c.act[o]
  let r = c.s.pos.rangeOf
  case a
  of aJab, aCross, aHook, aKick, aTeep, aKnee:
    var m = skill(p, c, w) * exposure(p, c, o) * angleMult(p, c, w) * interrupt
    case oa
    of aCover: m *= p.coverHit
    of aSlip:
      if a in Punches: m *= p.slipPunch
      elif a == aKick: m *= p.slipKick
    of aRetreat: m *= (if a in {aKick, aTeep}: p.retreatKick else: p.retreatHit)
    of aAdvance: m *= (if a == aKick: p.jamKick else: p.advanceHit)
    of aCircle: m *= p.circleHit
    of aShoot:
      if a in Punches: m *= p.shootDuck
    of aSprawl: m *= p.sprawlExposed
    of aCounter: m *= p.counterDef
    else: discard
    var dm = 1.0
    if oa == aCover: dm *= p.coverDmg
    if oa == aAdvance: dm *= (if a == aKick: p.jamKick else: p.advanceDmg)
    result = strikeEvents(p, c, w, hitAt(p, a, r) * m, p.dmg1[a], p.dmg2[a], dm)
  of aShoot:
    var m = skill(p, c, w) * angleMult(p, c, w) * interrupt
    if c.s.f[o].off: m *= p.offGrapple
    case oa
    of aSprawl: m *= p.sprawlStop
    of aRetreat: m *= p.shootVsRetreat
    of aAdvance: m *= p.shootVsAdvance
    of aKick: m *= p.shootVsKick
    of aCross, aHook: m *= p.shootVsCommit
    of aShoot: m *= p.shootBoth
    else: discard
    let base = case r
      of rLong: p.shootLong
      of rMid: p.shootMid
      of rClose: p.shootClose
    let ps = clampP(p, base * m)
    if ps > 0.0: result.add Ev(kind: evSuccess, p: ps)
    if ps < 1.0:
      if oa == aSprawl:
        # stuffed: front choke, back take, or just stopped
        let q = 1.0 - ps
        let choke = clamp(p.guillotine, 0.0, 1.0)
        let back = (1.0 - choke) * p.sprawlBack
        if choke > 0.0: result.add Ev(kind: evChoked, p: q * choke)
        if back > 0.0: result.add Ev(kind: evStuffed, p: q * back)
        if 1.0 - choke - back > 0.0: result.add Ev(kind: evFail, p: q * (1.0 - choke - back))
      else:
        result.add Ev(kind: evFail, p: 1.0 - ps)
  of aClinch:
    if oa == aClinch:
      result.add Ev(kind: evSuccess, p: 1.0)   # both want the tie-up
    else:
      var m = skill(p, c, w) * angleMult(p, c, w) * interrupt
      if c.s.f[o].off: m *= p.offGrapple
      if oa == aRetreat: m *= p.clinchVsRetreat
      result = binaryEvents(p, (if r == rClose: p.clinchBase else: p.clinchMid) * m)
  of aCounter:
    if oa in StandingStrikes + {aKnee}:
      let m = skill(p, c, w) * exposure(p, c, o) * angleMult(p, c, w) * interrupt
      result = strikeEvents(p, c, w, p.hitScale * p.counterHit * m,
                            p.dmg1[aCounter], p.dmg2[aCounter], 1.0)
    else:
      result.add Ev(kind: evNone, p: 1.0)   # nothing to counter
  of aFeint:
    if oa in {aCounter, aSlip}:
      result = binaryEvents(p, p.feintDraw * skill(p, c, w))
    else:
      result.add Ev(kind: evNone, p: 1.0)
  of aCircle:
    var m = skill(p, c, w) * interrupt
    if oa == aCircle: m *= p.circleVsCircle
    result = binaryEvents(p, p.circleBase * m)
  else:
    result.add Ev(kind: evNone, p: 1.0)

proc resolveStanding(p: Params, c: Ctx, raws: var seq[Raw]) =
  let pos = c.s.pos
  let r = pos.rangeOf
  forOrdered(c, p, standingDist):
    var offSrc: array[Who, seq[float]]
    var dmgTaken: array[Who, int]
    var kdRisk: array[Who, bool]
    var tags: array[Who, set[EventTag]]
    var takedown, stuffedBy, choked, clinchIn, circled: array[Who, bool]
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
        tags[w].incl etLanded
        dmgTaken[o] += e.dmg
        if e.dmg > 0:
          tags[w].incl etDamaged
          offSrc[o].add p.stagger
        if e.dmg >= 2: kdRisk[o] = true
        if a == aTeep:
          pushed = true
          offSrc[o].add p.teepOff
        if a == aCounter: tags[w].incl etCountered
      of evMiss:
        offSrc[w].add p.commit[a]
        if a in Punches and c.act[o] == aSlip: slipChance[o] = p.slipAngle
      of evSuccess:
        case a
        of aShoot: takedown[w] = true
        of aClinch: clinchIn[w] = true
        of aCircle: circled[w] = true
        of aFeint:
          offSrc[o].add 1.0          # the opponent bit on the feint
          tags[w].incl etFeinted
        else: discard
      of evFail:
        offSrc[w].add p.commit[a]
        if a == aShoot: shotFailed = true
      of evStuffed:
        stuffedBy[o] = true
      of evChoked:
        choked[w] = true
      of evNone: discard

    for (kdA, pkA) in coin(if kdRisk[wA]: p.knockdown else: 0.0):
      for (kdB, pkB) in coin(if kdRisk[wB]: p.knockdown else: 0.0):
        for (offA, poA) in coin(combineOff(offSrc[wA])):
          for (offB, poB) in coin(combineOff(offSrc[wB])):
            for (slipA, psA) in coin(slipChance[wA]):
              for (slipB, psB) in coin(slipChance[wB]):
                let base = prob * pkA * pkB * poA * poB * psA * psB
                if base <= 0.0: continue
                var o = Raw(p: base, dmgTaken: dmgTaken, off: [wA: offA, wB: offB],
                            term: -1, tags: tags)
                if choked[wA] or choked[wB]:
                  let winner = if choked[wA]: wB else: wA
                  o.term = ord(if winner == wA: tASub else: tBSub)
                  o.tags[winner].incl etSubmission
                  raws.add o
                  continue
                let kd = [wA: kdA, wB: kdB]
                if kd[wA] and kd[wB]:
                  o.pos = pLong
                  o.off = [wA: true, wB: true]
                  raws.add o
                  continue
                var decided = false
                for w in Who:
                  if kd[w.other]:
                    o.pos = overPos(w)
                    o.tags[w].incl etKnockdown
                    decided = true
                if decided:
                  raws.add o
                  continue
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
                if clinchIn[wA] or clinchIn[wB]:
                  var lvl = 0
                  if clinchIn[wA] and not clinchIn[wB] and pos.hasAngle(wA): lvl = 1
                  if clinchIn[wB] and not clinchIn[wA] and pos.hasAngle(wB): lvl = -1
                  o.pos = clinchPos(lvl)
                  for w in Who:
                    if clinchIn[w]: o.tags[w].incl etClinchEntry
                  raws.add o
                  continue
                # Footwork
                var nr = r
                var lostAngle = false
                if pushed:
                  nr = Range(min(ord(rLong), ord(r) + 1))
                  lostAngle = true
                elif shotFailed:
                  nr = rClose
                else:
                  if intent > 0:
                    nr = Range(min(ord(rLong), ord(r) + 1))
                    lostAngle = true
                  elif intent < 0:
                    nr = Range(max(ord(rClose), ord(r) - 1))
                var angle = -1
                if nr != rLong:
                  if circled[wA] and not circled[wB]: angle = ord(wA)
                  elif circled[wB] and not circled[wA]: angle = ord(wB)
                  elif circled[wA] and circled[wB]: angle = -1
                  elif slipA: angle = ord(wA)
                  elif slipB: angle = ord(wB)
                  else:
                    angle = pos.advantaged
                    if angle >= 0 and lostAngle: angle = -1
                if angle >= 0 and pos.advantaged == angle and
                   not circled[Who(angle)] and not [wA: slipA, wB: slipB][Who(angle)]:
                  # an existing angle nobody renewed: it may fade
                  let keep = p.angleKeep
                  if keep < 1.0:
                    var lose = o
                    lose.p = base * (1.0 - keep)
                    lose.pos = standing(nr, -1)
                    raws.add lose
                  o.p = base * keep
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
  case a
  of aKnee:
    var m = skill(p, c, w) * exposure(p, c, o) * interrupt
    if lvl > 0: m *= p.kneeDom
    elif lvl < 0: m *= p.kneeSub
    if oa == aCover: m *= p.coverHit
    if oa == aPummel: m *= p.kneeVsPummel
    let dm = if oa == aCover: p.coverDmg else: 1.0
    result = strikeEvents(p, c, w, p.hitScale * p.hitClinch[aKnee] * m, p.dmg1[aKnee], p.dmg2[aKnee], dm)
  of aPummel:
    let base = if lvl < 0: p.pummelRecover else: p.pummelGain
    result = binaryEvents(p, base * skill(p, c, w) * interrupt)
  of aThrow:
    var m = skill(p, c, w) * interrupt
    if c.s.f[o].off: m *= p.offGrapple
    if oa == aKnee: m *= p.throwVsKnee
    if oa == aCover: m *= p.throwVsCover
    let base = if lvl > 0: p.throwDom elif lvl < 0: p.throwSub else: p.throwEven
    # a successful throw also rolls damage from the landing
    let ps = clampP(p, base * m)
    if ps < 1.0: result.add Ev(kind: evFail, p: 1.0 - ps)
    if ps > 0.0:
      for e in strikeEvents(p, c, w, 1.0, p.dmg1[aThrow], p.dmg2[aThrow], 1.0):
        result.add Ev(kind: evSuccess, dmg: e.dmg, p: ps * e.p)
  of aBreak:
    if oa == aBreak:
      result.add Ev(kind: evSuccess, p: 1.0)
    else:
      var m = interrupt
      if lvl < 0: m *= p.breakVsDom
      result = binaryEvents(p, p.breakBase * m)
  else:
    result.add Ev(kind: evNone, p: 1.0)

proc resolveClinch(p: Params, c: Ctx, raws: var seq[Raw]) =
  let lvlA = c.s.pos.clinchLevel(wA)
  forOrdered(c, p, clinchDist):
    var offSrc: array[Who, seq[float]]
    var dmgTaken: array[Who, int]
    var kdRisk, threw, broke, pummelled: array[Who, bool]
    var tags: array[Who, set[EventTag]]
    for w in Who:
      let o = w.other
      let a = c.act[w]
      let e = ev[w]
      case e.kind
      of evLand:
        tags[w].incl etLanded
        dmgTaken[o] += e.dmg
        if e.dmg > 0:
          tags[w].incl etDamaged
          offSrc[o].add p.stagger
        if e.dmg >= 2: kdRisk[o] = true
      of evMiss, evFail:
        offSrc[w].add p.commit[a]
      of evSuccess:
        case a
        of aThrow:
          threw[w] = true
          dmgTaken[o] += e.dmg
        of aBreak: broke[w] = true
        of aPummel: pummelled[w] = true
        else: discard
      else: discard
    for (kdA, pkA) in coin(if kdRisk[wA]: p.knockdown else: 0.0):
      for (kdB, pkB) in coin(if kdRisk[wB]: p.knockdown else: 0.0):
        for (offA, poA) in coin(combineOff(offSrc[wA])):
          for (offB, poB) in coin(combineOff(offSrc[wB])):
            let base = prob * pkA * pkB * poA * poB
            if base <= 0.0: continue
            var o = Raw(p: base, dmgTaken: dmgTaken, off: [wA: offA, wB: offB], term: -1, tags: tags)
            let kd = [wA: kdA, wB: kdB]
            if kd[wA] and kd[wB]:
              o.pos = pClose
              o.off = [wA: true, wB: true]
            elif kd[wB]:
              o.pos = overPos(wA)
              o.tags[wA].incl etKnockdown
            elif kd[wA]:
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
              let lvl = clamp(lvlA + ord(pummelled[wA]) - ord(pummelled[wB]), -1, 1)
              o.pos = clinchPos(lvl)
            raws.add o

# ---------------------------------------------------------------------------
# One fighter down, the other standing over them
# ---------------------------------------------------------------------------

proc resolveOver(p: Params, c: Ctx, raws: var seq[Raw]) =
  let x = Who(c.s.pos.advantaged)      # standing
  let y = x.other                       # down
  let ax = c.act[x]
  let ay = c.act[y]
  # Upkick only matters against someone coming in.
  var upkick: seq[Ev]
  if ay == aUpkick and ax == aFollow:
    let land = p.hitScale * p.upkickHit * skill(p, c, y) * exposure(p, c, x)
    upkick = strikeEvents(p, c, y, land, p.dmg1[aUpkick], p.dmg2[aUpkick], 1.0)
  else:
    upkick = @[Ev(kind: evNone, p: 1.0)]
  for e in upkick:
    var dmgTaken: array[Who, int]
    var tags: array[Who, set[EventTag]]
    var staggerX = 0.0
    if e.kind == evLand:
      tags[y].incl etLanded
      dmgTaken[x] = e.dmg
      if e.dmg > 0:
        tags[y].incl etDamaged
        staggerX = p.stagger
    var outcomes: seq[(float, Pos)]
    if ax == aFollow:
      if e.kind == evLand:
        outcomes.add (1.0, overPos(x))          # kicked off; still standing over them
      else:
        let ps = clampP(p, (if ay == aGetUp: p.followVsGetUp else: p.followBase) *
                           skill(p, c, x))
        if ps > 0.0: outcomes.add (ps, groundPos(x, gGuard))
        if ps < 1.0:
          outcomes.add (1.0 - ps, (if ay == aGetUp: pClose else: overPos(x)))
    else:  # aBackOff
      if ay == aGetUp:
        outcomes.add (1.0, pLong)
      else:
        # nobody engages: the referee may stand them up
        if p.refStandUp > 0.0: outcomes.add (p.refStandUp, pLong)
        if p.refStandUp < 1.0: outcomes.add (1.0 - p.refStandUp, overPos(x))
    for (pp, np) in outcomes:
      for (offX, po) in coin(staggerX):
        var o = Raw(p: e.p * pp * po, pos: np, dmgTaken: dmgTaken, term: -1, tags: tags)
        o.off[x] = offX
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

  # Top fighter's event
  var top: seq[Ev]
  case ax
  of aPound:
    var m = skill(p, c, x) * exposure(p, c, y)
    if ay == aCover: m *= p.coverGround
    let base = case k
      of gGuard: p.poundGuard
      of gMount: p.poundMount
      of gBack: p.poundBack
    top = strikeEvents(p, c, x, p.hitScale * base * m, p.dmg1[aPound], p.dmg2[aPound],
                       (if ay == aCover: p.coverDmg else: 1.0))
  of aPass:
    top = binaryEvents(p, (if k == gGuard: p.passGuard else: p.passMount) * skill(p, c, x))
  of aSubmit:
    var m = skill(p, c, x)
    if ay == aCover: m *= p.coverGround
    top = binaryEvents(p, (if k == gMount: p.subMount else: p.subBack) * m)
  of aDisengage:
    top = binaryEvents(p, p.disengage)
  else:
    top = @[Ev(kind: evNone, p: 1.0)]

  # Bottom fighter's event
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
      var dmgTaken: array[Who, int]
      var tags: array[Who, set[EventTag]]
      if et.kind == evLand:
        tags[x].incl etLanded
        dmgTaken[y] = et.dmg
        if et.dmg > 0: tags[x].incl etDamaged
      # Terminal: submissions
      if ax == aSubmit and et.kind == evSuccess:
        var o = Raw(p: prob, pos: pos, term: ord(if x == wA: tASub else: tBSub), tags: tags)
        o.tags[x].incl etSubmission
        raws.add o
        continue
      if ay == aGuardSub and eb.kind == evSuccess:
        var o = Raw(p: prob, pos: pos, term: ord(if y == wA: tASub else: tBSub), tags: tags)
        o.tags[y].incl etSubmission
        raws.add o
        continue
      # Position changes, in priority order
      var np = pos
      var failCoin = 0.0
      var failPos = pos
      if ay == aSweep and eb.kind == evSuccess:
        np = groundPos(y, gGuard)
        tags[y].incl etSweep
      elif ay == aEscape and eb.kind == evSuccess:
        np = if k == gGuard: pLong else: groundPos(x, gGuard)
        tags[y].incl etEscape
      elif ax == aPass and et.kind == evSuccess:
        np = groundPos(x, if k == gGuard: gMount else: gBack)
        tags[x].incl etPass
      elif ax == aDisengage and et.kind == evSuccess:
        np = pLong
      elif ax == aSubmit and et.kind == evFail:
        failCoin = p.subFailEscape
        failPos = groundPos(x, gGuard)
      elif ay == aGuardSub and eb.kind == evFail:
        failCoin = p.guardSubFailPass
        failPos = groundPos(x, gMount)
      elif ay == aEscape and eb.kind == evFail and k != gBack:
        # standing up from guard or turning out of mount exposes the back
        failCoin = if k == gGuard: p.standUpBack else: p.mountTurnBack
        failPos = groundPos(x, gBack)
      elif ax == aHold and ay == aCover:
        failCoin = p.refStandUp     # stalling: the referee may restart them standing
        failPos = pLong
      for (failed, pf) in coin(failCoin):
        var o = Raw(p: prob * pf, pos: (if failed: failPos else: np),
                    dmgTaken: dmgTaken, term: -1, tags: tags)
        if failed:
          if ax == aSubmit: o.tags[y].incl etEscape
          elif ay == aGuardSub or ay == aEscape: o.tags[x].incl etPass
        raws.add o

# ---------------------------------------------------------------------------
# Damage, fatigue, terminal checks
# ---------------------------------------------------------------------------

proc finish(p: Params, c: Ctx, raws: seq[Raw], detailed: bool): seq[Outcome] =
  let dl = c.d.damageLevels
  let fl = c.d.fatigueLevels

  proc emit(res: var seq[Outcome], prob: float, target: int32,
            tags: array[Who, set[EventTag]], detailed: bool) =
    if prob <= 0.0: return
    if not detailed:
      for o in res.mitems:
        if o.target == target:
          o.p += prob
          return
    res.add Outcome(p: prob, target: target, tags: tags)

  # fatigue distribution per fighter: (delta, prob)
  var fatDist: array[Who, seq[(int, float)]]
  for w in Who:
    let a = c.act[w]
    var up = p.cost[a]
    if c.s.pos in {pMountA, pMountB, pBackA, pBackB} and not c.s.pos.isTop(w):
      up += p.bottomFatigue
    up = clamp(up, 0.0, 1.0)
    let f = c.s.f[w].fat
    if f >= fl - 1: up = 0.0
    var down = if f > 0: p.recover[a] else: 0.0
    down = clamp(down, 0.0, 1.0 - up)
    if up > 0.0: fatDist[w].add (1, up)
    if down > 0.0: fatDist[w].add (-1, down)
    if 1.0 - up - down > 0.0: fatDist[w].add (0, 1.0 - up - down)

  for r in raws:
    if r.p <= 0.0: continue
    if r.term >= 0:
      emit(result, r.p, terminalCode(Terminal(r.term)), r.tags, detailed)
      continue
    let na = c.s.f[wA].dmg + r.dmgTaken[wA]
    let nb = c.s.f[wB].dmg + r.dmgTaken[wB]
    if na >= dl and nb >= dl:
      emit(result, r.p, terminalCode(tDraw), r.tags, detailed)
      continue
    if na >= dl:
      emit(result, r.p, terminalCode(tBKO), r.tags, detailed)
      continue
    if nb >= dl:
      emit(result, r.p, terminalCode(tAKO), r.tags, detailed)
      continue
    for (dfa, pfa) in fatDist[wA]:
      for (dfb, pfb) in fatDist[wB]:
        var ns = State(pos: r.pos)
        ns.f[wA] = Fighter(dmg: na, fat: c.s.f[wA].fat + dfa, off: r.off[wA])
        ns.f[wB] = Fighter(dmg: nb, fat: c.s.f[wB].fat + dfb, off: r.off[wB])
        ns = canonical(ns)
        emit(result, r.p * pfa * pfb, int32(encode(ns, c.d)), r.tags, detailed)

proc resolve*(p: Params, s: State, actA, actB: Action, d: Dims,
              detailed = false): seq[Outcome] =
  ## Distribution over what happens when A plays `actA` and B plays `actB`
  ## simultaneously in `s`. With `detailed`, outcomes are not merged by target
  ## and keep their event tags (for statistics).
  let c = Ctx(s: s, act: [actA, actB], d: d)
  var raws: seq[Raw]
  if s.pos in StandingPositions: resolveStanding(p, c, raws)
  elif s.pos in ClinchPositions: resolveClinch(p, c, raws)
  elif s.pos in OverPositions: resolveOver(p, c, raws)
  else: resolveGround(p, c, raws)
  finish(p, c, raws, detailed)

proc decisionValue*(p: Params, s: State): float =
  ## P(A wins) if the fight is stopped now and goes to the judges: damage
  ## difference plus who controls the position. Because the stop can come on
  ## any beat, the expected decision is the time-average of this along the
  ## fight, so holding top position works like control time on a scorecard.
  var v = 0.5 + p.decisionWeight * float(s.f[wB].dmg - s.f[wA].dmg)
  let adv = s.pos.advantaged
  if adv >= 0:
    let bonus = case s.pos
      of pGuardA, pGuardB, pOverA, pOverB: p.decisionTop
      of pMountA, pMountB, pBackA, pBackB: p.decisionDominant
      else: 0.0
    v += (if adv == ord(wA): bonus else: -bonus)
  clamp(v, 0.0, 1.0)
