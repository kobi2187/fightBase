## Core vocabulary of the equilibrium solver.
##
## A confrontation is a two-player, zero-sum, simultaneous-move stochastic
## game: every beat both fighters pick an action at the same time, the pair
## of actions resolves into an explicit probability distribution over next
## positions, and the game ends by incapacitation, a choke, an escape, or a
## stoppage.
##
## Everything that can change the outcome is part of `State`, so the value of
## a position depends on the position only (the Markov property a tablebase
## needs). All of it is discrete, so the position space is finite.
##
## Two modes share the same rules:
## - self-defense (default): fighter A is the defender ("you"), B the
##   attacker. The value is P(you come out safe): you escape, or the attacker
##   is incapacitated. There are no judges; a stoppage is scored by the harm
##   you have taken.
## - sport: symmetric, no escaping, decisions by judges. Used as a
##   correctness check (a symmetric matchup must be worth exactly 0.5).

import std/[strutils]
import ../vulnerabilities

export VulnerabilityZone

type
  Who* = enum
    wA = "A"
    wB = "B"

  Mode* = enum
    mSelfDefense = "self-defense"
    mSport = "sport"

  Pos* = enum
    ## Shared geometry of the two fighters. A suffix `A`/`B` always names the
    ## fighter who holds the advantage in that position.
    pLong        ## kicking range
    pMid         ## punching range
    pMidAngA     ## punching range, A is off the centre line (outside angle)
    pMidAngB
    pClose       ## elbow/knee range, not tied up
    pCloseAngA
    pCloseAngB
    pClinch      ## standing tie-up, neither fighter dominant
    pClinchA     ## A holds the dominant grip (headlock, double underhooks, plum)
    pClinchB
    pBehindA     ## A is behind B, standing (bear hug, rear choke attempt)
    pBehindB
    pOverA       ## A standing over B, who is down
    pOverB
    pGuardA      ## A on top inside B's guard
    pGuardB
    pMountA      ## A mounted on B
    pMountB
    pBackA       ## A has B's back on the ground
    pBackB

  Range* = enum
    rClose, rMid, rLong

  GroundKind* = enum
    gGuard, gMount, gBack

  Cond* = enum
    ## Lasts one beat unless renewed.
    cOk        ## set and ready
    cOff       ## off-balance or recovering from a committed move
    cStunned   ## pain/reflex shock (eyes, groin, liver, nose...) or a hard hit

  Coil* = enum
    ## Which side of the body is loaded for a rotational strike. A normal
    ## stance loads the rear side; a rear rotational strike unwinds it and
    ## loads the lead side, and vice versa. This is what makes cross -> hook
    ## -> cross chain naturally.
    coRear
    coLead

  Mechanics* = enum
    ## How a technique generates force.
    mkNone        ## not a strike
    mkLinear      ## straight line, little wind-up (jab, oblique kick)
    mkRotational  ## hip/torso torque (cross, hook, round kick); wants a loaded side
    mkWhip        ## elastic, relaxed snap (finger jab, groin kick): fastest, light
    mkPush        ## pushes the target away (teep, shove)
    mkDrop        ## body weight falling into the target (stomp)

  Side* = enum
    sdNone, sdLead, sdRear

  Action* = enum
    # footwork
    aAdvance, aRetreat, aCircle, aFlee
    # defence and timing
    aCover, aSlip, aParry, aCounter, aFeint
    # strikes
    aFingerJab, aJab, aCross, aHook, aHaymaker, aBodyHook, aElbow,
    aGroinKick, aObliqueKick, aLowKick, aRoundKick, aTeep, aKnee,
    aHeadbutt, aStomp
    # grappling
    aPush, aGrab, aShoot, aSprawl, aPummel, aThrow, aBreak, aChoke, aTurn
    # one fighter down
    aFollow, aBackOff, aGetUp, aUpkick
    # ground
    aPound, aPass, aHold, aDisengage, aEscape, aSweep, aGuardSub

  Fighter* = object
    dmg*: int      ## accumulated damage level, 0 .. damageLevels-1 (reaching damageLevels = incapacitated)
    cond*: Cond
    coil*: Coil
    legs*: bool    ## legs hurt (knee/thigh damage): slower, cannot kick, hard to flee or chase

  State* = object
    pos*: Pos
    f*: array[Who, Fighter]

  Dims* = object
    damageLevels*: int   ## live damage levels; the next one incapacitates

  Terminal* = enum
    ## Encoded as negative transition targets (see `terminalCode`).
    tAKO, tASub, tBKO, tBSub, tDraw, tAEscape

  TechSpec* = object
    mech*: Mechanics
    side*: Side
    speed*: int                  ## initiative; higher resolves first
    zone*: VulnerabilityZone     ## primary target
    downZone*: VulnerabilityZone ## target when the opponent is stunned/bent over or down

