## fightsolve: solve the confrontation game exactly and ask it questions.
##
## The main product is `fightsolve playbook`, which writes a static
## self-defense playbook (Markdown, HTML and JSON). The other commands
## inspect single matchups and positions.

import std/[json, os, parseopt, sequtils, strformat, strutils, times]
import solver/[core, params, rules, game, solve, analysis, studies, playbook, playbook_render]

const usage = """
fightsolve - exact equilibrium analysis of a discrete self-defense model

Commands
  playbook      Generate the static self-defense playbook (Markdown, HTML,
                JSON) into --out (default docs/playbook).
  solve         Solve one matchup from one situation; print the certificate,
                how encounters end, and what each side does.
  explain       Values, optimal mixed strategies and the full payoff matrix
                at one position.
  ablate        What each technique / target zone / force mechanism is worth
                to the defender (--by technique|zone|mechanics).
  matchups      P(safe) for every defender profile vs every attacker profile.
  sensitivity   Perturb every parameter; report whether a conclusion holds.
  calibrate     Sport mode: fit the global knobs to UFC outcome statistics.
  params        Print (or write) every model parameter as JSON.
  export        Write every solved position and strategy as JSON.

Options
  --a NAME / --b NAME     profiles: defenders trained, untrained; attackers
                          brawler, striker, grappler; complete (sport)
                          default: trained vs brawler
  --pos POS               situation (position) for solve/explain/sensitivity:
                          Long Mid MidAngA MidAngB Close CloseAngA CloseAngB
                          Clinch ClinchA ClinchB BehindA BehindB OverA OverB
                          GuardA GuardB MountA MountB BackA BackB
                          (suffix = who has the advantage; A is you)
  --a-dmg N --a-off --a-stun --a-lead --a-legs   your condition (explain)
  --b-dmg N --b-off --b-stun --b-lead --b-legs   attacker's condition (explain)
  --sport                 sport mode (symmetric, decisions) instead of self-defense
  --params FILE           JSON file overriding any parameters
  --damage-levels N       damage levels before incapacitation (default 4)
  --tol X                 solver tolerance (default 1e-9)
  --by KIND               ablate: technique, zone or mechanics (default zone)
  --query Q               sensitivity: value | ablate:TECH | usage:TECH
  --spread X              sensitivity perturbation size (default 0.25)
  --fine                  sensitivity: perturb every table entry separately
  --no-robustness         playbook: skip the perturbation checks (faster)
  --top N                 rows to show (default 15)
  --targets FILE          calibration targets (default data/calibration_targets.json)
  --out PATH              output file or directory
  --quiet                 no progress output
"""

type Opts = object
  cmd: string
  args: seq[string]
  a, b: string
  pos: string
  mode: Mode
  paramsFile: string
  dims: Dims
  tol: float
  by: string
  query: string
  spread: float
  fine: bool
  robustness: bool
  top: int
  targets: string
  outFile: string
  quiet: bool
  fA, fB: Fighter

proc parseOpts(): Opts =
  result = Opts(a: "trained", b: "brawler", pos: "Long", mode: mSelfDefense,
                dims: defaultDims, tol: 1e-9, by: "zone", query: "value",
                spread: 0.25, robustness: true, top: 15,
                targets: "data/calibration_targets.json")
  var p = initOptParser(commandLineParams(), shortNoVal = {'h'},
                        longNoVal = @["fine", "quiet", "sport", "no-robustness", "help",
                                      "a-off", "a-stun", "a-lead", "a-legs",
                                      "b-off", "b-stun", "b-lead", "b-legs"])
  for kind, key, val in p.getopt():
    case kind
    of cmdArgument:
      if result.cmd.len == 0: result.cmd = key
      else: result.args.add key
    of cmdLongOption, cmdShortOption:
      case key
      of "a": result.a = val
      of "b": result.b = val
      of "pos": result.pos = val
      of "sport": result.mode = mSport
      of "params": result.paramsFile = val
      of "damage-levels": result.dims.damageLevels = parseInt(val)
      of "tol": result.tol = parseFloat(val)
      of "by": result.by = val
      of "query": result.query = val
      of "spread": result.spread = parseFloat(val)
      of "fine": result.fine = true
      of "no-robustness": result.robustness = false
      of "top": result.top = parseInt(val)
      of "targets": result.targets = val
      of "out": result.outFile = val
      of "quiet": result.quiet = true
      of "a-dmg": result.fA.dmg = parseInt(val)
      of "b-dmg": result.fB.dmg = parseInt(val)
      of "a-off": result.fA.cond = cOff
      of "b-off": result.fB.cond = cOff
      of "a-stun": result.fA.cond = cStunned
      of "b-stun": result.fB.cond = cStunned
      of "a-lead": result.fA.coil = coLead
      of "b-lead": result.fB.coil = coLead
      of "a-legs": result.fA.legs = true
      of "b-legs": result.fB.legs = true
      of "h", "help":
        echo usage
        quit 0
      else:
        raise newException(ValueError, "unknown option --" & key)
    of cmdEnd: discard
  if result.dims.damageLevels < 1 or result.dims.damageLevels > 8:
    raise newException(ValueError, "--damage-levels must be between 1 and 8")

