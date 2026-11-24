## Questions you can ask the solved model, and how robust the answers are.
##
## - ablation: how much a technique, a target zone or a way of generating
##   force is worth to the defender (remove it and re-solve; in a zero-sum
##   game removing an option can never help, which the tests check)
## - matchups: every defender profile against every attacker profile
## - sensitivity: perturb every parameter and see whether a conclusion holds
## - calibration (sport mode): fit the global knobs to real fight statistics

import std/[algorithm, json, math, strformat, strutils, times]
import core, params, game, solve, analysis

type
  Setup* = object
    ## Everything needed to build one game.
    params*: Params
    a*, b*: set[Action]
    dims*: Dims
    mode*: Mode
    starts*: seq[State]
    tol*: float

  QueryKind* = enum
    qValue      ## value of the first start position
    qAblation   ## change in that value when A loses a set of techniques
    qUsage      ## expected uses of one action by A per encounter

  Query* = object
    kind*: QueryKind
    removed*: set[Action]
    technique*: Action
    label*: string

  Sensitivity* = object
    name*: string
    low*, high*: float    ## query value with the parameter scaled by (1 -/+ spread)

  SensitivityReport* = object
    label*: string
    baseline*: float
    spread*: float
    threshold*: float     ## the conclusion is "baseline is above/below this"
    rows*: seq[Sensitivity]
    seconds*: float

proc defaultSetup*(a = "trained", b = "brawler", mode = mSelfDefense): Setup =
  Setup(params: defaultParams(), a: findStyle(a).arsenal, b: findStyle(b).arsenal,
        dims: defaultDims, mode: mode, starts: @[startState()], tol: 1e-9)

proc build*(st: Setup): Game =
  buildGame(st.params, st.a, st.b, st.dims, st.mode, st.starts)

proc solveSetup*(st: Setup): (Game, Solution) =
  let g = build(st)
  let sol = solveGame(g, st.tol)
  (g, sol)

proc startValues*(g: Game, sol: Solution, starts: seq[State]): seq[float] =
  for s in starts: result.add sol.value[g.stateId(s)]

proc evaluate*(q: Query, st: Setup): float =
  case q.kind
  of qValue:
    let (g, sol) = solveSetup(st)
    sol.value[g.stateId(st.starts[0])]
  of qAblation:
    let (g0, s0) = solveSetup(st)
    var st1 = st
    st1.a = st.a - q.removed
    let (g1, s1) = solveSetup(st1)
    s1.value[g1.stateId(st.starts[0])] - s0.value[g0.stateId(st.starts[0])]
  of qUsage:
    let (g, sol) = solveSetup(st)
    fightStats(g, sol, g.stateId(st.starts[0])).uses[wA][q.technique]

# ---------------------------------------------------------------------------
# Ablation: what is each technique / target / mechanism worth?
# ---------------------------------------------------------------------------

type
  AblationRow* = object
    label*: string
    removed*: set[Action]
    deltas*: seq[float]   ## change in value per start position (<= 0)
    mean*: float

proc techniquesAimedAt*(z: VulnerabilityZone, among: set[Action]): set[Action] =
  for a in among:
    if a in Strikes and tech[a].zone == z: result.incl a

proc techniquesWith*(m: Mechanics, among: set[Action]): set[Action] =
  for a in among:
    if a in Strikes and tech[a].mech == m: result.incl a

proc ablate*(st: Setup, groups: seq[(string, set[Action])],
             progress = false): (seq[float], seq[AblationRow]) =
  let (g0, s0) = solveSetup(st)
  let base = startValues(g0, s0, st.starts)
  var rows: seq[AblationRow]
  for (label, removed) in groups:
    let r = removed * st.a
    if r.card == 0: continue
    var st1 = st
    st1.a = st.a - r
    let (g1, s1) = solveSetup(st1)
    let v = startValues(g1, s1, st.starts)
    var row = AblationRow(label: label, removed: r)
    for i in 0 ..< v.len:
      row.deltas.add v[i] - base[i]
      row.mean += (v[i] - base[i]) / v.len.float
    rows.add row
    if progress: stderr.writeLine &"  without {label}: {row.mean:+.4f}"
  rows.sort(proc(x, y: AblationRow): int = cmp(x.mean, y.mean))
  (base, rows)

proc techniqueGroups*(arsenal: set[Action]): seq[(string, set[Action])] =
  for t in Techniques:
    if t in arsenal: result.add (t.name, {t})

proc zoneGroups*(arsenal: set[Action]): seq[(string, set[Action])] =
  for z in VulnerabilityZone:
    let s = techniquesAimedAt(z, arsenal)
    if s.card > 0: result.add (z.zoneName, s)

proc mechanicsGroups*(arsenal: set[Action]): seq[(string, set[Action])] =
  for m in Mechanics:
    if m == mkNone: continue
    let s = techniquesWith(m, arsenal)
    if s.card > 0: result.add (($m)[2 .. ^1], s)