const
  defaultDims* = Dims(damageLevels: 4)

  nz = vzCenterMass  ## "no specific target"

  tech*: array[Action, TechSpec] = [
    aAdvance: TechSpec(), aRetreat: TechSpec(), aCircle: TechSpec(), aFlee: TechSpec(),
    aCover: TechSpec(), aSlip: TechSpec(), aParry: TechSpec(),
    aCounter: TechSpec(mech: mkLinear, side: sdLead, speed: 3, zone: vzNose, downZone: vzNose),
    aFeint: TechSpec(),
    aFingerJab: TechSpec(mech: mkWhip, side: sdLead, speed: 4, zone: vzEyes, downZone: vzEyes),
    aJab: TechSpec(mech: mkLinear, side: sdLead, speed: 3, zone: vzNose, downZone: vzNose),
    aCross: TechSpec(mech: mkRotational, side: sdRear, speed: 2, zone: vzJaw, downZone: vzJaw),
    aHook: TechSpec(mech: mkRotational, side: sdLead, speed: 2, zone: vzTemples, downZone: vzJaw),
    aHaymaker: TechSpec(mech: mkRotational, side: sdRear, speed: 1, zone: vzTemples, downZone: vzTemples),
    aBodyHook: TechSpec(mech: mkRotational, side: sdLead, speed: 2, zone: vzLiver, downZone: vzLiver),
    aElbow: TechSpec(mech: mkRotational, side: sdLead, speed: 3, zone: vzTemples, downZone: vzTemples),
    aGroinKick: TechSpec(mech: mkWhip, side: sdRear, speed: 3, zone: vzGroin, downZone: vzGroin),
    aObliqueKick: TechSpec(mech: mkLinear, side: sdLead, speed: 3, zone: vzKneeLateral, downZone: vzKneeLateral),
    aLowKick: TechSpec(mech: mkRotational, side: sdRear, speed: 2, zone: vzThighMuscle, downZone: vzThighMuscle),
    aRoundKick: TechSpec(mech: mkRotational, side: sdRear, speed: 1, zone: vzLiver, downZone: vzJaw),
    aTeep: TechSpec(mech: mkPush, side: sdLead, speed: 2, zone: vzSolarPlexus, downZone: vzSolarPlexus),
    aKnee: TechSpec(mech: mkRotational, side: sdRear, speed: 2, zone: vzGroin, downZone: vzNose),
    aHeadbutt: TechSpec(mech: mkLinear, side: sdNone, speed: 3, zone: vzNose, downZone: vzNose),
    aStomp: TechSpec(mech: mkDrop, side: sdRear, speed: 2, zone: vzFoot, downZone: vzJaw),
    aPush: TechSpec(mech: mkPush, side: sdNone, speed: 2, zone: nz, downZone: nz),
    aGrab: TechSpec(speed: 2), aShoot: TechSpec(speed: 2), aSprawl: TechSpec(),
    aPummel: TechSpec(), aThrow: TechSpec(speed: 1), aBreak: TechSpec(speed: 1),
    aChoke: TechSpec(), aTurn: TechSpec(speed: 1),
    aFollow: TechSpec(), aBackOff: TechSpec(), aGetUp: TechSpec(),
    aUpkick: TechSpec(mech: mkLinear, side: sdRear, speed: 2, zone: vzJaw, downZone: vzJaw),
    aPound: TechSpec(mech: mkDrop, side: sdNone, speed: 2, zone: vzJaw, downZone: vzJaw),
    aPass: TechSpec(), aHold: TechSpec(), aDisengage: TechSpec(), aEscape: TechSpec(),
    aSweep: TechSpec(), aGuardSub: TechSpec()]

  Strikes* = {aCounter, aFingerJab, aJab, aCross, aHook, aHaymaker, aBodyHook,
              aElbow, aGroinKick, aObliqueKick, aLowKick, aRoundKick, aTeep,
              aKnee, aHeadbutt, aStomp, aUpkick, aPound}
  StandingStrikes* = {aFingerJab, aJab, aCross, aHook, aHaymaker, aBodyHook,
                      aElbow, aGroinKick, aObliqueKick, aLowKick, aRoundKick,
                      aTeep, aKnee}
  Kicks* = {aGroinKick, aObliqueKick, aLowKick, aRoundKick, aTeep}
  Punches* = {aFingerJab, aJab, aCross, aHook, aHaymaker, aBodyHook, aCounter}
  ## Committed techniques nobody can launch while off-balance or stunned.
  HeavyActions* = {aHaymaker, aRoundKick, aLowKick, aShoot, aThrow}
  ## Attacks that commit the body forward: interceptable by a straight
  ## technique with reach (stop-hit, stop-kick).
  Committing* = {aAdvance, aHaymaker, aShoot, aGrab, aPush, aRoundKick}
  ## What a stunned fighter can still do.
  StunnedActions* = {aCover, aRetreat, aHold, aBackOff, aBreak}
  ## Actions every fighter has, whatever their style. Without them some
  ## positions would have no legal action at all.
  CoreActions* = {aAdvance, aRetreat, aCover, aBreak, aFollow, aBackOff,
                  aGetUp, aHold, aEscape, aDisengage, aTurn}
  Techniques* = {low(Action) .. high(Action)} - CoreActions
  AllActions* = {low(Action) .. high(Action)}

  StandingPositions* = {pLong .. pCloseAngB}
  ClinchPositions* = {pClinch, pClinchA, pClinchB}
  BehindPositions* = {pBehindA, pBehindB}
  OverPositions* = {pOverA, pOverB}
  GroundPositions* = {pGuardA .. pBackB}
  LegZones* = {vzKneeLateral, vzKneeFront, vzFoot, vzThighMuscle, vzCalf, vzAnkle, vzHip}
  HeadZones* = {vzEyes, vzTemples, vzNose, vzJaw, vzEars, vzThroat, vzBackOfHead, vzNeck}

