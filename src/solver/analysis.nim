## What optimal play looks like: how encounters end, where they are fought,
## which techniques get used, how often they land, which body zones they hit
## and what that does. Everything is computed exactly from the solved
## strategies (expected values over the Markov chain they induce), not by
## sampling.

import std/[algorithm, math, strformat, strutils, tables]
import core, params, rules, game, solve

type
  FightStats* = object
    beats*: float                          ## expected beats played
    stopped*: float                        ## P(ends without a finish)
    stopValue*: float                      ## expected value A collects from stoppages
    finishes*: array[Terminal, float]      ## P(ends this way)
    valueA*: float                         ## total value for A (= start value)
    uses*: array[Who, array[Action, float]]    ## expected times each action is chosen
    events*: array[Who, array[EventTag, float]] ## expected count of each event
    landed*: array[Who, array[Action, float]]   ## expected landed strikes per technique
    zoneHits*: array[Who, array[VulnerabilityZone, float]] ## landed strikes per target zone
    timeIn*: array[Pos, float]             ## expected beats spent in each position

proc flows(g: Game, sol: Solution): seq[seq[(int32, float)]] =
  ## Expected next-state flow under the equilibrium mix (support pairs only).
  let n = g.states.len
  result = newSeq[seq[(int32, float)]](n)
  for s in 0 ..< n:
    let m = g.nActs(wA, s)
    let k = g.nActs(wB, s)
    let oa = int(g.actOff[wA][s])
    let ob = int(g.actOff[wB][s])
    var acc = initTable[int32, float]()
    for i in 0 ..< m:
      let xi = sol.strat[wA][oa + i]
      if xi <= 0.0: continue
      for j in 0 ..< k:
        let yj = sol.strat[wB][ob + j]
        if yj <= 0.0: continue
        let pair = g.pairIndex(s, i, j)
        for o in g.outOff[pair] ..< g.outOff[pair + 1]:
          let t = g.target[o]
          if t >= 0:
            acc.mgetOrPut(t, 0.0) += xi * yj * g.prob[o]
    for t, p in acc: result[s].add (t, p)

proc occupancy*(g: Game, sol: Solution, start: int, tol = 1e-12): seq[float] =
  ## Expected number of times each position is visited, starting from
  ## `start`, before the encounter ends (stop or finish).
  let n = g.states.len
  let eps = g.params.stopChance
  let flowFrom = flows(g, sol)
  result = newSeq[float](n)
  var cur = newSeq[float](n)
  cur[start] = 1.0
  for step in 0 ..< 1_000_000:
    var nxt = newSeq[float](n)
    var mass = 0.0
    for s in 0 ..< n:
      let c = cur[s]
      if c == 0.0: continue
      result[s] += c
      for (t, p) in flowFrom[s]:
        nxt[t] += c * (1.0 - eps) * p
    for x in nxt: mass += x
    cur = nxt
    if mass < tol: break

proc fightStats*(g: Game, sol: Solution, start = -1): FightStats =
  let s0 = if start < 0: int(g.start) else: start
  let eps = g.params.stopChance
  let visits = occupancy(g, sol, s0)
  for s in 0 ..< g.states.len:
    let nv = visits[s]
    if nv < 1e-14: continue
    let st = g.states[s]
    result.timeIn[st.pos] += nv
    result.stopped += eps * nv
    result.stopValue += eps * nv * g.stopValue[s]
    let play = (1.0 - eps) * nv
    result.beats += play
    let m = g.nActs(wA, s)
    let k = g.nActs(wB, s)
    let oa = int(g.actOff[wA][s])
    let ob = int(g.actOff[wB][s])
    for i in 0 ..< m:
      result.uses[wA][g.act(wA, s, i)] += play * sol.strat[wA][oa + i]
    for j in 0 ..< k:
      result.uses[wB][g.act(wB, s, j)] += play * sol.strat[wB][ob + j]
    for i in 0 ..< m:
      let xi = sol.strat[wA][oa + i]
      if xi <= 0.0: continue
      for j in 0 ..< k:
        let yj = sol.strat[wB][ob + j]
        if yj <= 0.0: continue
        let w = play * xi * yj
        let acts = [wA: g.act(wA, s, i), wB: g.act(wB, s, j)]
        let c = Ctx(s: st, act: acts, d: g.dims, mode: g.mode)
        for o in resolve(g.params, st, acts[wA], acts[wB], g.dims, g.mode, detailed = true):
          let wp = w * o.p
          if o.target < 0: result.finishes[toTerminal(o.target)] += wp
          for who in Who:
            for t in o.tags[who]:
              result.events[who][t] += wp
            if etLanded in o.tags[who]:
              let a = acts[who]
              result.landed[who][a] += wp
              let z = if c.s.f[who.other].cond == cStunned or st.pos.isDown(who.other):
                        tech[a].downZone else: tech[a].zone
              result.zoneHits[who][z] += wp
  result.valueA = result.stopValue
  for t in Terminal: result.valueA += result.finishes[t] * terminalValue(t)

