## fightsolve: solve the fight game exactly and ask it questions.
##
##   fightsolve solve        [--a STYLE] [--b STYLE]
##   fightsolve explain      POSITION [--a-dmg N] [--a-fat N] [--a-off] [--b-dmg N] [--b-fat N] [--b-off]
##   fightsolve matchups     [--styles a,b,c]
##   fightsolve ablate       [--a STYLE] [--b STYLE]
##   fightsolve sensitivity  [--query value|ablate:TECH|usage:TECH] [--a STYLE] [--b STYLE]
##                           [--spread 0.25] [--top 15] [--fine]
##   fightsolve calibrate    [--targets data/calibration_targets.json] [--out FILE]
##   fightsolve params       [--out FILE]
##   fightsolve export       --out FILE [--a STYLE] [--b STYLE]
##
## Common options: --params FILE (JSON overrides), --damage-levels N,
## --fatigue-levels N, --tol X, --quiet

import std/[json, os, parseopt, strformat, strutils, times]
import solver/[core, params, rules, game, solve, analysis, studies]

const usage = """
fightsolve - exact equilibrium analysis of a discrete fight model

Commands
  solve         Solve one matchup; print the certificate, how fights end,
                what each fighter does, and the opening strategies.
  explain POS   Values and optimal mixed strategies at one position.
                POS is one of: Long Mid MidAngA MidAngB Close CloseAngA
                CloseAngB Clinch ClinchA ClinchB OverA OverB GuardA GuardB
                MountA MountB BackA BackB (suffix = fighter with the advantage)
  matchups      P(row style beats column style) for every pair of styles.
  ablate        How much each technique is worth to fighter A.
  sensitivity   Perturb every parameter; report whether a conclusion holds.
  calibrate     Fit the global knobs to real fight-outcome statistics.
  params        Print (or write) every model parameter as JSON.
  export        Write the solved positions and strategies as JSON.

Options
  --a STYLE / --b STYLE    fighter styles (complete boxer kickboxer wrestler
                           grappler judoka); default complete
  --params FILE            JSON file overriding any parameters
  --damage-levels N        damage levels before a knockout (default 4)
  --fatigue-levels N       fatigue levels (default 3)
  --tol X                  solver tolerance (default 1e-10)
  --query Q                sensitivity target: value | ablate:TECH | usage:TECH
  --spread X               sensitivity perturbation size (default 0.25)
  --fine                   sensitivity: perturb every table entry separately
  --top N                  rows to show (default 15)
  --styles a,b,...         styles for matchups (default all)
  --targets FILE           calibration targets (default data/calibration_targets.json)
  --out FILE               output file
  --quiet                  no progress output
"""

type Opts = object
  cmd: string
  args: seq[string]
  a, b: string
  paramsFile: string
  dims: Dims
  tol: float
  query: string
  spread: float
  fine: bool
  top: int
  styles: string
  targets: string
  outFile: string
  quiet: bool
  aDmg, aFat, bDmg, bFat: int
  aOff, bOff: bool

proc parseOpts(): Opts =
  result = Opts(a: "complete", b: "complete", dims: defaultDims, tol: 1e-10,
                query: "value", spread: 0.25, top: 15,
                targets: "data/calibration_targets.json")
  var p = initOptParser(commandLineParams(), shortNoVal = {'h'},
                        longNoVal = @["fine", "quiet", "a-off", "b-off", "help"])
  for kind, key, val in p.getopt():
    case kind
    of cmdArgument:
      if result.cmd.len == 0: result.cmd = key
      else: result.args.add key
    of cmdLongOption, cmdShortOption:
      case key
      of "a": result.a = val
      of "b": result.b = val
      of "params": result.paramsFile = val
      of "damage-levels": result.dims.damageLevels = parseInt(val)
      of "fatigue-levels": result.dims.fatigueLevels = parseInt(val)
      of "tol": result.tol = parseFloat(val)
      of "query": result.query = val
      of "spread": result.spread = parseFloat(val)
      of "fine": result.fine = true
      of "top": result.top = parseInt(val)
      of "styles": result.styles = val
      of "targets": result.targets = val
      of "out": result.outFile = val
      of "quiet": result.quiet = true
      of "a-dmg": result.aDmg = parseInt(val)
      of "a-fat": result.aFat = parseInt(val)
      of "b-dmg": result.bDmg = parseInt(val)
      of "b-fat": result.bFat = parseInt(val)
      of "a-off": result.aOff = true
      of "b-off": result.bOff = true
      of "h", "help":
        echo usage
        quit 0
      else:
        quit "unknown option --" & key & "\n" & usage, 2
    of cmdEnd: discard

proc loadParams(o: Opts): Params =
  result = defaultParams()
  if o.paramsFile.len > 0: result.applyJson(parseFile(o.paramsFile))