proc other*(w: Who): Who {.inline.} = (if w == wA: wB else: wA)

proc name*(a: Action): string =
  ## "aGuardSub" -> "GuardSub"
  ($a)[1 .. ^1]

proc name*(p: Pos): string = ($p)[1 .. ^1]

proc zoneName*(z: VulnerabilityZone): string = ($z)[2 .. ^1]

proc parseAction*(s: string): Action =
  for a in Action:
    if cmpIgnoreCase(a.name, s) == 0: return a
  raise newException(ValueError, "unknown action: " & s)

proc parsePos*(s: string): Pos =
  for p in Pos:
    if cmpIgnoreCase(p.name, s) == 0: return p
  raise newException(ValueError, "unknown position: " & s)

# ---------------------------------------------------------------------------
# Position geometry
# ---------------------------------------------------------------------------

proc swapPos*(p: Pos): Pos =
  ## The same position seen with the fighters' labels exchanged.
  case p
  of pLong, pMid, pClose, pClinch: p
  of pMidAngA: pMidAngB
  of pMidAngB: pMidAngA
  of pCloseAngA: pCloseAngB
  of pCloseAngB: pCloseAngA
  of pClinchA: pClinchB
  of pClinchB: pClinchA
  of pBehindA: pBehindB
  of pBehindB: pBehindA
  of pOverA: pOverB
  of pOverB: pOverA
  of pGuardA: pGuardB
  of pGuardB: pGuardA
  of pMountA: pMountB
  of pMountB: pMountA
  of pBackA: pBackB
  of pBackB: pBackA