proc accuracy*(st: FightStats, w: Who, a: Action): float =
  if st.uses[w][a] > 0: st.landed[w][a] / st.uses[w][a] else: 0.0

proc strikeAccuracy*(st: FightStats, w: Who): (float, float, float) =
  ## (attempted, landed, accuracy) over all strikes except counters (a
  ## counter is only thrown when there is something to counter)
  var att, lan = 0.0
  for a in Strikes - {aCounter}:
    att += st.uses[w][a]
    lan += st.landed[w][a]
  (att, lan, (if att > 0: lan / att else: 0.0))

proc takedownAccuracy*(st: FightStats, w: Who): (float, float, float) =
  let att = st.uses[w][aShoot]
  let ok = st.events[w][etTakedown]
  (att, ok, (if att > 0: ok / att else: 0.0))

proc positionGroups*(st: FightStats): seq[(string, float)] =
  var total = 0.0
  for p in Pos: total += st.timeIn[p]
  var g = initOrderedTable[string, float]()
  for p in Pos:
    let k = if p in StandingPositions: "standing apart"
            elif p in ClinchPositions: "clinch"
            elif p in BehindPositions: "held from behind"
            elif p in OverPositions: "one down"
            else: "ground"
    g.mgetOrPut(k, 0.0) += st.timeIn[p] / max(total, 1e-300)
  for k, v in g: result.add (k, v)

proc pct*(x: float): string = $int(round(100.0 * x)) & "%"

proc pct1*(x: float): string = formatFloat(100.0 * x, ffDecimal, 1) & "%"

proc outcomeLine*(g: Game, st: FightStats): string =
  case g.mode
  of mSelfDefense:
    &"You escape {pct1(st.finishes[tAEscape])}, incapacitate them {pct1(st.finishes[tAKO])}, " &
    &"choke them {pct1(st.finishes[tASub])} | you are incapacitated {pct1(st.finishes[tBKO])}, " &
    &"choked {pct1(st.finishes[tBSub])} | ends without a finish {pct1(st.stopped)}"
  of mSport:
    &"KO/TKO {pct1(st.finishes[tAKO] + st.finishes[tBKO])}   submission " &
    &"{pct1(st.finishes[tASub] + st.finishes[tBSub])}   decision {pct1(st.stopped)}"

proc usesLine*(st: FightStats, who: Who, limit = 14): string =
  var used: seq[(float, Action)]
  for a in Action:
    if st.uses[who][a] > 1e-4: used.add (st.uses[who][a], a)
  used.sort(proc(x, y: (float, Action)): int = cmp(y[0], x[0]))
  var parts: seq[string]
  for i, (u, a) in used:
    if i >= limit: break
    var s = &"{a.name} {u:.2f}"
    if a in Strikes - {aCounter} and u > 0: s &= " (" & pct(st.accuracy(who, a)) & " land)"
    parts.add s
  parts.join(", ")

proc zonesLine*(st: FightStats, who: Who): string =
  var z: seq[(float, VulnerabilityZone)]
  for zone in VulnerabilityZone:
    if st.zoneHits[who][zone] > 1e-4: z.add (st.zoneHits[who][zone], zone)
  z.sort(proc(x, y: (float, VulnerabilityZone)): int = cmp(y[0], x[0]))
  var parts: seq[string]
  for (h, zone) in z: parts.add &"{zone.zoneName} {h:.2f}"
  parts.join(", ")

proc report*(g: Game, sol: Solution, st: FightStats): string =
  var lines: seq[string]
  lines.add "Outcome          " & outcomeLine(g, st)
  lines.add &"Length           {st.beats:.1f} beats on average"
  var where: seq[string]
  for (k, v) in positionGroups(st): where.add k & " " & pct(v)
  lines.add "Time spent       " & where.join(", ")
  for who in Who:
    let (att, lan, acc) = strikeAccuracy(st, who)
    let label = if g.mode == mSelfDefense: (if who == wA: "You     " else: "Attacker") else: "Fighter " & $who
    lines.add &"{label}: strikes {att:.2f} thrown, {lan:.2f} landed ({pct(acc)}); " &
              &"stuns {st.events[who][etStunned]:.2f}, leg injuries {st.events[who][etLegs]:.2f}, " &
              &"knockdowns {st.events[who][etKnockdown]:.2f}, takedowns {st.events[who][etTakedown]:.2f}"
    lines.add "  uses per encounter: " & usesLine(st, who)
    let zl = zonesLine(st, who)
    if zl.len > 0: lines.add "  targets hit: " & zl
  lines.join("\n")