proc header(g: Game, o: Opts) =
  if not o.quiet:
    echo &"Model: {g.states.len} positions, {g.pairCount} action pairs, {g.outcomeCount} explicit outcomes " &
         &"({o.dims.damageLevels} damage levels, {o.dims.fatigueLevels} fatigue levels)"

proc certificateLine(sol: Solution): string =
  &"Certificate: A's strategy guarantees >= {sol.floorStart:.9f}, B's concedes <= {sol.ceilingStart:.9f} " &
  &"(exploitability {max(0.0, sol.exploitability):.1e}; worst position {max(0.0, sol.worstExploitability):.1e}; " &
  &"{sol.sweeps} exact + {sol.evalSweeps} fast sweeps, {sol.seconds:.1f}s)"

proc mixLine(g: Game, sol: Solution, w: Who, s: int): string =
  var parts: seq[string]
  for (a, x) in mix(g, sol, w, s):
    if x > 0.005: parts.add &"{a.name} {pct(x)}"
  parts.join(", ")

proc cmdSolve(o: Opts) =
  let p = loadParams(o)
  let g = buildGame(p, findStyle(o.a).arsenal, findStyle(o.b).arsenal, o.dims)
  header(g, o)
  var sol = solveGame(g, o.tol)
  certify(g, sol)
  echo &"A ({o.a}) vs B ({o.b}): P(A wins) = {sol.value[g.start]:.4f}"
  echo certificateLine(sol)
  let st = fightStats(g, sol)
  echo report(g, sol, st, wA)
  if o.a != o.b:
    let (att, lan, acc) = strikeAccuracy(st, wB)
    echo &"Fighter B: strikes {att:.1f} thrown, {lan:.1f} landed ({pct(acc)})"
  echo ""
  echo "Opening (kicking range, both fresh):"
  echo "  A: " & mixLine(g, sol, wA, g.start)
  echo "  B: " & mixLine(g, sol, wB, g.start)

proc cmdExplain(o: Opts) =
  if o.args.len < 1: quit "explain needs a position, e.g. `fightsolve explain Mid`", 2
  let p = loadParams(o)
  let g = buildGame(p, findStyle(o.a).arsenal, findStyle(o.b).arsenal, o.dims)
  header(g, o)
  let sol = solveGame(g, o.tol)
  var s = State(pos: parsePos(o.args[0]))
  s.f[wA] = Fighter(dmg: o.aDmg, fat: o.aFat, off: o.aOff)
  s.f[wB] = Fighter(dmg: o.bDmg, fat: o.bFat, off: o.bOff)
  let id = g.stateId(s)
  if id < 0:
    quit &"position {s} is not reachable from the opening in this model", 1
  echo &"Position: {g.states[id]}"
  echo &"P(A wins) under optimal play: {sol.value[id]:.4f}   (decision now would give {g.stopValue[id]:.3f})"
  echo "A plays: " & mixLine(g, sol, wA, id)
  echo "B plays: " & mixLine(g, sol, wB, id)
  echo ""
  echo "Payoff matrix, P(A wins) after this beat (rows A, columns B):"
  let m = g.nActs(wA, id)
  let k = g.nActs(wB, id)
  var head = alignLeft("", 10)
  for j in 0 ..< k: head &= align(g.act(wB, id, j).name, 9)
  echo head
  for i in 0 ..< m:
    var line = alignLeft(g.act(wA, id, i).name, 10)
    for j in 0 ..< k:
      let pair = g.pairIndex(id, i, j)
      var v = 0.0
      for t in g.outOff[pair] ..< g.outOff[pair + 1]:
        let tg = g.target[t]
        v += g.prob[t] * (if tg >= 0: sol.value[tg] else: terminalValue(toTerminal(tg)))
      line &= align(formatFloat(v, ffDecimal, 3), 9)
    echo line

proc styleNames(o: Opts): seq[string] =
  if o.styles.len > 0:
    return o.styles.split(',')
  for s in styles: result.add s.name

proc cmdMatchups(o: Opts) =
  let p = loadParams(o)
  let names = styleNames(o)
  let t0 = epochTime()
  let m = matchups(p, names, o.dims, o.tol)
  echo "P(row beats column) from the opening, both fresh:"
  var head = alignLeft("", 11)
  for n in names: head &= align(n, 11)
  echo head
  for i, n in names:
    var line = alignLeft(n, 11)
    for j in 0 ..< names.len: line &= align(formatFloat(m[i][j], ffDecimal, 3), 11)
    echo line
  if not o.quiet: echo &"({epochTime() - t0:.0f}s)"

proc cmdAblate(o: Opts) =
  let p = loadParams(o)
  let t0 = epochTime()
  let (base, rows) = ablation(p, findStyle(o.a).arsenal, findStyle(o.b).arsenal, o.dims, o.tol)
  echo &"A ({o.a}) vs B ({o.b}): P(A wins) = {base:.4f} with the full arsenal."
  echo "Value of each technique to A (drop in P(A wins) if A could not use it):"
  echo &"{\"technique\":<12} {\"worth\":>8} {\"uses/fight\":>11}"
  for r in rows:
    echo &"{r.technique.name:<12} {-r.delta:>8.4f} {r.usesPerFight:>11.2f}"
  if not o.quiet: echo &"({epochTime() - t0:.0f}s)"