proc rangeOf*(p: Pos): Range =
  case p
  of pLong: rLong
  of pMid, pMidAngA, pMidAngB: rMid
  of pClose, pCloseAngA, pCloseAngB: rClose
  else: raise newException(ValueError, "not a standing position: " & $p)

proc hasAngle*(p: Pos, w: Who): bool =
  case w
  of wA: p in {pMidAngA, pCloseAngA}
  of wB: p in {pMidAngB, pCloseAngB}

proc standing*(r: Range, angle: int): Pos =
  ## angle: -1 none, ord(wA) / ord(wB) for the fighter holding it.
  case r
  of rLong: pLong
  of rMid: (if angle < 0: pMid elif angle == ord(wA): pMidAngA else: pMidAngB)
  of rClose: (if angle < 0: pClose elif angle == ord(wA): pCloseAngA else: pCloseAngB)

proc clinchLevel*(p: Pos, w: Who): int =
  ## +1 if `w` holds the dominant grip, -1 if the opponent does, 0 if even.
  if p == pClinch: 0
  elif (p == pClinchA) == (w == wA): 1
  else: -1

proc clinchPos*(levelForA: int): Pos =
  if levelForA > 0: pClinchA elif levelForA < 0: pClinchB else: pClinch

proc behindPos*(controller: Who): Pos =
  if controller == wA: pBehindA else: pBehindB

proc overPos*(standingFighter: Who): Pos =
  if standingFighter == wA: pOverA else: pOverB

proc groundPos*(top: Who, k: GroundKind): Pos =
  case k
  of gGuard: (if top == wA: pGuardA else: pGuardB)
  of gMount: (if top == wA: pMountA else: pMountB)
  of gBack: (if top == wA: pBackA else: pBackB)

proc groundKind*(p: Pos): GroundKind =
  case p
  of pGuardA, pGuardB: gGuard
  of pMountA, pMountB: gMount
  of pBackA, pBackB: gBack
  else: raise newException(ValueError, "not a ground position: " & $p)

proc advantaged*(p: Pos): int =
  ## ord(Who) of the fighter the position favours, or -1 if neutral.
  case p
  of pMidAngA, pCloseAngA, pClinchA, pBehindA, pOverA, pGuardA, pMountA, pBackA: ord(wA)
  of pMidAngB, pCloseAngB, pClinchB, pBehindB, pOverB, pGuardB, pMountB, pBackB: ord(wB)
  else: -1

proc isDown*(p: Pos, w: Who): bool =
  ## Is fighter `w` on the ground in this position?
  if p in OverPositions: p.advantaged != ord(w)
  else: p in GroundPositions

proc isTop*(p: Pos, w: Who): bool = p in GroundPositions and p.advantaged == ord(w)

# ---------------------------------------------------------------------------
# State encoding: a dense integer index over the whole discrete space
# ---------------------------------------------------------------------------

proc fighterCount*(d: Dims): int = d.damageLevels * 3 * 2 * 2

proc stateCount*(d: Dims): int =
  let n = fighterCount(d)
  (ord(high(Pos)) + 1) * n * n

proc encode*(f: Fighter, d: Dims): int =
  ((f.dmg * 3 + ord(f.cond)) * 2 + ord(f.coil)) * 2 + ord(f.legs)

proc decodeFighter*(x: int, d: Dims): Fighter =
  result.legs = (x mod 2) == 1
  result.coil = Coil((x div 2) mod 2)
  result.cond = Cond((x div 4) mod 3)
  result.dmg = x div 12

proc encode*(s: State, d: Dims): int =
  let n = fighterCount(d)
  (ord(s.pos) * n + encode(s.f[wA], d)) * n + encode(s.f[wB], d)

proc decodeState*(x: int, d: Dims): State =
  let n = fighterCount(d)
  result.f[wB] = decodeFighter(x mod n, d)
  result.f[wA] = decodeFighter((x div n) mod n, d)
  result.pos = Pos(x div (n * n))

