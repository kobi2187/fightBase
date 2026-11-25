## Deep analysis: no time budget.
##
## Every computation is a *unit* with a complete JSON specification. Its
## result is cached on disk under a hash of that specification, so a run
## that takes days can be interrupted and resumed, and repeated runs only
## compute what changed. The orchestrator runs units in parallel worker
## processes (`fightsolve unit`) on all cores, then aggregates:
##
## - full units: one per matchup. Every situation's responses, answers to
##   attacks, optimal lines (deep), exhaustive combination search, and the
##   complete tablebase (best responses at every reachable position).
## - one-at-a-time robustness: every parameter scaled by each spread.
## - joint robustness: many samples with *all* parameters perturbed at once
##   (log-normal noise), giving the probability that a recommendation holds.
## - discretisation: the same game on finer damage grids.
## - weapons: removing each technique, every pair of techniques (synergy),
##   each target zone, each way of generating force, and hip loading.

import std/[algorithm, hashes, json, math, os, osproc, random, sequtils, sets,
            strformat, strutils, tables, times]
import core, params, game, solve, analysis, studies, playbook

type
  UnitKind* = enum
    ukSummary = "summary"   ## values and top responses for every situation
    ukFull = "full"         ## everything for one matchup except exhaustive search
    ukCombos = "combos"     ## exhaustive combination search for one situation

  UnitSpec* = object
    kind*: UnitKind
    defender*, attacker*: string
    removeA*: seq[Action]
    damageLevels*: int
    params*: Params
    comboLength*: int
    minExecuted*: float
    lineDepth*: int
    scenario*: string        ## ukCombos: scenario id

  DeepConfig* = object
    exe*: string              ## path to the fightsolve binary
    cacheDir*, outDir*: string
    jobs*: int
    defenders*, attackers*: seq[string]
    comboLength*, lineDepth*: int
    minExecuted*: float
    spreads*: seq[float]      ## one-at-a-time factors, e.g. 0.5 0.75 1.25 1.5
    mcSamples*: int
    mcSigma*: float
    grids*: seq[int]          ## damage-level grids to re-solve on
    pairs*: bool              ## technique-pair ablations (synergy)
    seed*: int

proc defaultDeepConfig*(): DeepConfig =
  DeepConfig(exe: getAppFilename(), cacheDir: ".fightsolve-cache", outDir: "docs/playbook",
             jobs: countProcessors(), defenders: @["trained", "untrained"],
             attackers: @["brawler", "striker", "grappler"], comboLength: 6, lineDepth: 6,
             minExecuted: 0.25, spreads: @[0.5, 0.75, 1.25, 1.5], mcSamples: 300,
             mcSigma: 0.25, grids: @[6, 8], pairs: true, seed: 20261124)

# ---------------------------------------------------------------------------
# Units
# ---------------------------------------------------------------------------

proc toJson*(u: UnitSpec): JsonNode =
  result = %*{"kind": $u.kind, "defender": u.defender, "attacker": u.attacker,
              "removeA": u.removeA.mapIt(it.name), "damageLevels": u.damageLevels,
              "params": u.params.toJson}
  case u.kind
  of ukFull:
    result["lineDepth"] = %u.lineDepth
  of ukCombos:
    result["comboLength"] = %u.comboLength
    result["minExecuted"] = %u.minExecuted
    result["scenario"] = %u.scenario
  of ukSummary: discard

proc parseUnit*(j: JsonNode): UnitSpec =
  result.kind = case j["kind"].getStr
    of "full": ukFull
    of "combos": ukCombos
    else: ukSummary
  result.defender = j["defender"].getStr
  result.attacker = j["attacker"].getStr
  for a in j["removeA"]: result.removeA.add parseAction(a.getStr)
  result.damageLevels = j["damageLevels"].getInt
  result.params = defaultParams()
  result.params.applyJson(j["params"])
  result.comboLength = j{"comboLength"}.getInt(0)
  result.minExecuted = j{"minExecuted"}.getFloat(0.25)
  result.lineDepth = j{"lineDepth"}.getInt(4)
  result.scenario = j{"scenario"}.getStr("")

proc key*(u: UnitSpec): string =
  toHex(cast[uint64](hash($u.toJson)))

proc setupOf(u: UnitSpec): Setup =
  var removed: set[Action]
  for a in u.removeA: removed.incl a
  Setup(params: u.params, a: findStyle(u.defender).arsenal - removed,
        b: findStyle(u.attacker).arsenal, dims: Dims(damageLevels: u.damageLevels),
        mode: mSelfDefense, starts: scenarioStates(), tol: 1e-9)

