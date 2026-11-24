## The self-defense playbook: a static, precomputed answer sheet.
##
## For each situation (scenario) and each kind of attacker it records, from
## the exact equilibrium of the game:
## - how safe you are with optimal play
## - every first response, scored two ways: against an attacker playing
##   optimally ("expected") and against the attacker's best reply this beat
##   ("guaranteed")
## - for each attack the attacker might open with, your best answers
## - the lines optimal play actually follows (most likely action sequences)
## - scored combinations: discovered by search, plus classic and documented
##   sequences, each scored vs an attacker playing optimally and vs an
##   attacker who reads the whole plan
## - what each weak point, way of generating force, and technique is worth
## - whether the top recommendation survives perturbing every family of
##   assumptions

import std/[algorithm, json, sequtils, sets, strformat, strutils, tables, times]
import core, params, rules, game, solve, analysis, studies

type
  Scenario* = object
    id*, title*, situation*: string
    state*: State

  ResponseScore* = object
    action*: Action
    expected*: float     ## vs the attacker's optimal mix, then optimal play
    guaranteed*: float   ## vs the attacker's best reply this beat, then optimal play
    mix*: float          ## how often optimal play chooses it

  AttackAnswer* = object
    attack*: Action
    attackerMix*: float  ## how often an optimal attacker opens with it here
    answers*: seq[(Action, float)]   ## best replies, value after this beat
    worst*: (Action, float)

  ComboScore* = object
    plan*: seq[Action]
    source*: string      ## "discovered", "classic", "document: ..."
    vsAttack*: string    ## attacker's committed first move, if any
    expected*: float     ## vs the attacker's optimal play
    guaranteed*: float   ## vs an attacker who knows the plan
    finishedSafe*: float ## P(you are safe before the plan is over)
    executed*: float     ## P(every step of the plan could be carried out)
    dealt*: float        ## expected damage levels dealt during the plan
    stuns*: float        ## expected stuns inflicted during the plan
    taken*: float        ## expected damage levels taken during the plan

  Line* = object
    actions*: seq[Action]
    prob*: float         ## P(optimal play follows this sequence)
    value*: float        ## P(safe | this line)
    finishedSafe*: float ## P(safe finish within the line | line)

  Robustness* = object
    checks*: int
    sameTop*: int
    displacedBy*: seq[(string, string)]  ## (perturbation, new top response)
    valueLow*, valueHigh*: float

  ScenarioReport* = object
    scenario*: Scenario
    value*: float
    outcome*: FightStats
    responses*: seq[ResponseScore]
    answers*: seq[AttackAnswer]
    lines*: seq[Line]
    combos*: seq[ComboScore]
    robustness*: Robustness

  MatchReport* = object
    defender*, attacker*: string
    states*, pairs*, outcomes*: int
    exploitability*: float
    seconds*: float
    scenarios*: seq[ScenarioReport]

const scenarios* = [
  Scenario(id: "distance", title: "Squared up at kicking range",
           situation: "The aggressor is a couple of steps away, both of you standing.",
           state: State(pos: pLong)),
  Scenario(id: "arms-length", title: "Aggressor at arm's length",
           situation: "Punching range: he can hit you and grab you.",
           state: State(pos: pMid)),
  Scenario(id: "in-your-face", title: "In your face",
           situation: "Chest to chest distance, not yet holding each other.",
           state: State(pos: pClose)),
  Scenario(id: "grabbed", title: "Grabbed (headlock / dominant grip)",
           situation: "He has hold of you with the better grip.",
           state: State(pos: pClinchB)),
  Scenario(id: "tied-up", title: "Tied up",
           situation: "You are holding each other, neither has the better grip.",
           state: State(pos: pClinch)),
  Scenario(id: "from-behind", title: "Grabbed from behind",
           situation: "Bear hug or rear choke attempt while standing.",
           state: State(pos: pBehindB)),
  Scenario(id: "knocked-down", title: "Down, attacker standing over you",
           situation: "You are on the ground; he is standing.",
           state: State(pos: pOverB)),
  Scenario(id: "tackled", title: "Tackled, attacker on top in your guard",
           situation: "On your back with your legs around him.",
           state: State(pos: pGuardB)),
  Scenario(id: "mounted", title: "Mounted",
           situation: "He is sitting on your chest.",
           state: State(pos: pMountB)),
  Scenario(id: "back-taken", title: "Back taken on the ground",
           situation: "He is behind you on the ground.",
           state: State(pos: pBackB)),
]