proc canonical*(s: State): State =
  ## Balance and hip loading mean nothing on the ground: clear them so
  ## equivalent positions share one index.
  result = s
  for w in Who:
    if s.pos in GroundPositions or s.pos.isDown(w):
      if result.f[w].cond == cOff: result.f[w].cond = cOk
      result.f[w].coil = coRear

proc swap*(s: State): State =
  State(pos: swapPos(s.pos), f: [s.f[wB], s.f[wA]])

proc startState*(pos = pLong): State =
  ## Fresh fighters in a normal stance (rear side loaded).
  State(pos: pos)

proc `$`*(f: Fighter): string =
  result = "dmg " & $f.dmg
  if f.cond == cOff: result &= " off-balance"
  elif f.cond == cStunned: result &= " STUNNED"
  if f.coil == coLead: result &= " lead-loaded"
  if f.legs: result &= " legs-hurt"

proc `$`*(s: State): string =
  s.pos.name & " | A: " & $s.f[wA] & " | B: " & $s.f[wB]

proc terminalCode*(t: Terminal): int32 = -1'i32 - int32(ord(t))

proc toTerminal*(code: int32): Terminal = Terminal(-1 - code)

proc terminalValue*(t: Terminal): float =
  ## Value from A's point of view.
  case t
  of tAKO, tASub, tAEscape: 1.0
  of tBKO, tBSub: 0.0
  of tDraw: 0.5

proc winner*(t: Terminal): int =
  case t
  of tAKO, tASub, tAEscape: ord(wA)
  of tBKO, tBSub: ord(wB)
  of tDraw: -1

# ---------------------------------------------------------------------------
# Profiles: who the fighters are
# ---------------------------------------------------------------------------

type Style* = object
  name*: string
  role*: string           ## "defender", "attacker" or "sport"
  description*: string
  techniques*: set[Action]

const styles* = [
  Style(name: "trained", role: "defender",
        description: "self-defense trained: footwork, deflection, counters, weak-point strikes, escapes",
        techniques: {aCircle, aFlee, aSlip, aParry, aCounter, aFeint, aFingerJab,
                     aJab, aCross, aHook, aBodyHook, aElbow, aGroinKick,
                     aObliqueKick, aLowKick, aTeep, aKnee, aHeadbutt, aStomp,
                     aPush, aGrab, aSprawl, aPummel, aThrow, aUpkick, aPound,
                     aPass, aSweep, aGuardSub}),
  Style(name: "untrained", role: "defender",
        description: "no training: instinctive covering, pushing, wild swings, running",
        techniques: {aFlee, aHaymaker, aPush, aGrab, aPound}),
  Style(name: "brawler", role: "attacker",
        description: "typical street aggressor: shoves, grabs, haymakers, tackles, headlocks, stomps",
        techniques: {aHaymaker, aJab, aPush, aGrab, aShoot, aKnee, aHeadbutt,
                     aStomp, aChoke, aThrow, aPound, aPummel}),
  Style(name: "striker", role: "attacker",
        description: "trained striker: jab, cross, hook, kicks, counters, clinch knees",
        techniques: {aCircle, aSlip, aParry, aCounter, aFeint, aJab, aCross,
                     aHook, aBodyHook, aElbow, aLowKick, aRoundKick, aTeep,
                     aKnee, aPush, aGrab, aPummel, aSprawl, aStomp, aPound}),
  Style(name: "grappler", role: "attacker",
        description: "trained grappler: takedowns, clinch control, chokes, ground and pound",
        techniques: {aJab, aPush, aGrab, aShoot, aSprawl, aPummel, aThrow,
                     aChoke, aKnee, aPound, aPass, aSweep, aGuardSub, aStomp}),
  Style(name: "complete", role: "sport",
        description: "every technique (sport mode reference)",
        techniques: Techniques - {aFlee}),
]

proc findStyle*(name: string): Style =
  for s in styles:
    if cmpIgnoreCase(s.name, name) == 0: return s
  var names: seq[string]
  for s in styles: names.add s.name
  raise newException(ValueError, "unknown profile '" & name & "' (known: " &
                     names.join(", ") & ")")

proc arsenal*(st: Style): set[Action] = st.techniques + CoreActions