proc parseQuery(o: Opts): Query =
  result.a = findStyle(o.a).arsenal
  result.b = findStyle(o.b).arsenal
  let parts = o.query.split(':')
  case parts[0]
  of "value":
    result.kind = qValue
    result.label = &"P({o.a} beats {o.b})"
  of "ablate":
    result.kind = qAblation
    result.technique = parseAction(parts[1])
    result.label = &"change in P({o.a} beats {o.b}) without {result.technique.name}"
  of "usage":
    result.kind = qUsage
    result.technique = parseAction(parts[1])
    result.label = &"{o.a}'s uses of {result.technique.name} per fight vs {o.b}"
  else: quit "unknown query: " & o.query, 2

proc cmdSensitivity(o: Opts) =
  let p = loadParams(o)
  let q = parseQuery(o)
  let r = sensitivity(q, p, o.spread, o.fine, o.dims, max(o.tol, 1e-9),
                      progress = not o.quiet)
  echo render(r, o.top)

proc cmdCalibrate(o: Opts) =
  let t = loadTargets(o.targets)
  let start = loadParams(o)
  let (p, trace) = calibrate(start, t, o.dims, progress = not o.quiet)
  let last = trace[^1]
  echo "Targets:  " & &"KO {pct(t.ko)}  submission {pct(t.sub)}  decision {pct(t.decision)}  strike accuracy {pct(t.strikeAccuracy)}"
  echo "Model:    " & &"KO {pct(last.ko)}  submission {pct(last.sub)}  decision {pct(last.decision)}  strike accuracy {pct(last.accuracy)}"
  echo &"Fitted knobs: stopChance {p.stopChance:.5f}  damageScale {p.damageScale:.4f}  submissionScale {p.submissionScale:.4f}  grappleScale {p.grappleScale:.4f}  hitScale {p.hitScale:.4f}"
  let stuck = atBound(p)
  if stuck.len > 0:
    echo "WARNING: " & stuck.join(", ") & " ended at the edge of its allowed range: the model's structure, " &
         "not just its global knobs, cannot reproduce these targets."
  if o.outFile.len > 0:
    writeFile(o.outFile, pretty(%*{"stopChance": p.stopChance, "damageScale": p.damageScale,
                                   "submissionScale": p.submissionScale,
                                   "grappleScale": p.grappleScale, "hitScale": p.hitScale}))
    echo "Wrote " & o.outFile

proc cmdParams(o: Opts) =
  let j = pretty(loadParams(o).toJson)
  if o.outFile.len > 0:
    writeFile(o.outFile, j)
    echo "Wrote " & o.outFile
  else:
    echo j

proc cmdExport(o: Opts) =
  if o.outFile.len == 0: quit "export needs --out FILE", 2
  let p = loadParams(o)
  let g = buildGame(p, findStyle(o.a).arsenal, findStyle(o.b).arsenal, o.dims)
  var sol = solveGame(g, o.tol)
  certify(g, sol)
  var positions = newJArray()
  for id in 0 ..< g.states.len:
    let s = g.states[id]
    var strat = newJObject()
    for w in Who:
      var m = newJObject()
      for (a, x) in mix(g, sol, w, id):
        if x > 1e-9: m[a.name] = %x
      strat[$w] = m
    positions.add %*{
      "id": id, "position": s.pos.name,
      "A": {"damage": s.f[wA].dmg, "fatigue": s.f[wA].fat, "offBalance": s.f[wA].off},
      "B": {"damage": s.f[wB].dmg, "fatigue": s.f[wB].fat, "offBalance": s.f[wB].off},
      "value": sol.value[id], "strategy": strat}
  let doc = %*{
    "styleA": o.a, "styleB": o.b,
    "damageLevels": o.dims.damageLevels, "fatigueLevels": o.dims.fatigueLevels,
    "startValue": sol.value[g.start], "exploitability": sol.exploitability,
    "params": p.toJson, "positions": positions}
  writeFile(o.outFile, $doc)
  echo &"Wrote {g.states.len} positions to {o.outFile}"

when isMainModule:
  try:
    let o = parseOpts()
    case o.cmd
    of "solve": cmdSolve(o)
    of "explain": cmdExplain(o)
    of "matchups": cmdMatchups(o)
    of "ablate": cmdAblate(o)
    of "sensitivity": cmdSensitivity(o)
    of "calibrate": cmdCalibrate(o)
    of "params": cmdParams(o)
    of "export": cmdExport(o)
    of "", "help": echo usage
    else: quit "unknown command: " & o.cmd & "\n" & usage, 2
  except ValueError, KeyError, IOError, OSError:
    quit "error: " & getCurrentExceptionMsg(), 1
