## Equilibrium of the fight game (Shapley value iteration) and a certificate
## of how close the computed strategies are to a true equilibrium.
##
## Value of a position s, as P(A wins):
##
##   V(s) = stop * decision(s) + (1 - stop) * val( M_s(V) )
##   M_s(V)[i][j] = sum over outcomes o of P(o | s, i, j) * U(o)
##
## where val() is the value of the zero-sum matrix game (A maximises, B
## minimises) and U(o) is V of the next position or 1 / 0 / 0.5 for an A win,
## B win or draw. The per-beat stop chance makes the operator a contraction,
## so the iteration converges to the unique solution from any start.
##
## Certificate: freezing A's computed mixed strategy, B's best response gives
## the value A is *guaranteed* (floor); freezing B's, A's best response gives
## the most A can get (ceiling). floor <= true value <= ceiling, and
## ceiling - floor is the exploitability of the computed strategy pair.

import std/[times, strformat]
import core, game, matrix_game

type
  Solution* = object
    value*: seq[float]              ## id -> P(A wins) under optimal play
    strat*: array[Who, seq[float]]  ## mixed strategies, indexed like g.acts
    sweeps*: int                    ## exact sweeps (one LP per position)
    evalSweeps*: int                ## cheap sweeps with frozen strategies
    residual*: float                ## last sweep's largest change
    floorStart*, ceilingStart*: float
    exploitability*: float          ## ceiling - floor at the start position
    worstExploitability*: float     ## largest ceiling - floor over all positions
    maxGap*: float                  ## largest duality gap of any matrix game
    seconds*: float

proc utility(g: Game, v: seq[float], t: int32): float {.inline.} =
  if t >= 0: v[t] else: terminalValue(toTerminal(t))

proc pairValue(g: Game, v: seq[float], pair: int): float {.inline.} =
  for k in g.outOff[pair] ..< g.outOff[pair + 1]:
    result += g.prob[k] * utility(g, v, g.target[k])

proc fillMatrix(g: Game, v: seq[float], s: int, M: var Matrix): (int, int) =
  let m = g.nActs(wA, s)
  let n = g.nActs(wB, s)
  var pair = int(g.pairOff[s])
  for i in 0 ..< m:
    for j in 0 ..< n:
      M[i][j] = pairValue(g, v, pair)
      inc pair
  (m, n)

type
  Support = object
    ## Sparse "which action pairs are actually played, with what weight".
    off: seq[int32]
    pair: seq[int32]
    w: seq[float]

proc evalSweep(g: Game, v: var seq[float], sup: Support): float =
  ## One Gauss-Seidel sweep with both strategies frozen.
  let eps = g.params.stopChance
  for s in 0 ..< g.states.len:
    var acc = 0.0
    for k in sup.off[s] ..< sup.off[s + 1]:
      acc += sup.w[k] * pairValue(g, v, int(sup.pair[k]))
    let nv = eps * g.stopValue[s] + (1.0 - eps) * acc
    result = max(result, abs(nv - v[s]))
    v[s] = nv

proc supportOf(g: Game, x, y: seq[float]): Support =
  result.off.add 0'i32
  for s in 0 ..< g.states.len:
    let m = g.nActs(wA, s)
    let k = g.nActs(wB, s)
    let oa = int(g.actOff[wA][s])
    let ob = int(g.actOff[wB][s])
    for i in 0 ..< m:
      let xi = x[oa + i]
      if xi <= 1e-15: continue
      for j in 0 ..< k:
        let yj = y[ob + j]
        if yj <= 1e-15: continue
        result.pair.add int32(g.pairIndex(s, i, j))
        result.w.add xi * yj
    result.off.add int32(result.pair.len)