proc summarise(g: Game, sol: Solution): JsonNode =
  var sc = newJArray()
  for s0 in scenarioStates():
    let s = g.stateId(s0)
    var top = newJArray()
    for i, r in responses(g, sol, s):
      if i >= 6: break
      top.add %*[r.action.name, r.expected, r.guaranteed]
    sc.add %*{"value": sol.value[s], "top": top}
  %*{"positions": g.states.len, "scenarios": sc}

proc runUnit*(u: UnitSpec): JsonNode =
  let t0 = epochTime()
  let st = setupOf(u)
  let g = build(st)
  var sol = solveGame(g, st.tol)
  case u.kind
  of ukSummary:
    result = summarise(g, sol)
  of ukFull:
    certify(g, sol)
    var m = MatchReport(defender: u.defender, attacker: u.attacker, states: g.states.len,
                        pairs: g.pairCount, outcomes: g.outcomeCount,
                        exploitability: max(0.0, sol.worstExploitability))
    for sc in scenarios:
      let s = g.stateId(sc.state)
      var rep = ScenarioReport(scenario: sc, value: sol.value[s])
      rep.outcome = fightStats(g, sol, s)
      rep.responses = responses(g, sol, s)
      rep.answers = attackAnswers(g, sol, s)
      rep.lines = optimalLines(g, sol, s, depth = u.lineDepth, minProb = 0.01, top = 8)
      # quick beam-searched combinations; replaced by the exhaustive search
      # results (combos units) when those are available
      rep.combos = discoverCombos(g, sol, s)
      rep.combos.add discoverCombos(g, sol, s, top = 4, strikesOnly = true)
      for (sid, atk, label, plan) in namedCombos:
        if sid != sc.id: continue
        var af = -1
        if atk.len > 0:
          let a = parseAction(atk)
          if g.actIndex(wB, s, a) < 0: continue
          af = ord(a)
        rep.combos.add scoreCombo(g, sol, s, plan, label, af)
      rep.robustness = Robustness(valueLow: rep.value, valueHigh: rep.value)
      m.scenarios.add rep
    m.seconds = epochTime() - t0
    result = %*{"match": m.toJson, "tablebase": tablebase(g, sol), "summary": summarise(g, sol)}
  of ukCombos:
    var sc0: Scenario
    for sc in scenarios:
      if sc.id == u.scenario: sc0 = sc
    let s = g.stateId(sc0.state)
    let ex = exhaustiveCombos(g, sol, s, maxLen = u.comboLength, minExecuted = u.minExecuted)
    result = %*{"id": u.scenario, "evaluated": ex.evaluated, "maxLen": ex.maxLen,
                "minExecuted": ex.minExecuted, "best": ex.best.mapIt(it.comboJson),
                "striking": ex.striking.mapIt(it.comboJson),
                "decisive": ex.decisive.mapIt(it.comboJson)}
  result["seconds"] = %(epochTime() - t0)

proc runUnitFile*(specPath, resultPath: string) =
  ## Worker entry point: compute one unit and write its result atomically.
  let u = parseUnit(parseFile(specPath))
  let r = runUnit(u)
  let tmp = resultPath & ".tmp"
  writeFile(tmp, $r)
  moveFile(tmp, resultPath)

# ---------------------------------------------------------------------------
# Planning the whole analysis
# ---------------------------------------------------------------------------

type PlannedUnit* = object
  group*, label*: string
  spec*: UnitSpec

proc sdParamNames(p: Params): seq[string] =
  ## Every parameter that matters in self-defense mode.
  var sportOnly: HashSet[string]
  for (fam, members) in paramFamilies:
    if fam == "sport only":
      for m in members: sportOnly.incl m
  for n in p.paramNames:
    if n notin sportOnly: result.add n

proc jointSample(p: Params, names: seq[string], sigma: float, r: var Rand): Params =
  result = p
  for n in names:
    result = result.perturbed(n, exp(sigma * r.gauss()))