proc hipLoadingValue*(st: Setup): (seq[float], seq[float]) =
  ## Values with the hip-loading model on (default) and off (every
  ## rotational strike at full power and speed regardless of which side is
  ## wound up). The difference is what chaining rotations is worth.
  let (g0, s0) = solveSetup(st)
  var st1 = st
  st1.params.unloadedPower = 1.0
  let (g1, s1) = solveSetup(st1)
  (startValues(g0, s0, st.starts), startValues(g1, s1, st.starts))

# ---------------------------------------------------------------------------
# Matchups
# ---------------------------------------------------------------------------

proc matchups*(base: Setup, defenders, attackers: seq[string],
               progress = false): seq[seq[seq[float]]] =
  ## result[i][j][k] = value of start k for defender i vs attacker j.
  for dn in defenders:
    var row: seq[seq[float]]
    for an in attackers:
      var st = base
      st.a = findStyle(dn).arsenal
      st.b = findStyle(an).arsenal
      let (g, sol) = solveSetup(st)
      row.add startValues(g, sol, st.starts)
      if progress: stderr.writeLine &"  {dn} vs {an} done"
    result.add row

# ---------------------------------------------------------------------------
# Sensitivity
# ---------------------------------------------------------------------------

proc groupNames*(p: Params): seq[string] =
  ## Scalars individually; each table as one group (scaled as a whole),
  ## which keeps a full sweep affordable.
  for k, v in p.fieldPairs:
    when v is float:
      if k notin ["maxProb", "decisionWeight", "decisionTop", "decisionDominant",
                  "refStandUp"]:
        result.add k
    elif v is ActionTable or v is MechTable:
      result.add k & ".*"

proc perturbGroup*(p: Params, name: string, factor: float): Params =
  if name.endsWith(".*"):
    result = p
    let table = name[0 .. ^3]
    for full in p.paramNames:
      if full.startsWith(table & "."):
        result = result.perturbed(full, factor)
  else:
    result = p.perturbed(name, factor)

proc sensitivity*(q: Query, st: Setup, spread = 0.25, fine = false,
                  threshold = NaN, progress = false): SensitivityReport =
  let t0 = epochTime()
  result.label = q.label
  result.spread = spread
  result.baseline = evaluate(q, st)
  result.threshold =
    if not threshold.isNaN: threshold
    else:
      case q.kind
      of qValue: 0.5
      of qAblation, qUsage: 0.0
  let names = if fine: st.params.paramNames else: groupNames(st.params)
  for i, name in names:
    var lo = st
    lo.params = perturbGroup(st.params, name, 1.0 - spread)
    var hi = st
    hi.params = perturbGroup(st.params, name, 1.0 + spread)
    let l = evaluate(q, lo)
    let h = evaluate(q, hi)
    result.rows.add Sensitivity(name: name, low: l, high: h)
    if progress:
      stderr.writeLine &"  [{i+1}/{names.len}] {name}: {l:.4f} .. {h:.4f}"
  let base = result.baseline
  result.rows.sort(proc(x, y: Sensitivity): int =
    cmp(max(abs(y.low - base), abs(y.high - base)),
        max(abs(x.low - base), abs(x.high - base))))
  result.seconds = epochTime() - t0

proc flips*(r: SensitivityReport): seq[Sensitivity] =
  ## Perturbations that move the answer to the other side of the threshold.
  let side = r.baseline > r.threshold
  for row in r.rows:
    if (row.low > r.threshold) != side or (row.high > r.threshold) != side:
      result.add row

proc render*(r: SensitivityReport, top = 15): string =
  var lines: seq[string]
  lines.add &"Query: {r.label}"
  lines.add &"Baseline: {r.baseline:.4f}   (each parameter scaled by 1 -/+ {r.spread:.2f}; {r.rows.len} parameters, {r.seconds:.0f}s)"
  var lo = r.baseline
  var hi = r.baseline
  for row in r.rows:
    lo = min(lo, min(row.low, row.high))
    hi = max(hi, max(row.low, row.high))
  lines.add &"Range over all one-at-a-time perturbations: {lo:.4f} .. {hi:.4f}"
  let fl = r.flips
  let side = if r.baseline > r.threshold: "above" else: "below"
  if fl.len == 0:
    lines.add &"Conclusion ({side} {r.threshold:.3f}) holds under every perturbation: ROBUST"
  else:
    var names: seq[string]
    for f in fl: names.add f.name
    lines.add &"Conclusion ({side} {r.threshold:.3f}) FLIPS under {fl.len} perturbation(s): " & names.join(", ")
  lines.add ""
  let minus = "-" & $int(r.spread * 100) & "%"
  let plus = "+" & $int(r.spread * 100) & "%"
  lines.add alignLeft("parameter", 26) & align(minus, 10) & align(plus, 10) & "   largest move"
  for i, row in r.rows:
    if i >= top: break
    let mv = max(abs(row.low - r.baseline), abs(row.high - r.baseline))
    lines.add &"{row.name:<26}{row.low:>10.4f}{row.high:>10.4f}   {mv:.4f}"
  lines.join("\n")