proc scenarioStates*(): seq[State] =
  for s in scenarios: result.add s.state

# ---------------------------------------------------------------------------
# Per-position quantities
# ---------------------------------------------------------------------------

proc continuation(g: Game, sol: Solution, s, i, j: int): float =
  ## Value after A plays i and B plays j at s (one beat), then optimal play.
  let pair = g.pairIndex(s, i, j)
  for o in g.outOff[pair] ..< g.outOff[pair + 1]:
    let t = g.target[o]
    result += g.prob[o] * (if t >= 0: sol.value[t] else: terminalValue(toTerminal(t)))

proc beatValue(g: Game, s: int, cont: float): float =
  let eps = g.params.stopChance
  eps * g.stopValue[s] + (1.0 - eps) * cont

proc responses*(g: Game, sol: Solution, s: int): seq[ResponseScore] =
  let m = g.nActs(wA, s)
  let k = g.nActs(wB, s)
  let ob = int(g.actOff[wB][s])
  let oa = int(g.actOff[wA][s])
  for i in 0 ..< m:
    var e = 0.0
    var worst = Inf
    for j in 0 ..< k:
      let c = continuation(g, sol, s, i, j)
      e += sol.strat[wB][ob + j] * c
      worst = min(worst, c)
    result.add ResponseScore(action: g.act(wA, s, i), expected: beatValue(g, s, e),
                             guaranteed: beatValue(g, s, worst),
                             mix: sol.strat[wA][oa + i])
  result.sort(proc(x, y: ResponseScore): int =
    let c = cmp(y.expected, x.expected)
    if c != 0: c else: cmp(y.guaranteed, x.guaranteed))

proc attackAnswers*(g: Game, sol: Solution, s: int, top = 3): seq[AttackAnswer] =
  let m = g.nActs(wA, s)
  let k = g.nActs(wB, s)
  let ob = int(g.actOff[wB][s])
  for j in 0 ..< k:
    let atk = g.act(wB, s, j)
    var rows: seq[(Action, float)]
    for i in 0 ..< m:
      rows.add (g.act(wA, s, i), beatValue(g, s, continuation(g, sol, s, i, j)))
    rows.sort(proc(x, y: (Action, float)): int = cmp(y[1], x[1]))
    var ans = AttackAnswer(attack: atk, attackerMix: sol.strat[wB][ob + j],
                           worst: rows[^1])
    for r in 0 ..< min(top, rows.len): ans.answers.add rows[r]
    result.add ans
  result.sort(proc(x, y: AttackAnswer): int = cmp(y.attackerMix, x.attackerMix))

# ---------------------------------------------------------------------------
# Lines: what optimal play actually does, as sequences
# ---------------------------------------------------------------------------

proc optimalLines*(g: Game, sol: Solution, s0: int, depth = 4,
                   minProb = 0.02, top = 6): seq[Line] =
  ## The defender's action sequences that optimal play follows, with their
  ## probabilities. A line is reported in its longest form unless it usually
  ## stops early (the encounter ended or the play branched).
  type Node = object
    actions: seq[Action]
    prob: float
    dist: Table[int, float]
    endedValue, endedSafe: float
  let eps = g.params.stopChance
  var frontier = @[Node(prob: 1.0, dist: {s0: 1.0}.toTable)]
  var found: seq[Line]
  for d in 1 .. depth:
    var next: seq[Node]
    for node in frontier:
      var children = initTable[Action, Node]()
      for s, m in node.dist:
        let mm = m * (1.0 - eps)
        let oa = int(g.actOff[wA][s])
        let ob = int(g.actOff[wB][s])
        for i in 0 ..< g.nActs(wA, s):
          let xi = sol.strat[wA][oa + i]
          if xi <= 1e-9: continue
          let a = g.act(wA, s, i)
          if a notin children:
            children[a] = Node(actions: node.actions & a)
          children[a].prob += mm * xi
          for j in 0 ..< g.nActs(wB, s):
            let yj = sol.strat[wB][ob + j]
            if yj <= 1e-12: continue
            let pair = g.pairIndex(s, i, j)
            for o in g.outOff[pair] ..< g.outOff[pair + 1]:
              let w = mm * xi * yj * g.prob[o]
              let t = g.target[o]
              if t < 0:
                children[a].endedValue += w * terminalValue(toTerminal(t))
                if winner(toTerminal(t)) == ord(wA): children[a].endedSafe += w
              else:
                children[a].dist.mgetOrPut(int(t), 0.0) += w
      for a, ch in children:
        if ch.prob < minProb: continue
        var v = ch.endedValue
        for s, m in ch.dist: v += m * sol.value[s]
        if d >= 2:
          found.add Line(actions: ch.actions, prob: ch.prob, value: v / ch.prob,
                         finishedSafe: ch.endedSafe / ch.prob)
        var cont = ch
        cont.endedValue = 0.0
        cont.endedSafe = 0.0
        next.add cont
    frontier = next
  proc key(l: Line): string = l.actions.mapIt(it.name).join(">")
  # drop a line when a longer line keeps at least 90% of its probability
  var longer = initTable[string, float]()
  for l in found:
    if l.actions.len >= 3:
      let pk = key(Line(actions: l.actions[0 .. ^2]))
      longer[pk] = max(longer.getOrDefault(pk, 0.0), l.prob)
  var kept: seq[Line]
  for l in found:
    if longer.getOrDefault(key(l), 0.0) >= 0.9 * l.prob: continue
    kept.add l
  kept.sort(proc(x, y: Line): int = cmp(y.prob, x.prob))
  for l in kept:
    result.add l
    if result.len >= top: break

