## Questions you can ask the solved model, and how robust the answers are.
##
## - matchups: P(style X beats style Y) from the opening
## - ablation: how much each technique is worth to a fighter (remove it and
##   re-solve; in a zero-sum game removing an option can never help)
## - sensitivity: perturb every parameter and see whether a conclusion holds
## - calibration: fit the global knobs to real fight-outcome statistics

import std/[algorithm, json, math, strformat, strutils, times]
import core, params, game, solve, analysis

type
  QueryKind* = enum
    qValue      ## P(A wins) from the opening
    qAblation   ## change in P(A wins) when A loses one technique
    qUsage      ## expected uses of one action by A per fight

  Query* = object
    kind*: QueryKind
    a*, b*: set[Action]   ## arsenals
    technique*: Action
    label*: string

  Sensitivity* = object
    name*: string
    low*, high*: float    ## query value with the parameter scaled by (1 -/+ spread)

  SensitivityReport* = object
    query*: Query
    baseline*: float
    spread*: float
    threshold*: float     ## the conclusion is "baseline is above/below this"
    rows*: seq[Sensitivity]
    seconds*: float

  Targets* = object
    ko*, sub*, decision*: float   ## share of fights ending each way
    strikeAccuracy*: float
    accuracyWeight*: float        ## how much to trust the accuracy target (0..1)
    sources*: seq[string]

proc solveValue*(p: Params, a, b: set[Action], dims: Dims, tol: float): (Game, Solution) =
  let g = buildGame(p, a, b, dims)
  let sol = solveGame(g, tol)
  (g, sol)

proc evaluate*(q: Query, p: Params, dims = defaultDims, tol = 1e-9): float =
  case q.kind
  of qValue:
    let (g, sol) = solveValue(p, q.a, q.b, dims, tol)
    sol.value[g.start]
  of qAblation:
    let (g0, s0) = solveValue(p, q.a, q.b, dims, tol)
    let (g1, s1) = solveValue(p, q.a - {q.technique}, q.b, dims, tol)
    s1.value[g1.start] - s0.value[g0.start]
  of qUsage:
    let (g, sol) = solveValue(p, q.a, q.b, dims, tol)
    fightStats(g, sol).uses[wA][q.technique]

# ---------------------------------------------------------------------------
# Matchups and ablation
# ---------------------------------------------------------------------------

proc newSeqWith2(n: int): seq[seq[float]] =
  result = newSeq[seq[float]](n)
  for i in 0 ..< n: result[i] = newSeq[float](n)

proc matchups*(p: Params, names: seq[string], dims = defaultDims,
               tol = 1e-9): seq[seq[float]] =
  ## result[i][j] = P(style i beats style j). Only i <= j is solved; the rest
  ## follows from zero-sum symmetry (checked in the tests).
  let n = names.len
  result = newSeqWith2(n)
  for i in 0 ..< n:
    for j in i ..< n:
      let a = findStyle(names[i]).arsenal
      let b = findStyle(names[j]).arsenal
      let v = if i == j: 0.5 else: solveValue(p, a, b, dims, tol)[1].value[0]
      result[i][j] = v
      result[j][i] = 1.0 - v

type AblationRow* = object
  technique*: Action
  delta*: float        ## change in P(A wins) without it (<= 0)
  usesPerFight*: float

proc ablation*(p: Params, a, b: set[Action], dims = defaultDims,
               tol = 1e-9): (float, seq[AblationRow]) =
  let (g0, s0) = solveValue(p, a, b, dims, tol)
  let base = s0.value[g0.start]
  let st = fightStats(g0, s0)
  var rows: seq[AblationRow]
  for t in Techniques:
    if t notin a: continue
    let (g1, s1) = solveValue(p, a - {t}, b, dims, tol)
    rows.add AblationRow(technique: t, delta: s1.value[g1.start] - base,
                         usesPerFight: st.uses[wA][t])
  rows.sort(proc(x, y: AblationRow): int = cmp(x.delta, y.delta))
  (base, rows)

# ---------------------------------------------------------------------------
# Sensitivity
# ---------------------------------------------------------------------------

proc groupNames*(p: Params): seq[string] =
  ## Scalars individually; each per-action table as one group (scaled as a
  ## whole), which keeps a full sweep affordable.
  for k, v in p.fieldPairs:
    when v is float:
      if k notin ["maxProb"]: result.add k
    elif v is ActionTable:
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

