## What optimal play looks like: how fights end, where they are fought, which
## techniques get used and how often they land. Everything is computed
## exactly from the solved strategies (expected values over the Markov chain
## they induce), not by sampling.

import std/[algorithm, math, strformat, strutils, tables]
import core, params, rules, game, solve

type
  FightStats* = object
    beats*: float                          ## expected beats played
    decision*: float                       ## P(stopped -> decision)
    decisionWinA*: float                   ## P(A wins on the cards)
    finishes*: array[Terminal, float]      ## P(fight ends this way)
    winA*: float                           ## total P(A wins), = start value
    uses*: array[Who, array[Action, float]]    ## expected times each action is chosen
    events*: array[Who, array[EventTag, float]] ## expected count of each event
    landed*: array[Who, array[Action, float]]   ## expected landed strikes per technique
    timeIn*: array[Pos, float]             ## expected beats spent in each position

proc occupancy*(g: Game, sol: Solution, tol = 1e-12): seq[float] =
  ## Expected number of times each position is visited, starting from the
  ## opening, before the fight ends (stop or finish).
  let n = g.states.len
  let eps = g.params.stopChance
  # Expected next-state flow under the equilibrium mix, support pairs only.
  var flowFrom: seq[seq[(int32, float)]] = newSeq[seq[(int32, float)]](n)
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
    for t, p in acc: flowFrom[s].add (t, p)
  result = newSeq[float](n)
  var cur = newSeq[float](n)
  cur[g.start] = 1.0
  # Sum of the visit distribution over time (geometric series).
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

proc fightStats*(g: Game, sol: Solution): FightStats =
  let eps = g.params.stopChance
  let visits = occupancy(g, sol)
  for s in 0 ..< g.states.len:
    let nv = visits[s]
    if nv < 1e-14: continue
    let st = g.states[s]
    result.timeIn[st.pos] += nv
    result.decision += eps * nv
    result.decisionWinA += eps * nv * g.stopValue[s]
    let play = (1.0 - eps) * nv
    result.beats += play
    let m = g.nActs(wA, s)
    let k = g.nActs(wB, s)
    let oa = int(g.actOff[wA][s])
    let ob = int(g.actOff[wB][s])
    for i in 0 ..< m:
      let xi = sol.strat[wA][oa + i]
      result.uses[wA][g.act(wA, s, i)] += play * xi
    for j in 0 ..< k:
      let yj = sol.strat[wB][ob + j]
      result.uses[wB][g.act(wB, s, j)] += play * yj
    for i in 0 ..< m:
      let xi = sol.strat[wA][oa + i]
      if xi <= 0.0: continue
      for j in 0 ..< k:
        let yj = sol.strat[wB][ob + j]
        if yj <= 0.0: continue
        let w = play * xi * yj
        let acts = [wA: g.act(wA, s, i), wB: g.act(wB, s, j)]
        for o in resolve(g.params, st, acts[wA], acts[wB], g.dims, detailed = true):
          let wp = w * o.p
          if o.target < 0: result.finishes[toTerminal(o.target)] += wp
          for who in Who:
            for t in o.tags[who]:
              result.events[who][t] += wp
            if etLanded in o.tags[who]:
              result.landed[who][acts[who]] += wp
  result.winA = result.decisionWinA + result.finishes[tAKO] + result.finishes[tASub] +
                0.5 * result.finishes[tDraw]

proc accuracy*(st: FightStats, w: Who, a: Action): float =
  if st.uses[w][a] > 0: st.landed[w][a] / st.uses[w][a] else: 0.0

proc strikeAccuracy*(st: FightStats, w: Who): (float, float, float) =
  ## (attempted, landed, accuracy) over all strikes
  var att, lan = 0.0
  for a in Strikes:
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
    let k = if p in StandingPositions: "standing"
            elif p in ClinchPositions: "clinch"
            elif p in OverPositions: "one down"
            else: "ground"
    g.mgetOrPut(k, 0.0) += st.timeIn[p] / max(total, 1e-300)
  for k, v in g: result.add (k, v)

proc pct*(x: float): string = $int(round(100.0 * x)) & "%"

proc report*(g: Game, sol: Solution, st: FightStats, who = wA): string =
  var lines: seq[string]
  let finishKO = st.finishes[tAKO] + st.finishes[tBKO]
  let finishSub = st.finishes[tASub] + st.finishes[tBSub]
  lines.add &"How fights end   KO/TKO {100*finishKO:5.1f}%   submission {100*finishSub:5.1f}%   decision {100*st.decision:5.1f}%   double KO {100*st.finishes[tDraw]:4.2f}%"
  lines.add &"A wins           {100*st.winA:5.1f}%  (KO {100*st.finishes[tAKO]:.1f}%, sub {100*st.finishes[tASub]:.1f}%, decision {100*st.decisionWinA:.1f}%)"
  lines.add &"Fight length     {st.beats:.1f} beats on average"
  var where: seq[string]
  for (k, v) in positionGroups(st): where.add k & " " & pct(v)
  lines.add "Time spent       " & where.join(", ")
  let (att, lan, acc) = strikeAccuracy(st, who)
  let (tda, tdo, tdacc) = takedownAccuracy(st, who)
  lines.add &"Fighter {who}: strikes {att:.1f} thrown, {lan:.1f} landed ({pct(acc)}); takedowns {tdo:.2f}/{tda:.2f} ({pct(tdacc)})"
  var used: seq[(float, Action)]
  for a in Action:
    if st.uses[who][a] > 1e-6: used.add (st.uses[who][a], a)
  used.sort(proc(x, y: (float, Action)): int = cmp(y[0], x[0]))
  var parts: seq[string]
  for (u, a) in used:
    var s = &"{a.name} {u:.2f}"
    if a in Strikes and u > 0: s &= " (" & pct(st.accuracy(who, a)) & " land)"
    parts.add s
  lines.add &"Fighter {who} uses per fight: " & parts.join(", ")
  lines.join("\n")