proc loadParams(o: Opts): Params =
  result = defaultParams()
  if o.paramsFile.len > 0: result.applyJson(parseFile(o.paramsFile))

proc situation(o: Opts): State =
  State(pos: parsePos(o.pos), f: [wA: o.fA, wB: o.fB])

proc setup(o: Opts, starts: seq[State]): Setup =
  Setup(params: loadParams(o), a: findStyle(o.a).arsenal, b: findStyle(o.b).arsenal,
        dims: o.dims, mode: o.mode, starts: starts, tol: o.tol)

proc header(g: Game, o: Opts) =
  if not o.quiet:
    echo &"Model: {g.states.len} positions, {g.pairCount} action pairs, " &
         &"{g.outcomeCount} explicit outcomes ({g.mode}, {g.dims.damageLevels} damage levels)"

proc mixLine(g: Game, sol: Solution, w: Who, s: int): string =
  var parts: seq[string]
  for (a, x) in mix(g, sol, w, s):
    if x > 0.005: parts.add &"{a.name} {pct(x)}"
  parts.join(", ")

proc cmdSolve(o: Opts) =
  let st = setup(o, @[situation(o)])
  let g = build(st)
  header(g, o)
  var sol = solveGame(g, o.tol)
  certify(g, sol)
  let label = if o.mode == mSelfDefense: "P(safe)" else: "P(A wins)"
  echo &"{o.a} (A) vs {o.b} (B) from {g.states[g.start]}: {label} = {sol.value[g.start]:.4f}"
  echo &"Certificate: A's strategy guarantees >= {sol.floorStart:.9f}, B's concedes <= {sol.ceilingStart:.9f} " &
       &"(exploitability {max(0.0, sol.exploitability):.1e}; worst position {max(0.0, sol.worstExploitability):.1e}; " &
       &"{sol.sweeps} exact + {sol.evalSweeps} fast sweeps, {sol.seconds:.1f}s)"
  echo report(g, sol, fightStats(g, sol))
  echo ""
  echo "Opening:"
  echo "  A: " & mixLine(g, sol, wA, g.start)
  echo "  B: " & mixLine(g, sol, wB, g.start)

proc cmdExplain(o: Opts) =
  let s = situation(o)
  let st = setup(o, @[s])
  let g = build(st)
  header(g, o)
  let sol = solveGame(g, o.tol)
  let id = g.stateId(s)
  echo &"Position: {g.states[id]}"
  echo &"Value under optimal play: {sol.value[id]:.4f}   (if it ended now: {g.stopValue[id]:.3f})"
  echo "A plays: " & mixLine(g, sol, wA, id)
  echo "B plays: " & mixLine(g, sol, wB, id)
  echo ""
  echo "Value after this beat (rows: A, columns: B):"
  let m = g.nActs(wA, id)
  let k = g.nActs(wB, id)
  var head = alignLeft("", 12)
  for j in 0 ..< k: head &= align(g.act(wB, id, j).name, 10)
  echo head
  for i in 0 ..< m:
    var line = alignLeft(g.act(wA, id, i).name, 12)
    for j in 0 ..< k:
      let pair = g.pairIndex(id, i, j)
      var v = 0.0
      for t in g.outOff[pair] ..< g.outOff[pair + 1]:
        let tg = g.target[t]
        v += g.prob[t] * (if tg >= 0: sol.value[tg] else: terminalValue(toTerminal(tg)))
      line &= align(formatFloat(v, ffDecimal, 3), 10)
    echo line