# ---------------------------------------------------------------------------
# Planned combinations
# ---------------------------------------------------------------------------

proc planExpected*(g: Game, sol: Solution, s0: int, plan: seq[Action],
                   attackerFirst = -1): ComboScore =
  ## Commit to `plan` while the attacker plays his optimal strategy (opening
  ## with `attackerFirst` if given). A step that is not possible in the
  ## position reached breaks the plan; you then play optimally from there.
  ## Fills expected, finishedSafe, executed, dealt, stuns and taken.
  let eps = g.params.stopChance
  let dl = g.dims.damageLevels
  var dist = {s0: 1.0}.toTable
  for k, a in plan:
    var nd = initTable[int, float]()
    for s, m in dist:
      let i = g.actIndex(wA, s, a)
      if i < 0:
        result.expected += m * sol.value[s]
        continue
      result.expected += m * eps * g.stopValue[s]
      let mm = m * (1.0 - eps)
      let cur = g.states[s]
      let ob = int(g.actOff[wB][s])
      var fixed = -1
      if k == 0 and attackerFirst >= 0:
        fixed = g.actIndex(wB, s, Action(attackerFirst))
      for j in 0 ..< g.nActs(wB, s):
        let yj = if fixed >= 0: (if j == fixed: 1.0 else: 0.0) else: sol.strat[wB][ob + j]
        if yj <= 0.0: continue
        let pair = g.pairIndex(s, i, j)
        for o in g.outOff[pair] ..< g.outOff[pair + 1]:
          let w = mm * yj * g.prob[o]
          let t = g.target[o]
          if t < 0:
            let term = toTerminal(t)
            result.expected += w * terminalValue(term)
            if winner(term) == ord(wA): result.finishedSafe += w
            if term in {tAKO, tDraw}: result.dealt += w * float(dl - cur.f[wB].dmg)
            if term in {tBKO, tDraw}: result.taken += w * float(dl - cur.f[wA].dmg)
          else:
            let ns = g.states[t]
            result.dealt += w * float(ns.f[wB].dmg - cur.f[wB].dmg)
            result.taken += w * float(ns.f[wA].dmg - cur.f[wA].dmg)
            if ns.f[wB].cond == cStunned: result.stuns += w
            nd.mgetOrPut(int(t), 0.0) += w
    dist = nd
  for s, m in dist:
    result.expected += m * sol.value[s]
    result.executed += m
  result.executed += result.finishedSafe

proc planGuaranteed*(g: Game, sol: Solution, s0: int, plan: seq[Action],
                     attackerFirst = -1): float =
  ## Value of committing to `plan` against an attacker who knows it and picks
  ## his replies to make it fail (opening with `attackerFirst` if given).
  let eps = g.params.stopChance
  var memo = initTable[(int, int), float]()
  proc rec(s, k: int): float =
    if k >= plan.len: return sol.value[s]
    if (s, k) in memo: return memo[(s, k)]
    let i = g.actIndex(wA, s, plan[k])
    if i < 0:
      memo[(s, k)] = sol.value[s]
      return sol.value[s]
    var best = Inf
    let fixed = if k == 0 and attackerFirst >= 0: g.actIndex(wB, s, Action(attackerFirst)) else: -1
    for j in 0 ..< g.nActs(wB, s):
      if fixed >= 0 and j != fixed: continue
      let pair = g.pairIndex(s, i, j)
      var v = 0.0
      for o in g.outOff[pair] ..< g.outOff[pair + 1]:
        let t = g.target[o]
        v += g.prob[o] * (if t < 0: terminalValue(toTerminal(t)) else: rec(int(t), k + 1))
      best = min(best, v)
    result = eps * g.stopValue[s] + (1.0 - eps) * best
    memo[(s, k)] = result
  rec(s0, 0)