proc solveGame*(g: Game, tol = 1e-10, maxSweeps = 200_000,
                evalSweeps = 25, verbose = false): Solution =
  ## Shapley value iteration, accelerated: after every exact sweep (an LP per
  ## position) the strategies are frozen for a few cheap sweeps that only
  ## touch the action pairs actually played. Freezing mixed strategies for too
  ## long can overshoot and oscillate, so whenever an exact sweep fails to
  ## make progress the number of cheap sweeps is halved, down to plain value
  ## iteration. Termination is always decided on an exact sweep with the
  ## standard contraction bound, and `certify` checks the result independently.
  let t0 = epochTime()
  let n = g.states.len
  let eps = g.params.stopChance
  result.value = g.stopValue
  for w in Who: result.strat[w] = newSeq[float](g.acts[w].len)
  var M: Matrix
  let factor = if eps > 0: (1.0 - eps) / eps else: 1e12
  var fast = evalSweeps
  var bestDelta = Inf
  var noProgress = 0
  while result.sweeps < maxSweeps:
    inc result.sweeps
    var delta = 0.0
    var maxGap = 0.0
    for s in 0 ..< n:
      let (m, k) = fillMatrix(g, result.value, s, M)
      let sol = solveMatrixGame(M, m, k)
      maxGap = max(maxGap, sol.gap)
      let nv = eps * g.stopValue[s] + (1.0 - eps) * sol.value
      delta = max(delta, abs(nv - result.value[s]))
      result.value[s] = nv
      let oa = int(g.actOff[wA][s])
      let ob = int(g.actOff[wB][s])
      for i in 0 ..< m: result.strat[wA][oa + i] = sol.x[i]
      for j in 0 ..< k: result.strat[wB][ob + j] = sol.y[j]
    result.residual = delta
    result.maxGap = maxGap
    if verbose:
      echo &"  exact sweep {result.sweeps:>4}  max change {delta:.3e}  fast sweeps {fast}"
    if delta * factor < tol: break
    if delta < 0.95 * bestDelta:
      bestDelta = delta
      noProgress = 0
    else:
      inc noProgress
      if noProgress >= 3 and fast > 0:
        fast = fast div 2
        noProgress = 0
    if fast > 0:
      let sup = supportOf(g, result.strat[wA], result.strat[wB])
      for k in 1 .. fast:
        inc result.evalSweeps
        if evalSweep(g, result.value, sup) * factor < tol * 0.01: break
  result.seconds = epochTime() - t0

proc bestResponseValues*(g: Game, strat: seq[float], fixed: Who,
                         tol = 1e-11, maxRounds = 100_000,
                         evalSweeps = 60): seq[float] =
  ## Values when `fixed` plays `strat` and the other fighter best-responds
  ## (policy iteration on the resulting one-player problem). For fixed = A
  ## this is what A's strategy guarantees (a floor on the true value); for
  ## fixed = B it is the most A can extract against B's strategy (a ceiling).
  let n = g.states.len
  let eps = g.params.stopChance
  let factor = if eps > 0: (1.0 - eps) / eps else: 1e12
  let responder = fixed.other
  result = g.stopValue
  var choice = newSeq[int](n)
  for round in 0 ..< maxRounds:
    var delta = 0.0
    for s in 0 ..< n:
      let m = g.nActs(wA, s)
      let k = g.nActs(wB, s)
      let base = int(g.pairOff[s])
      let off = int(g.actOff[fixed][s])
      var best = if fixed == wA: Inf else: -Inf
      var bestIdx = 0
      let nr = if responder == wA: m else: k
      let nf = if fixed == wA: m else: k
      for r in 0 ..< nr:
        var e = 0.0
        for f in 0 ..< nf:
          let pf = strat[off + f]
          if pf <= 0.0: continue
          let pair = if fixed == wA: base + f * k + r else: base + r * k + f
          e += pf * pairValue(g, result, pair)
        if (fixed == wA and e < best) or (fixed == wB and e > best):
          best = e
          bestIdx = r
      choice[s] = bestIdx
      let nv = eps * g.stopValue[s] + (1.0 - eps) * best
      delta = max(delta, abs(nv - result[s]))
      result[s] = nv
    if delta * factor < tol: break
    # Evaluate the current best-response policy before improving again.
    var sup: Support
    sup.off.add 0'i32
    for s in 0 ..< n:
      let k = g.nActs(wB, s)
      let off = int(g.actOff[fixed][s])
      let base = int(g.pairOff[s])
      let nf = g.nActs(fixed, s)
      for f in 0 ..< nf:
        let pf = strat[off + f]
        if pf <= 1e-15: continue
        let pair = if fixed == wA: base + f * k + choice[s] else: base + choice[s] * k + f
        sup.pair.add int32(pair)
        sup.w.add pf
      sup.off.add int32(sup.pair.len)
    for it in 1 .. evalSweeps:
      if evalSweep(g, result, sup) * factor < tol * 0.01: break

proc certify*(g: Game, sol: var Solution) =
  ## Fill in the best-response floor/ceiling and exploitability.
  let floorV = bestResponseValues(g, sol.strat[wA], wA)
  let ceilV = bestResponseValues(g, sol.strat[wB], wB)
  sol.floorStart = floorV[g.start]
  sol.ceilingStart = ceilV[g.start]
  sol.exploitability = sol.ceilingStart - sol.floorStart
  sol.worstExploitability = 0.0
  for s in 0 ..< g.states.len:
    sol.worstExploitability = max(sol.worstExploitability, ceilV[s] - floorV[s])

proc solveAndCertify*(g: Game, tol = 1e-10, verbose = false): Solution =
  result = solveGame(g, tol, verbose = verbose)
  certify(g, result)

proc mix*(g: Game, sol: Solution, w: Who, s: int): seq[(Action, float)] =
  let off = int(g.actOff[w][s])
  for i in 0 ..< g.nActs(w, s):
    result.add (g.act(w, s, i), sol.strat[w][off + i])

proc startValue*(g: Game, sol: Solution): float = sol.value[g.start]
