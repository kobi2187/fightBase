## Core vocabulary of the equilibrium solver.
##
## A fight is a two-player, zero-sum, simultaneous-move stochastic game:
## every beat both fighters pick an action at the same time, the pair of
## actions resolves into an explicit probability distribution over next
## positions, and the game ends by knockout, submission, or a stoppage that
## goes to a decision.
##
## Everything that can change the outcome is part of `State`, so the value of
## a position depends on the position only (the Markov property a tablebase
## needs). All of it is discrete, so the position space is finite.

import std/[strutils]

type
  Who* = enum
    wA = "A"
    wB = "B"

  Pos* = enum
    ## Shared geometry of the two fighters. A suffix `A`/`B` always names the
    ## fighter who holds the advantage in that position.
    pLong        ## kicking range
    pMid         ## punching range
    pMidAngA     ## punching range, A has the outside angle
    pMidAngB
    pClose       ## elbow/knee range, not tied up
    pCloseAngA
    pCloseAngB
    pClinch      ## standing tie-up, neither fighter dominant
    pClinchA     ## A has the dominant ties (underhooks / plum)
    pClinchB
    pOverA       ## A standing over B, who is down
    pOverB
    pGuardA      ## A on top inside B's guard
    pGuardB
    pMountA      ## A mounted on B
    pMountB
    pBackA       ## A has B's back
    pBackB

  Range* = enum
    rClose, rMid, rLong

  GroundKind* = enum
    gGuard, gMount, gBack

  Action* = enum
    # footwork
    aAdvance, aRetreat, aCircle
    # standing strikes
    aJab, aCross, aHook, aKick, aTeep
    # standing defence and timing
    aCover, aSlip, aCounter, aFeint
    # grappling entries and their counters
    aShoot, aSprawl, aClinch
    # clinch
    aKnee, aPummel, aThrow, aBreak
    # one fighter down
    aFollow, aBackOff, aGetUp, aUpkick
    # ground, top
    aPound, aPass, aSubmit, aHold, aDisengage
    # ground, bottom
    aEscape, aSweep, aGuardSub

  Fighter* = object
    dmg*: int    ## accumulated damage level, 0 .. damageLevels-1 (reaching damageLevels = KO)
    fat*: int    ## fatigue level, 0 .. fatigueLevels-1
    off*: bool   ## off-balance / still recovering from a committed move (lasts one beat)

  State* = object
    pos*: Pos
    f*: array[Who, Fighter]

  Dims* = object
    ## Discretisation of the per-fighter condition.
    damageLevels*: int   ## live damage levels; the next one is a knockout
    fatigueLevels*: int

  Terminal* = enum
    ## Encoded as negative transition targets (see `terminalCode`).
    tAKO, tASub, tBKO, tBSub, tDraw

const
  defaultDims* = Dims(damageLevels: 4, fatigueLevels: 3)

  Punches* = {aJab, aCross, aHook}
  StandingStrikes* = {aJab, aCross, aHook, aKick, aTeep}
  Strikes* = StandingStrikes + {aKnee, aUpkick, aPound}
  LightStrikes* = {aJab, aTeep}
  ## Committed techniques nobody can launch while off-balance or exhausted.
  HeavyActions* = {aKick, aShoot, aThrow}
  ## Actions every fighter has, whatever their style. Without them some
  ## positions would have no legal action at all.
  CoreActions* = {aAdvance, aRetreat, aCover, aBreak, aFollow, aBackOff,
                  aGetUp, aHold, aEscape, aDisengage}
  Techniques* = {low(Action) .. high(Action)} - CoreActions
  AllActions* = {low(Action) .. high(Action)}

  ## Initiative: when both fighters attack, the faster technique resolves
  ## first and, if it succeeds, disrupts the slower one.
  speed*: array[Action, int] = [
    aAdvance: 0, aRetreat: 0, aCircle: 0,
    aJab: 3, aCross: 2, aHook: 2, aKick: 1, aTeep: 2,
    aCover: 0, aSlip: 0, aCounter: 3, aFeint: 0,
    aShoot: 2, aSprawl: 0, aClinch: 1,
    aKnee: 2, aPummel: 0, aThrow: 1, aBreak: 1,
    aFollow: 0, aBackOff: 0, aGetUp: 0, aUpkick: 2,
    aPound: 2, aPass: 0, aSubmit: 0, aHold: 0, aDisengage: 0,
    aEscape: 0, aSweep: 0, aGuardSub: 0]

  StandingPositions* = {pLong .. pCloseAngB}
  ClinchPositions* = {pClinch, pClinchA, pClinchB}
  OverPositions* = {pOverA, pOverB}
  GroundPositions* = {pGuardA .. pBackB}

proc other*(w: Who): Who {.inline.} = (if w == wA: wB else: wA)

proc name*(a: Action): string =
  ## "aGuardSub" -> "GuardSub"
  ($a)[1 .. ^1]

