## Parameters (JSON round trip, perturbation, families) and the playbook's
## scoring identities.

import std/[unittest, json, sets, strutils]
import solver/[core, params, game, solve, studies, playbook, deep]

const small = Dims(damageLevels: 2)

suite "parameters":
  test "JSON round trip reproduces every parameter":
    let p = defaultParams()
    var q = defaultParams()
    q.forceScale = 0.1
    q.applyJson(p.toJson)
    for name in p.paramNames(includeZero = true):
      check p.getParam(name) == q.getParam(name)

  test "unknown keys are rejected":
    var p = defaultParams()
    expect KeyError:
      p.applyJson(%*{"forceScal": 1.0})
    expect KeyError:
      p.applyJson(%*{"hitMid": {"Jabb": 0.5}})

  test "perturbing keeps probabilities in [0, 1] but not multipliers":
    let p = defaultParams()
    check p.perturbed("fleeBase", 3.0).fleeBase == 1.0
    check p.perturbed("angleAtk", 3.0).angleAtk > 1.0
    check p.perturbed("force.Cross", 2.0).force[aCross] == 1600.0

  test "every parameter belongs to exactly one family":
    let p = defaultParams()
    var seen = initHashSet[string]()
    for (fam, members) in paramFamilies:
      for name in expandFamily(p, members):
        check name notin seen
        seen.incl name
    for name in p.paramNames:
      check name in seen

suite "playbook scoring":
  setup:
    var st = defaultSetup("trained", "brawler")
    st.dims = small
    st.starts = @[State(pos: pMid), State(pos: pClinchB)]
    st.tol = 1e-12
    let (g, sol) = solveSetup(st)

  test "the best response's expected score is the position's value":
    for s0 in st.starts:
      let s = g.stateId(s0)
      let r = responses(g, sol, s)
      check abs(r[0].expected - sol.value[s]) < 1e-9
      for x in r:
        check x.guaranteed <= x.expected + 1e-12

  test "no plan beats optimal play against an optimal attacker":
    let s = g.stateId(State(pos: pMid))
    for plan in [@[aTeep], @[aJab, aCross, aHook], @[aRetreat, aFlee], @[aGroinKick, aKnee]]:
      let c = scoreCombo(g, sol, s, plan, "test")
      check c.expected <= sol.value[s] + 1e-9
      check c.guaranteed <= c.expected + 1e-9
      check c.executed >= 0.0 and c.executed <= 1.0 + 1e-9

  test "an all-optimal one-step plan scores exactly the value":
    let s = g.stateId(State(pos: pMid))
    let r = responses(g, sol, s)
    let c = scoreCombo(g, sol, s, @[r[0].action], "test")
    check abs(c.expected - sol.value[s]) < 1e-9

  test "discovered combinations respect the execution threshold":
    let s = g.stateId(State(pos: pMid))
    for c in discoverCombos(g, sol, s, maxLen = 2):
      check c.executed >= 0.25 - 1e-12

suite "deep analysis":
  setup:
    var st = defaultSetup("trained", "brawler")
    st.dims = small
    st.starts = scenarioStates()
    st.tol = 1e-12
    let (g, sol) = solveSetup(st)

  test "exhaustive search finds everything the beam search finds":
    let s = g.stateId(State(pos: pMid))
    let beam = discoverCombos(g, sol, s, maxLen = 3)
    let ex = exhaustiveCombos(g, sol, s, maxLen = 3)
    check ex.evaluated > 0
    check ex.best.len > 0
    check ex.best[0].expected >= beam[0].expected - 1e-12
    for lst in [ex.best, ex.striking, ex.decisive]:
      for c in lst:
        check c.executed >= 0.25 - 1e-12
        check c.expected <= sol.value[s] + 1e-9
        check c.guaranteed <= c.expected + 1e-9
        check c.plan.len >= 2 and c.plan.len <= 3
    for c in ex.striking:
      for a in c.plan: check a in Strikes + {aPush}

  test "the exhaustive search scores the same as committing to the plan":
    let s = g.stateId(State(pos: pClose))
    let ex = exhaustiveCombos(g, sol, s, maxLen = 3)
    for c in ex.best:
      let again = scoreCombo(g, sol, s, c.plan, "check")
      check abs(again.expected - c.expected) < 1e-9
      check abs(again.executed - c.executed) < 1e-9
      check abs(again.finishedSafe - c.finishedSafe) < 1e-9

  test "the tablebase covers every reachable position":
    let tb = tablebase(g, sol)
    check tb["rows"].len == g.states.len
    for r in tb["rows"]:
      check r.len >= 12
      check r[9].getFloat >= 0.0 and r[9].getFloat <= 1.0

  test "unit specifications round-trip and have a stable key":
    let u = UnitSpec(kind: ukSummary, defender: "trained", attacker: "brawler",
                     removeA: @[aTeep], damageLevels: 2,
                     params: defaultParams().perturbed("fleeBase", 0.5))
    let back = parseUnit(u.toJson)
    check back.key == u.key
    check back.params.fleeBase == 0.3
    check back.removeA == @[aTeep]
    var other = u
    other.removeA = @[aFlee]
    check other.key != u.key
    let r = runUnit(u)
    check r["scenarios"].len == scenarios.len
    for sc in r["scenarios"]:
      check sc["top"][0][0].getStr != "Teep"      # removed from the arsenal