proc planUnits*(cfg: DeepConfig): seq[PlannedUnit] =
  let base = defaultParams()
  proc summary(group, label, attacker: string, p: Params, remove: seq[Action] = @[],
               grid = 4): PlannedUnit =
    PlannedUnit(group: group, label: label, spec: UnitSpec(kind: ukSummary,
      defender: "trained", attacker: attacker, removeA: remove, damageLevels: grid, params: p))
  for d in cfg.defenders:
    for a in cfg.attackers:
      result.add PlannedUnit(group: "full", label: &"{d} vs {a}", spec: UnitSpec(kind: ukFull,
        defender: d, attacker: a, damageLevels: 4, params: base, lineDepth: cfg.lineDepth))
      for sc in scenarios:
        result.add PlannedUnit(group: "combos", label: &"{d} vs {a}|{sc.id}",
          spec: UnitSpec(kind: ukCombos, defender: d, attacker: a, damageLevels: 4,
                         params: base, comboLength: cfg.comboLength,
                         minExecuted: cfg.minExecuted, scenario: sc.id))
  let names = sdParamNames(base)
  let trained = findStyle("trained").techniques
  for a in cfg.attackers:
    result.add summary("base", a, a, base)
    for n in names:
      for f in cfg.spreads:
        result.add summary("oat", &"{a}|{n}|{f}", a, base.perturbed(n, f))
    var r = initRand(cfg.seed + a.len * 7919 + ord(a[0]))
    for k in 0 ..< cfg.mcSamples:
      result.add summary("mc", &"{a}|{k}", a, jointSample(base, names, cfg.mcSigma, r))
    for gsize in cfg.grids:
      result.add summary("grid", &"{a}|{gsize}", a, base, grid = gsize)
    var hip = base
    hip.unloadedPower = 1.0
    result.add summary("hip", a, a, hip)
    for t in Techniques:
      if t in trained: result.add summary("ablate", &"{a}|{t.name}", a, base, remove = @[t])
    for (label, s) in zoneGroups(trained):
      result.add summary("zone", &"{a}|{label}", a, base, remove = s.toSeq)
    for (label, s) in mechanicsGroups(trained):
      result.add summary("mechanics", &"{a}|{label}", a, base, remove = s.toSeq)
    if cfg.pairs:
      let ts = (Techniques * trained).toSeq
      for i in 0 ..< ts.len:
        for j in i + 1 ..< ts.len:
          result.add summary("pair", &"{a}|{ts[i].name}|{ts[j].name}", a, base,
                             remove = @[ts[i], ts[j]])

proc resultPath(cfg: DeepConfig, u: PlannedUnit): string =
  cfg.cacheDir / "results" / (u.spec.key & ".json")

proc runAll*(cfg: DeepConfig, units: seq[PlannedUnit]) =
  ## Run every unit whose result is not cached yet, `cfg.jobs` at a time.
  createDir(cfg.cacheDir / "specs")
  createDir(cfg.cacheDir / "results")
  createDir(cfg.cacheDir / "logs")
  var todo: seq[PlannedUnit]
  for u in units:
    if not fileExists(resultPath(cfg, u)): todo.add u
  # full units first (quick, and they make the playbook renderable), then the
  # summaries, then the long exhaustive searches
  proc rank(u: PlannedUnit): int =
    case u.spec.kind
    of ukFull: 0
    of ukSummary: 1
    of ukCombos: 2
  todo.sort(proc(x, y: PlannedUnit): int = cmp(rank(x), rank(y)))
  stderr.writeLine &"deep analysis: {units.len} units, {units.len - todo.len} cached, {todo.len} to run on {cfg.jobs} cores"
  if todo.len == 0: return
  var cmds: seq[string]
  for u in todo:
    let k = u.spec.key
    let spec = cfg.cacheDir / "specs" / (k & ".json")
    writeFile(spec, pretty(u.spec.toJson))
    cmds.add quoteShell(cfg.exe) & " unit --spec " & quoteShell(spec) & " --result " &
             quoteShell(resultPath(cfg, u)) & " > " & quoteShell(cfg.cacheDir / "logs" / (k & ".log")) & " 2>&1"
  let t0 = epochTime()
  var done = 0
  let total = cmds.len
  proc after(idx: int, p: Process) =
    inc done
    let el = epochTime() - t0
    let eta = el / done.float * float(total - done)
    let status = if p.peekExitCode == 0: "ok" else: "FAILED (see logs)"
    stderr.writeLine &"  [{done}/{total}] {todo[idx].group} {todo[idx].label}: {status}  " &
                     &"(elapsed {el / 60:.1f} min, remaining ~{int(round(eta / 60))} min)"
  discard execProcesses(cmds, options = {poEvalCommand}, n = cfg.jobs, afterRunEvent = after)

proc loadResult*(cfg: DeepConfig, u: PlannedUnit): JsonNode =
  let p = resultPath(cfg, u)
  if fileExists(p): parseFile(p) else: nil

# ---------------------------------------------------------------------------
# Aggregation
# ---------------------------------------------------------------------------