# ---------------------------------------------------------------------------
# Calibration (sport mode)
# ---------------------------------------------------------------------------

type
  Targets* = object
    ko*, sub*, decision*: float   ## share of fights ending each way
    strikeAccuracy*: float
    accuracyWeight*: float        ## how much to trust the accuracy target (0..1)
    sources*: seq[string]

  CalibrationStep* = object
    knobs*: array[5, float]   ## see `knobNames`
    ko*, sub*, decision*, accuracy*: float

const
  knobNames* = ["stopChance", "damageScale", "submissionScale", "grappleScale", "hitScale"]
  knobBounds* = [(0.001, 0.2), (0.05, 5.0), (0.1, 8.0), (0.25, 4.0), (0.3, 2.0)]

proc loadTargets*(path: string): Targets =
  let j = parseFile(path)
  result.ko = j["ko"].getFloat
  result.sub = j["submission"].getFloat
  result.decision = j["decision"].getFloat
  result.strikeAccuracy = j{"strikeAccuracy"}.getFloat(0.0)
  result.accuracyWeight = j{"accuracyWeight"}.getFloat(0.5)
  if j.hasKey("sources"):
    for s in j["sources"]: result.sources.add s.getStr

proc knobs*(p: Params): array[5, float] =
  [p.stopChance, p.damageScale, p.submissionScale, p.grappleScale, p.hitScale]

proc atBound*(p: Params): seq[string] =
  let v = knobs(p)
  for i in 0 ..< v.len:
    if v[i] <= knobBounds[i][0] * 1.0001 or v[i] >= knobBounds[i][1] * 0.9999:
      result.add knobNames[i]

proc observe*(st: Setup): CalibrationStep =
  let (g, sol) = solveSetup(st)
  let fs = fightStats(g, sol)
  result.knobs = knobs(st.params)
  result.ko = fs.finishes[tAKO] + fs.finishes[tBKO]
  result.sub = fs.finishes[tASub] + fs.finishes[tBSub]
  result.decision = fs.stopped
  result.accuracy = strikeAccuracy(fs, wA)[2]

proc calibrate*(start: Setup, t: Targets, maxIter = 30,
                progress = false): (Params, seq[CalibrationStep]) =
  ## Fit the global knobs so that equilibrium play in sport mode reproduces
  ## the target finish breakdown and strike accuracy. Damped multiplicative
  ## fixed-point updates; every step is a full solve. Submissions need both
  ## reaching the ground and finishing there, so the submission gap is split
  ## evenly (in log space) between grappleScale and submissionScale.
  var st = start
  st.mode = mSport
  var trace: seq[CalibrationStep]
  for it in 0 ..< maxIter:
    let o = observe(st)
    trace.add o
    let p0 = st.params
    if progress:
      stderr.writeLine &"  step {it:>2}: stop {p0.stopChance:.4f} dmg {p0.damageScale:.3f} sub {p0.submissionScale:.3f} grapple {p0.grappleScale:.3f} hit {p0.hitScale:.3f}  ->  KO {o.ko:.3f} sub {o.sub:.3f} dec {o.decision:.3f} acc {o.accuracy:.3f}"
    let errs = [abs(o.ko - t.ko) / t.ko, abs(o.sub - t.sub) / t.sub,
                abs(o.decision - t.decision) / t.decision,
                (if t.strikeAccuracy > 0: t.accuracyWeight * abs(o.accuracy - t.strikeAccuracy) / t.strikeAccuracy else: 0.0)]
    if max(errs) < 0.01: break
    const damp = 0.6
    var p = st.params
    p.stopChance = clamp(p.stopChance * pow(t.decision / max(o.decision, 1e-6), damp),
                         knobBounds[0][0], knobBounds[0][1])
    p.damageScale = clamp(p.damageScale * pow(t.ko / max(o.ko, 1e-6), damp),
                          knobBounds[1][0], knobBounds[1][1])
    let subRatio = pow(t.sub / max(o.sub, 1e-6), 0.5 * damp)
    p.submissionScale = clamp(p.submissionScale * subRatio, knobBounds[2][0], knobBounds[2][1])
    p.grappleScale = clamp(p.grappleScale * subRatio, knobBounds[3][0], knobBounds[3][1])
    if t.strikeAccuracy > 0:
      p.hitScale = clamp(p.hitScale * pow(t.strikeAccuracy / max(o.accuracy, 1e-6),
                                          damp * t.accuracyWeight),
                         knobBounds[4][0], knobBounds[4][1])
    st.params = p
  (st.params, trace)