proc scoreCombo*(g: Game, sol: Solution, s0: int, plan: seq[Action], source: string,
                 attackerFirst = -1): ComboScore =
  result = planExpected(g, sol, s0, plan, attackerFirst)
  result.plan = plan
  result.source = source
  result.vsAttack = if attackerFirst >= 0: Action(attackerFirst).name else: ""
  result.guaranteed = planGuaranteed(g, sol, s0, plan, attackerFirst)

proc reachableActions(g: Game, sol: Solution, s0: int, plan: seq[Action]): set[Action] =
  ## Defender actions available in some position the plan can reach.
  var dist = initHashSet[int]()
  dist.incl s0
  for a in plan:
    var nd = initHashSet[int]()
    for s in dist:
      let i = g.actIndex(wA, s, a)
      if i < 0: continue
      for j in 0 ..< g.nActs(wB, s):
        let pair = g.pairIndex(s, i, j)
        for o in g.outOff[pair] ..< g.outOff[pair + 1]:
          if g.target[o] >= 0: nd.incl int(g.target[o])
    dist = nd
  for s in dist:
    for i in 0 ..< g.nActs(wA, s): result.incl g.act(wA, s, i)

proc discoverCombos*(g: Game, sol: Solution, s0: int, maxLen = 3, beam = 24,
                     top = 6, minExecuted = 0.25, strikesOnly = false,
                     attackerFirst = -1): seq[ComboScore] =
  ## Beam search over planned sequences, ranked by value against the
  ## attacker's optimal play, then by how often the combination ends the
  ## encounter in your favour, then by how often it can be carried out. A
  ## combination has to be executable in full at least `minExecuted` of the
  ## time; otherwise it is a plan for positions that rarely happen. With
  ## `strikesOnly` every step must be a strike or push. The (more expensive)
  ## value against an attacker who reads the plan is computed for the
  ## finalists only.
  let allowed = if strikesOnly: Strikes + {aPush} else: AllActions
  proc quick(plan: seq[Action]): ComboScore =
    result = planExpected(g, sol, s0, plan, attackerFirst)
    result.plan = plan
    result.source = if strikesOnly: "discovered (strikes)" else: "discovered"
    result.vsAttack = if attackerFirst >= 0: Action(attackerFirst).name else: ""
  proc better(x, y: ComboScore): int =
    if abs(x.expected - y.expected) >= 1e-6: return cmp(y.expected, x.expected)
    if abs(x.finishedSafe - y.finishedSafe) >= 1e-6: return cmp(y.finishedSafe, x.finishedSafe)
    cmp(y.executed, x.executed)
  var level: seq[ComboScore]
  for i in 0 ..< g.nActs(wA, s0):
    let a = g.act(wA, s0, i)
    if a in allowed: level.add quick(@[a])
  var all: seq[ComboScore]
  for d in 2 .. maxLen:
    level.keepItIf(it.executed >= minExecuted)
    level.sort(better)
    if level.len > beam: level.setLen(beam)
    var next: seq[ComboScore]
    for c in level:
      for a in reachableActions(g, sol, s0, c.plan) * allowed:
        next.add quick(c.plan & a)
    all.add next
    level = next
  all.keepItIf(it.executed >= minExecuted)
  all.sort(better)
  for c in all:
    var r = c
    r.guaranteed = planGuaranteed(g, sol, s0, c.plan, attackerFirst)
    result.add r
    if result.len >= top: break