type
  ScenarioRobustness* = object
    top*: string                  ## baseline top response
    oatChecks*, oatHolds*: int
    oatFlips*: seq[(string, string)]   ## (parameter x factor, new top)
    mcChecks*, mcHolds*: int
    mcTops*: CountTable[string]
    valueQ*: array[3, float]      ## 5%, 50%, 95% of P(safe) under joint perturbation
    grid*: seq[(int, string, float)]   ## damage levels, top, value

proc holds(base: JsonNode, r: JsonNode, k: int, top: string): (bool, string) =
  ## Does the baseline top response stay the best (or within half a point)?
  let rows = r["scenarios"][k]["top"]
  let newTop = rows[0][0].getStr
  if newTop == top: return (true, newTop)
  for row in rows:
    if row[0].getStr == top and row[1].getFloat >= rows[0][1].getFloat - 0.005:
      return (true, newTop)
  (false, newTop)

proc quantile(xs: seq[float], q: float): float =
  if xs.len == 0: return NaN
  let s = xs.sorted
  s[clamp(int(round(q * float(s.len - 1))), 0, s.len - 1)]

proc aggregateRobustness*(cfg: DeepConfig, units: seq[PlannedUnit], attacker: string):
                          seq[ScenarioRobustness] =
  var base: JsonNode
  for u in units:
    if u.group == "base" and u.spec.attacker == attacker: base = loadResult(cfg, u)
  if base.isNil: return
  let n = base["scenarios"].len
  result = newSeq[ScenarioRobustness](n)
  var values = newSeq[seq[float]](n)
  for k in 0 ..< n:
    result[k].top = base["scenarios"][k]["top"][0][0].getStr
    result[k].mcTops = initCountTable[string]()
  for u in units:
    if u.spec.attacker != attacker or u.group notin ["oat", "mc", "grid"]: continue
    let r = loadResult(cfg, u)
    if r.isNil: continue
    for k in 0 ..< n:
      let (ok, newTop) = holds(base, r, k, result[k].top)
      case u.group
      of "oat":
        inc result[k].oatChecks
        if ok: inc result[k].oatHolds
        else:
          let parts = u.label.split('|')
          result[k].oatFlips.add (&"{parts[1]} x{parts[2]}", newTop)
      of "mc":
        inc result[k].mcChecks
        if ok: inc result[k].mcHolds
        result[k].mcTops.inc newTop
        values[k].add r["scenarios"][k]["value"].getFloat
      of "grid":
        result[k].grid.add (u.spec.damageLevels, newTop, r["scenarios"][k]["value"].getFloat)
      else: discard
  for k in 0 ..< n:
    result[k].valueQ = [quantile(values[k], 0.05), quantile(values[k], 0.5), quantile(values[k], 0.95)]

type AblationTable* = object
  group*, attacker*: string
  rows*: seq[(string, seq[float], float)]   ## label, per-scenario delta, mean

proc aggregateAblation*(cfg: DeepConfig, units: seq[PlannedUnit], attacker, group: string): AblationTable =
  result = AblationTable(group: group, attacker: attacker)
  var base: JsonNode
  for u in units:
    if u.group == "base" and u.spec.attacker == attacker: base = loadResult(cfg, u)
  if base.isNil: return
  for u in units:
    if u.spec.attacker != attacker or u.group != group: continue
    let r = loadResult(cfg, u)
    if r.isNil: continue
    var deltas: seq[float]
    var mean = 0.0
    for k in 0 ..< base["scenarios"].len:
      let d = r["scenarios"][k]["value"].getFloat - base["scenarios"][k]["value"].getFloat
      deltas.add d
      mean += d / base["scenarios"].len.float
    let label = u.label.split('|')[1 .. ^1].join(" + ")
    result.rows.add (label, deltas, mean)
  result.rows.sort(proc(x, y: (string, seq[float], float)): int = cmp(x[2], y[2]))

proc synergy*(singles, pairs: AblationTable): seq[(string, float, float)] =
  ## Interaction of each pair: Δ(both) − Δ(first) − Δ(second), averaged over
  ## situations. Negative: the two techniques back each other up (losing
  ## both costs more than the sum). Positive: they substitute for each other.
  var single = initTable[string, float]()
  for (l, _, m) in singles.rows: single[l] = m
  for (l, _, m) in pairs.rows:
    let parts = l.split(" + ")
    if parts.len != 2 or parts[0] notin single or parts[1] notin single: continue
    result.add (l, m - single[parts[0]] - single[parts[1]], m)
  result.sort(proc(x, y: (string, float, float)): int = cmp(x[1], y[1]))