proc cmdAblate(o: Opts) =
  var st = setup(o, scenarioStates())
  let groups = case o.by
    of "technique": techniqueGroups(st.a)
    of "zone": zoneGroups(st.a)
    of "mechanics": mechanicsGroups(st.a)
    else: raise newException(ValueError, "--by must be technique, zone or mechanics")
  let t0 = epochTime()
  let (base, rows) = ablate(st, groups, progress = not o.quiet)
  var mean = 0.0
  for b in base: mean += b / base.len.float
  echo &"{o.a} vs {o.b}: average P(safe) over the {base.len} playbook situations = {mean:.4f}"
  echo &"Worth of each {o.by} (average drop in P(safe), points, if you could not use it):"
  for r in rows:
    echo &"  {r.label:<16} {-100 * r.mean:>6.2f}   (" & r.removed.toSeq.mapIt(it.name).join(", ") & ")"
  if not o.quiet: echo &"({epochTime() - t0:.0f}s)"

proc cmdMatchups(o: Opts) =
  var st = setup(o, @[situation(o)])
  let defenders = @["trained", "untrained"]
  let attackers = @["brawler", "striker", "grappler"]
  let m = matchups(st, defenders, attackers, progress = not o.quiet)
  echo &"P(safe) from {o.pos}:"
  var head = alignLeft("", 11)
  for a in attackers: head &= align(a, 11)
  echo head
  for i, d in defenders:
    var line = alignLeft(d, 11)
    for j in 0 ..< attackers.len: line &= align(formatFloat(m[i][j][0], ffDecimal, 3), 11)
    echo line

proc cmdSensitivity(o: Opts) =
  let st = setup(o, @[situation(o)])
  var q: Query
  let parts = o.query.split(':')
  case parts[0]
  of "value":
    q = Query(kind: qValue, label: &"value of {o.pos} for {o.a} vs {o.b}")
  of "ablate":
    let t = parseAction(parts[1])
    q = Query(kind: qAblation, removed: {t}, label: &"change in value of {o.pos} without {t.name}")
  of "usage":
    let t = parseAction(parts[1])
    q = Query(kind: qUsage, technique: t, label: &"uses of {t.name} per encounter from {o.pos}")
  else: raise newException(ValueError, "unknown query: " & o.query)
  let r = sensitivity(q, st, o.spread, o.fine, progress = not o.quiet)
  echo render(r, o.top)

proc cmdCalibrate(o: Opts) =
  let t = loadTargets(o.targets)
  var st = setup(o, @[startState()])
  st.mode = mSport
  st.a = findStyle("complete").arsenal
  st.b = st.a
  let (p, trace) = calibrate(st, t, progress = not o.quiet)
  let last = trace[^1]
  echo &"Targets: KO {pct(t.ko)}  submission {pct(t.sub)}  decision {pct(t.decision)}  strike accuracy {pct(t.strikeAccuracy)}"
  echo &"Model:   KO {pct(last.ko)}  submission {pct(last.sub)}  decision {pct(last.decision)}  strike accuracy {pct(last.accuracy)}"
  echo &"Fitted knobs: stopChance {p.stopChance:.5f}  damageScale {p.damageScale:.4f}  " &
       &"submissionScale {p.submissionScale:.4f}  grappleScale {p.grappleScale:.4f}  hitScale {p.hitScale:.4f}"
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
  if o.outFile.len == 0: raise newException(ValueError, "export needs --out FILE")
  let st = setup(o, scenarioStates())
  let g = build(st)
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
    proc fj(f: Fighter): JsonNode =
      %*{"damage": f.dmg, "condition": ($f.cond)[1 .. ^1], "loaded": ($f.coil)[2 .. ^1], "legsHurt": f.legs}
    positions.add %*{"id": id, "position": s.pos.name, "A": fj(s.f[wA]), "B": fj(s.f[wB]),
                     "value": sol.value[id], "strategy": strat}
  let doc = %*{"defender": o.a, "attacker": o.b, "mode": $o.mode,
               "damageLevels": o.dims.damageLevels, "exploitability": sol.worstExploitability,
               "params": st.params.toJson, "positions": positions}
  writeFile(o.outFile, $doc)
  echo &"Wrote {g.states.len} positions to {o.outFile}"

