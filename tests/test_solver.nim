## The equilibrium solver: a hand-built game with a known value, the
## symmetric sport game, certificates, exact statistics, and the zero-sum
## property that removing an option can never help.

import std/[unittest, math]
import solver/[core, params, game, solve, analysis, studies]

const small = Dims(damageLevels: 2)

proc handBuilt(eps, decision: float): Game =
  ## One position; A and B each pick heads or tails. A match ends the game
  ## with A winning, a mismatch with B winning. With a stop chance `eps` that
  ## pays `decision`, the value is eps * decision + (1 - eps) * 1/2.
  result.dims = small
  result.params = defaultParams()
  result.params.stopChance = eps
  result.states = @[State(pos: pLong)]
  result.actOff = [@[0'i32, 2], @[0'i32, 2]]
  result.acts = [@[aJab, aCross], @[aJab, aCross]]
  result.pairOff = @[0'i32, 4]
  result.outOff = @[0'i32, 1, 2, 3, 4]
  result.target = @[terminalCode(tAKO), terminalCode(tBKO), terminalCode(tBKO), terminalCode(tAKO)]
  result.prob = @[1.0, 1.0, 1.0, 1.0]
  result.stopValue = @[decision]

suite "solver":
  test "hand-built game: value and strategies are exact":
    let g = handBuilt(0.1, 0.9)
    var sol = solveGame(g, 1e-12)
    certify(g, sol)
    check abs(sol.value[0] - (0.1 * 0.9 + 0.9 * 0.5)) < 1e-10
    check abs(sol.strat[wA][0] - 0.5) < 1e-9
    check abs(sol.strat[wB][0] - 0.5) < 1e-9
    check sol.exploitability < 1e-9

  test "symmetric sport game is worth exactly 1/2":
    let arsenal = findStyle("striker").arsenal
    let g = buildGame(defaultParams(), arsenal, arsenal, small, mSport)
    var sol = solveGame(g, 1e-11)
    certify(g, sol)
    check abs(sol.value[g.start] - 0.5) < 1e-9
    check sol.exploitability < 1e-8
    check sol.worstExploitability < 1e-8

  test "self-defense game: floor <= value <= ceiling, tight certificate":
    let g = buildGame(defaultParams(), findStyle("trained"), findStyle("grappler"), small,
                      mSelfDefense, [State(pos: pMid), State(pos: pMountB)])
    var sol = solveGame(g, 1e-11)
    certify(g, sol)
    check sol.floorStart <= sol.value[g.start] + 1e-9
    check sol.value[g.start] <= sol.ceilingStart + 1e-9
    check sol.exploitability < 1e-8
    for v in sol.value:
      check v >= -1e-12 and v <= 1.0 + 1e-12

  test "statistics are exact: outcomes sum to 1 and reproduce the value":
    let g = buildGame(defaultParams(), findStyle("trained"), findStyle("brawler"), small,
                      mSelfDefense, [State(pos: pClose)])
    let sol = solveGame(g, 1e-12)
    let st = fightStats(g, sol)
    var total = st.stopped
    for t in Terminal: total += st.finishes[t]
    check abs(total - 1.0) < 1e-8
    check abs(st.valueA - sol.value[g.start]) < 1e-8

  test "removing a defender's option never helps him":
    var st = defaultSetup("trained", "brawler")
    st.dims = small
    st.starts = @[State(pos: pMid), State(pos: pClinchB), State(pos: pBehindB)]
    st.tol = 1e-11
    let (base, rows) = ablate(st, @[("Teep", {aTeep}), ("Flee", {aFlee}),
                                    ("GroinKick", {aGroinKick}), ("Break-free tools", {aPummel, aThrow})])
    check base.len == 3
    for r in rows:
      for d in r.deltas:
        check d <= 1e-9

  test "giving the attacker an extra option never helps the defender":
    var st = defaultSetup("trained", "brawler")
    st.dims = small
    st.starts = @[State(pos: pMid)]
    st.tol = 1e-11
    let (g0, s0) = solveSetup(st)
    st.b = st.b + {aLowKick, aCross}
    let (g1, s1) = solveSetup(st)
    check s1.value[g1.start] <= s0.value[g0.start] + 1e-9

  test "hip loading matters: rotation-free strikes change the value":
    var st = defaultSetup("trained", "striker")
    st.dims = small
    st.starts = @[State(pos: pMid)]
    let (on, off) = hipLoadingValue(st)
    check abs(on[0] - off[0]) > 1e-6