proc name*(p: Pos): string = ($p)[1 .. ^1]

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
  ## +1 if `w` holds the dominant ties, -1 if the opponent does, 0 if even.
  if p == pClinch: 0
  elif (p == pClinchA) == (w == wA): 1
  else: -1

proc clinchPos*(levelForA: int): Pos =
  if levelForA > 0: pClinchA elif levelForA < 0: pClinchB else: pClinch

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
  of pMidAngA, pCloseAngA, pClinchA, pOverA, pGuardA, pMountA, pBackA: ord(wA)
  of pMidAngB, pCloseAngB, pClinchB, pOverB, pGuardB, pMountB, pBackB: ord(wB)
  else: -1

proc isDown*(p: Pos, w: Who): bool =
  ## Is fighter `w` on the ground in this position?
  if p in OverPositions: p.advantaged != ord(w)
  else: p in GroundPositions

proc isTop*(p: Pos, w: Who): bool = p in GroundPositions and p.advantaged == ord(w)

# ---------------------------------------------------------------------------
# State encoding: a dense integer index over the whole discrete space
# ---------------------------------------------------------------------------

proc fighterCount*(d: Dims): int = d.damageLevels * d.fatigueLevels * 2

proc stateCount*(d: Dims): int =
  let n = fighterCount(d)
  (ord(high(Pos)) + 1) * n * n

proc encode*(f: Fighter, d: Dims): int =
  (f.dmg * d.fatigueLevels + f.fat) * 2 + ord(f.off)

proc decodeFighter*(x: int, d: Dims): Fighter =
  result.off = (x mod 2) == 1
  let y = x div 2
  result.fat = y mod d.fatigueLevels
  result.dmg = y div d.fatigueLevels

proc encode*(s: State, d: Dims): int =
  let n = fighterCount(d)
  (ord(s.pos) * n + encode(s.f[wA], d)) * n + encode(s.f[wB], d)

proc decodeState*(x: int, d: Dims): State =
  let n = fighterCount(d)
  result.f[wB] = decodeFighter(x mod n, d)
  result.f[wA] = decodeFighter((x div n) mod n, d)
  result.pos = Pos(x div (n * n))

proc canonical*(s: State): State =
  ## Balance means nothing to a fighter on the ground: clear it so equivalent
  ## positions share one index.
  result = s
  for w in Who:
    if s.pos.isDown(w) or s.pos in GroundPositions:
      result.f[w].off = false

proc swap*(s: State): State =
  State(pos: swapPos(s.pos), f: [s.f[wB], s.f[wA]])

proc startState*(): State =
  ## Fresh fighters squaring up at kicking range.
  State(pos: pLong)

proc `$`*(f: Fighter): string =
  "dmg " & $f.dmg & " fat " & $f.fat & (if f.off: " OFF" else: "")

proc `$`*(s: State): string =
  s.pos.name & " | A: " & $s.f[wA] & " | B: " & $s.f[wB]

proc terminalCode*(t: Terminal): int32 = -1'i32 - int32(ord(t))

proc toTerminal*(code: int32): Terminal = Terminal(-1 - code)

proc terminalValue*(t: Terminal): float =
  ## Value from A's point of view: probability A wins.
  case t
  of tAKO, tASub: 1.0
  of tBKO, tBSub: 0.0
  of tDraw: 0.5

proc winner*(t: Terminal): int =
  case t
  of tAKO, tASub: ord(wA)
  of tBKO, tBSub: ord(wB)
  of tDraw: -1

# ---------------------------------------------------------------------------
# Styles: illustrative arsenals for matchup studies
# ---------------------------------------------------------------------------

type Style* = object
  name*: string
  techniques*: set[Action]

const styles* = [
  Style(name: "complete", techniques: Techniques),
  Style(name: "boxer", techniques: {aCircle, aJab, aCross, aHook, aSlip,
        aCounter, aFeint}),
  Style(name: "kickboxer", techniques: {aCircle, aJab, aCross, aHook, aKick,
        aTeep, aSlip, aCounter, aFeint, aClinch, aKnee, aPummel, aThrow}),
  Style(name: "wrestler", techniques: {aCircle, aJab, aFeint, aShoot, aSprawl,
        aClinch, aPummel, aThrow, aPound, aPass}),
  Style(name: "grappler", techniques: {aShoot, aSprawl, aClinch, aPummel,
        aThrow, aUpkick, aPass, aSubmit, aSweep, aGuardSub}),
  Style(name: "judoka", techniques: {aClinch, aPummel, aThrow, aSprawl, aPass,
        aSubmit, aSweep, aPound}),
]

proc findStyle*(name: string): Style =
  for s in styles:
    if cmpIgnoreCase(s.name, name) == 0: return s
  var names: seq[string]
  for s in styles: names.add s.name
  raise newException(ValueError, "unknown style '" & name & "' (known: " &
                     names.join(", ") & ")")

proc arsenal*(st: Style): set[Action] = st.techniques + CoreActions