# Classic and documented sequences, scored where they apply.
const namedCombos* = [
  # From biomechanical_movement_library.md, "SCENARIO: Haymaker Punch Attack"
  ("arms-length", "Haymaker", "document: evasion path (L-step, shovel hook, oblique kick, exit)",
   @[aSlip, aBodyHook, aObliqueKick, aFlee]),
  ("arms-length", "Haymaker", "document: deflection path (tan sao, chain punch, control, knee)",
   @[aParry, aJab, aGrab, aKnee]),
  ("arms-length", "Haymaker", "document: interception path (stop kick, whip hand, exit)",
   @[aObliqueKick, aFingerJab, aFlee]),
  # Rotation chaining: the second strike uses the side the first one loaded
  ("arms-length", "", "classic: jab, cross, hook (hips reload each time)",
   @[aJab, aCross, aHook]),
  ("arms-length", "", "rotation: cross then hook (lead side loaded by the cross)",
   @[aCross, aHook]),
  ("arms-length", "", "rotation: cross then cross (second from the unwound side)",
   @[aCross, aCross]),
  ("in-your-face", "", "weak points: knee to the groin, knee to the bent-over head, back off, run",
   @[aKnee, aKnee, aRetreat, aFlee]),
  ("in-your-face", "", "rotation: lead hook to the liver, rear cross to the jaw",
   @[aBodyHook, aCross]),
  ("arms-length", "", "weak points: eye jab, groin kick, run",
   @[aFingerJab, aGroinKick, aFlee]),
  ("distance", "", "stop kick to the knee, then run",
   @[aObliqueKick, aFlee]),
  ("from-behind", "", "loosen the hold: stomp, elbow, turn",
   @[aStomp, aElbow, aTurn]),
  ("grabbed", "", "knee the groin, then break away",
   @[aKnee, aBreak]),
]

# ---------------------------------------------------------------------------
# Whole report
# ---------------------------------------------------------------------------

proc topResponse*(g: Game, sol: Solution, s: int): (Action, float) =
  let r = responses(g, sol, s)
  (r[0].action, r[0].expected)

proc analyseMatch*(base: Setup, defender, attacker: string,
                   robustness = true, progress = false): MatchReport =
  let t0 = epochTime()
  var st = base
  st.a = findStyle(defender).arsenal
  st.b = findStyle(attacker).arsenal
  st.starts = scenarioStates()
  let g = build(st)
  var sol = solveGame(g, st.tol)
  certify(g, sol)
  result = MatchReport(defender: defender, attacker: attacker, states: g.states.len,
                       pairs: g.pairCount, outcomes: g.outcomeCount,
                       exploitability: max(0.0, sol.worstExploitability))
  if progress: stderr.writeLine &"  {defender} vs {attacker}: solved {g.states.len} positions"
  for sc in scenarios:
    let s = g.stateId(sc.state)
    var rep = ScenarioReport(scenario: sc, value: sol.value[s])
    rep.outcome = fightStats(g, sol, s)
    rep.responses = responses(g, sol, s)
    rep.answers = attackAnswers(g, sol, s)
    rep.lines = optimalLines(g, sol, s)
    rep.combos = discoverCombos(g, sol, s)
    rep.combos.add discoverCombos(g, sol, s, top = 4, strikesOnly = true)
    for (sid, atk, label, plan) in namedCombos:
      if sid != sc.id: continue
      var af = -1
      if atk.len > 0:
        let a = parseAction(atk)
        if g.actIndex(wB, s, a) < 0: continue    # this attacker never does that
        af = ord(a)
      rep.combos.add scoreCombo(g, sol, s, plan, label, af)
    rep.robustness = Robustness(valueLow: rep.value, valueHigh: rep.value)
    result.scenarios.add rep
  if robustness:
    let tops = block:
      var t: seq[Action]
      for r in result.scenarios: t.add r.responses[0].action
      t
    for (fam, members) in paramFamilies:
      if fam == "sport only": continue
      for factor in [0.75, 1.25]:
        var st2 = st
        st2.params = perturbFamily(st.params, members, factor)
        let g2 = build(st2)
        let sol2 = solveGame(g2, st.tol)
        let label = &"{fam} x{factor:.2f}"
        for k, sc in scenarios:
          let s2 = g2.stateId(sc.state)
          let (top2, _) = topResponse(g2, sol2, s2)
          let r2 = responses(g2, sol2, s2)
          var rb = result.scenarios[k].robustness
          inc rb.checks
          # same top, or the old top is still within half a point of the best
          var oldScore = -1.0
          for r in r2:
            if r.action == tops[k]: oldScore = r.expected
          if top2 == tops[k] or oldScore >= r2[0].expected - 0.005:
            inc rb.sameTop
          else:
            rb.displacedBy.add (label, top2.name)
          rb.valueLow = min(rb.valueLow, sol2.value[s2])
          rb.valueHigh = max(rb.valueHigh, sol2.value[s2])
          result.scenarios[k].robustness = rb
        if progress: stderr.writeLine &"    robustness: {label}"
  result.seconds = epochTime() - t0