proc cmdPlaybook(o: Opts) =
  let dir = if o.outFile.len > 0: o.outFile else: "docs/playbook"
  createDir(dir)
  let t0 = epochTime()
  let base = setup(o, scenarioStates())
  let attackers = @["brawler", "striker", "grappler"]
  var matches: seq[MatchReport]
  for a in attackers:
    if not o.quiet: stderr.writeLine &"Solving trained vs {a}..."
    matches.add analyseMatch(base, "trained", a, o.robustness, progress = not o.quiet)
  if not o.quiet: stderr.writeLine "Solving untrained vs brawler..."
  let baseline = analyseMatch(base, "untrained", "brawler", robustness = false,
                              progress = not o.quiet)
  var worths: seq[WorthTable]
  let trained = findStyle("trained").arsenal
  proc titled(w: WorthTable, t: string): WorthTable =
    result = w
    result.title = t
  if not o.quiet: stderr.writeLine "Weapons: techniques vs brawler..."
  worths.add worth(base, "trained", "brawler", techniqueGroups(trained),
                   progress = not o.quiet).titled("Techniques")
  for a in attackers:
    if not o.quiet: stderr.writeLine &"Weapons: targets and mechanics vs {a}..."
    worths.add worth(base, "trained", a, zoneGroups(trained), withHip = true,
                     progress = not o.quiet).titled("Target zones")
    worths.add worth(base, "trained", a, mechanicsGroups(trained),
                     progress = not o.quiet).titled("How force is generated")
  let generated = now().utc.format("yyyy-MM-dd HH:mm 'UTC'")
  var glossary = newJArray()
  for a in Action:
    let t = tech[a]
    glossary.add %*{"action": a.name, "meaning": describeAction(a),
                    "mechanics": (if t.mech == mkNone: "" else: ($t.mech)[2 .. ^1]),
                    "target": (if a in Strikes: t.zone.zoneName else: "")}
  var worthJson = newJArray()
  for w in worths: worthJson.add w.toJson
  let data = %*{
    "generated": generated, "damageLevels": o.dims.damageLevels,
    "robustnessChecked": o.robustness,
    "matches": matches.mapIt(it.toJson), "baseline": baseline.toJson,
    "worths": worthJson, "glossary": glossary, "params": base.params.toJson}
  writeFile(dir / "playbook.json", pretty(data))
  writeFile(dir / "PLAYBOOK.md", markdown(matches, worths, baseline, base.params, generated))
  writeFile(dir / "index.html", html(data))
  echo &"Wrote {dir}/PLAYBOOK.md, {dir}/index.html and {dir}/playbook.json ({epochTime() - t0:.0f}s)"

when isMainModule:
  try:
    let o = parseOpts()
    case o.cmd
    of "playbook": cmdPlaybook(o)
    of "solve": cmdSolve(o)
    of "explain": cmdExplain(o)
    of "ablate": cmdAblate(o)
    of "matchups": cmdMatchups(o)
    of "sensitivity": cmdSensitivity(o)
    of "calibrate": cmdCalibrate(o)
    of "params": cmdParams(o)
    of "export": cmdExport(o)
    of "", "help": echo usage
    else: raise newException(ValueError, "unknown command: " & o.cmd)
  except ValueError, KeyError, IOError, OSError:
    stderr.writeLine "error: " & getCurrentExceptionMsg()
    stderr.writeLine "run `fightsolve help` for usage"
    quit 1