proc sensitivity*(q: Query, p: Params, spread = 0.25, fine = false,
                  dims = defaultDims, tol = 1e-9, threshold = NaN,
                  progress = false): SensitivityReport =
  let t0 = epochTime()
  result.query = q
  result.spread = spread
  result.baseline = evaluate(q, p, dims, tol)
  result.threshold =
    if not threshold.isNaN: threshold
    else:
      case q.kind
      of qValue: 0.5
      of qAblation: 0.0
      of qUsage: 0.0
  let names = if fine: p.paramNames else: groupNames(p)
  for i, name in names:
    let lo = evaluate(q, perturbGroup(p, name, 1.0 - spread), dims, tol)
    let hi = evaluate(q, perturbGroup(p, name, 1.0 + spread), dims, tol)
    result.rows.add Sensitivity(name: name, low: lo, high: hi)
    if progress:
      stderr.writeLine &"  [{i+1}/{names.len}] {name}: {lo:.4f} .. {hi:.4f}"
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
  lines.add &"Query: {r.query.label}"
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
  lines.add &"{\"parameter\":<26} {\"-\" & $int(r.spread*100) & \"%\":>9} {\"+\" & $int(r.spread*100) & \"%\":>9}   largest move"
  for i, row in r.rows:
    if i >= top: break
    let mv = max(abs(row.low - r.baseline), abs(row.high - r.baseline))
    lines.add &"{row.name:<26} {row.low:>9.4f} {row.high:>9.4f}   {mv:.4f}"
  lines.join("\n")

# ---------------------------------------------------------------------------
# Calibration
# ---------------------------------------------------------------------------

proc loadTargets*(path: string): Targets =
  let j = parseFile(path)
  result.ko = j["ko"].getFloat
  result.sub = j["submission"].getFloat
  result.decision = j["decision"].getFloat
  result.strikeAccuracy = j{"strikeAccuracy"}.getFloat(0.0)
  result.accuracyWeight = j{"accuracyWeight"}.getFloat(0.5)
  if j.hasKey("sources"):
    for s in j["sources"]: result.sources.add s.getStr

type CalibrationStep* = object
  knobs*: array[5, float]   ## see `knobNames`
  ko*, sub*, decision*, accuracy*: float

const
  knobNames* = ["stopChance", "damageScale", "submissionScale", "grappleScale", "hitScale"]
  knobBounds* = [(0.001, 0.2), (0.05, 5.0), (0.1, 8.0), (0.25, 4.0), (0.3, 2.0)]

proc knobs*(p: Params): array[5, float] =
  [p.stopChance, p.damageScale, p.submissionScale, p.grappleScale, p.hitScale]

proc atBound*(p: Params): seq[string] =
  let v = knobs(p)
  for i in 0 ..< v.len:
    if v[i] <= knobBounds[i][0] * 1.0001 or v[i] >= knobBounds[i][1] * 0.9999:
      result.add knobNames[i]

proc observe*(p: Params, dims: Dims, tol: float): CalibrationStep =
  let all = findStyle("complete").arsenal
  let (g, sol) = solveValue(p, all, all, dims, tol)
  let st = fightStats(g, sol)
  result.knobs = knobs(p)
  result.ko = st.finishes[tAKO] + st.finishes[tBKO]
  result.sub = st.finishes[tASub] + st.finishes[tBSub]
  result.decision = st.decision
  result.accuracy = strikeAccuracy(st, wA)[2]

proc calibrate*(start: Params, t: Targets, dims = defaultDims, maxIter = 40,
                tol = 1e-7, progress = false): (Params, seq[CalibrationStep]) =
  ## Fit the global knobs so that equilibrium play between two complete
  ## fighters reproduces the target finish breakdown and strike accuracy.
  ## Damped multiplicative fixed-point updates; every step is a full solve.
  ## Submissions need both reaching the ground and finishing there, so the
  ## submission gap is split evenly (in log space) between grappleScale and
  ## submissionScale instead of letting one of them run to an extreme.
  var p = start
  var trace: seq[CalibrationStep]
  for it in 0 ..< maxIter:
    let o = observe(p, dims, tol)
    trace.add o
    if progress:
      stderr.writeLine &"  step {it:>2}: stop {p.stopChance:.4f} dmg {p.damageScale:.3f} sub {p.submissionScale:.3f} grapple {p.grappleScale:.3f} hit {p.hitScale:.3f}  ->  KO {o.ko:.3f} sub {o.sub:.3f} dec {o.decision:.3f} acc {o.accuracy:.3f}"
    let errs = [abs(o.ko - t.ko) / t.ko, abs(o.sub - t.sub) / t.sub,
                abs(o.decision - t.decision) / t.decision,
                (if t.strikeAccuracy > 0: t.accuracyWeight * abs(o.accuracy - t.strikeAccuracy) / t.strikeAccuracy else: 0.0)]
    if max(errs) < 0.01: break
    const damp = 0.6
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
  (p, trace)