# ---------------------------------------------------------------------------
# Body and mechanics: what is each weak point / force type worth?
# ---------------------------------------------------------------------------

type
  WorthTable* = object
    title*: string
    defender*, attacker*: string
    baseline*: seq[float]          ## per scenario
    rows*: seq[AblationRow]
    hipOn*, hipOff*: seq[float]

proc worth*(base: Setup, defender, attacker: string, groups: seq[(string, set[Action])],
            withHip = false, progress = false): WorthTable =
  var st = base
  st.a = findStyle(defender).arsenal
  st.b = findStyle(attacker).arsenal
  st.starts = scenarioStates()
  let (b, rows) = ablate(st, groups, progress)
  result = WorthTable(defender: defender, attacker: attacker, baseline: b, rows: rows)
  if withHip:
    let (on, off) = hipLoadingValue(st)
    result.hipOn = on
    result.hipOff = off

# ---------------------------------------------------------------------------
# JSON
# ---------------------------------------------------------------------------

proc `%`*(a: Action): JsonNode = %a.name

proc toJson*(r: ScenarioReport): JsonNode =
  var resp = newJArray()
  for x in r.responses:
    resp.add %*{"action": x.action, "expected": x.expected, "guaranteed": x.guaranteed, "mix": x.mix}
  var ans = newJArray()
  for a in r.answers:
    var best = newJArray()
    for (act, v) in a.answers: best.add %*{"action": act, "value": v}
    ans.add %*{"attack": a.attack, "attackerMix": a.attackerMix, "best": best,
               "worst": {"action": a.worst[0], "value": a.worst[1]}}
  var lines = newJArray()
  for l in r.lines:
    lines.add %*{"actions": l.actions, "prob": l.prob, "value": l.value, "finishedSafe": l.finishedSafe}
  var combos = newJArray()
  for c in r.combos:
    combos.add %*{"plan": c.plan, "source": c.source, "vsAttack": c.vsAttack,
                  "expected": c.expected, "guaranteed": c.guaranteed,
                  "finishedSafe": c.finishedSafe, "executed": c.executed,
                  "dealt": c.dealt, "stuns": c.stuns, "taken": c.taken}
  var disp = newJArray()
  for (lbl, top) in r.robustness.displacedBy: disp.add %*{"perturbation": lbl, "newTop": top}
  let o = r.outcome
  result = %*{
    "id": r.scenario.id, "title": r.scenario.title, "situation": r.scenario.situation,
    "position": r.scenario.state.pos.name, "safe": r.value,
    "outcome": {"escape": o.finishes[tAEscape], "incapacitate": o.finishes[tAKO],
                "choke": o.finishes[tASub], "incapacitated": o.finishes[tBKO],
                "choked": o.finishes[tBSub], "doubleKO": o.finishes[tDraw],
                "noFinish": o.stopped, "beats": o.beats},
    "responses": resp, "answers": ans, "lines": lines, "combos": combos,
    "robustness": {"checks": r.robustness.checks, "sameTop": r.robustness.sameTop,
                   "displacedBy": disp, "valueLow": r.robustness.valueLow,
                   "valueHigh": r.robustness.valueHigh}}

proc toJson*(m: MatchReport): JsonNode =
  var sc = newJArray()
  for r in m.scenarios: sc.add toJson(r)
  %*{"defender": m.defender, "attacker": m.attacker, "positions": m.states,
     "actionPairs": m.pairs, "outcomes": m.outcomes, "exploitability": m.exploitability,
     "seconds": m.seconds, "scenarios": sc}

proc toJson*(w: WorthTable): JsonNode =
  var rows = newJArray()
  for r in w.rows:
    var rem = newJArray()
    for a in r.removed: rem.add %a
    rows.add %*{"label": r.label, "removed": rem, "mean": r.mean, "perScenario": r.deltas}
  result = %*{"title": w.title, "defender": w.defender, "attacker": w.attacker,
              "baseline": w.baseline, "rows": rows}
  if w.hipOn.len > 0:
    result["hipLoading"] = %*{"on": w.hipOn, "off": w.hipOff}
