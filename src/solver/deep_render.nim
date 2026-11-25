## Turn the cached results of a deep analysis into the static outputs:
## PLAYBOOK.md, DEEP_ANALYSIS.md, index.html (with the tablebase explorer),
## playbook.json and tablebase/*.json.

import std/[algorithm, json, math, os, sequtils, strformat, strutils, tables, times]
import core, params, studies, playbook, playbook_render, deep

proc pts(x: float): string = formatFloat(100.0 * x, ffDecimal, 1) & "%"

proc delta(x: float): string =
  let v = 100.0 * x
  (if v >= 0: "+" else: "") & formatFloat(v, ffDecimal, 2)

proc worthFrom(t: AblationTable, title: string, hip: (seq[float], seq[float])): WorthTable =
  result = WorthTable(title: title, defender: "trained", attacker: t.attacker,
                      hipOn: hip[0], hipOff: hip[1])
  for (label, deltas, mean) in t.rows:
    result.rows.add AblationRow(label: label, deltas: deltas, mean: mean)

type CrossRow = object
  scenario: string
  action: Action
  worst, mean: float
  perAttacker: seq[(string, float)]
  bestPer: seq[(string, Action)]

proc crossProfile(matches: seq[MatchReport]): seq[CrossRow] =
  ## Against an attacker of unknown type: the response with the best
  ## worst case over the attacker types (scores are each type's "expected").
  if matches.len == 0: return
  for k in 0 ..< matches[0].scenarios.len:
    var scores = initTable[Action, seq[(string, float)]]()
    for m in matches:
      for r in m.scenarios[k].responses:
        scores.mgetOrPut(r.action, @[]).add (m.attacker, r.expected)
    var best = CrossRow(scenario: matches[0].scenarios[k].scenario.title, worst: -1.0)
    for a, lst in scores:
      if lst.len != matches.len: continue
      var w = Inf
      var mean = 0.0
      for (_, v) in lst:
        w = min(w, v)
        mean += v / lst.len.float
      if w > best.worst + 1e-12 or (abs(w - best.worst) <= 1e-12 and mean > best.mean):
        best.action = a
        best.worst = w
        best.mean = mean
        best.perAttacker = lst
    for m in matches: best.bestPer.add (m.attacker, m.scenarios[k].responses[0].action)
    result.add best

proc deepMarkdown(cfg: DeepConfig, units: seq[PlannedUnit], matches: seq[MatchReport],
                  untrained: seq[MatchReport], rob: Table[string, seq[ScenarioRobustness]],
                  ablations: Table[string, Table[string, AblationTable]],
                  hips: Table[string, (seq[float], seq[float])],
                  exhaustiveStats: seq[(string, string, int)], generated: string): string =
  var o: seq[string]
  template add(s: string) = o.add s
  add "# Deep analysis"
  add ""
  add &"*Generated {generated} by `fightsolve deep`. Companion to [PLAYBOOK.md](PLAYBOOK.md); " &
      "the model is described in [SOLVER.md](../SOLVER.md).*"
  add ""
  add "## What was computed"
  add ""
  var counts = initCountTable[string]()
  for u in units: counts.inc u.group
  add &"{units.len} exact solves, each a complete game solved to equilibrium:"
  add ""
  add &"- **Full analyses** ({counts[\"full\"]}): every situation for each defender and attacker type: " &
      &"responses, answers to attacks, optimal lines to depth {cfg.lineDepth}, and the complete " &
      "tablebase (best responses at every reachable position)."
  var combosDone = 0
  for u in units:
    if u.group == "combos" and not loadResult(cfg, u).isNil: inc combosDone
  add &"- **Exhaustive combination search** ({counts[\"combos\"]}, {combosDone} finished): every plan of " &
      &"2 to {cfg.comboLength} actions in every situation, keeping only plans whose every step is " &
      &"performed at least {pts(cfg.minExecuted)} of the time (an exact cut: a longer plan is never " &
      "performed in full more often than its prefix). Situations whose search has not finished yet " &
      "show beam-searched combinations in the playbook."
  if counts["oat"] > 0:
    add &"- **One parameter at a time** ({counts[\"oat\"]}): every self-defense parameter scaled by " &
        cfg.spreads.mapIt("×" & $it).join(", ") & ", for each attacker type."
  if counts["mc"] > 0:
    add &"- **Joint perturbation** ({counts[\"mc\"]}): {cfg.mcSamples} samples per attacker type with " &
        &"every parameter multiplied by an independent log-normal factor (σ = {cfg.mcSigma})."
  if counts["grid"] > 0:
    add &"- **Discretisation** ({counts[\"grid\"]}): the same game on " &
        cfg.grids.mapIt($it).join(" and ") & " damage levels instead of 4."
  add &"- **Weapons** ({counts[\"ablate\"] + counts[\"zone\"] + counts[\"mechanics\"] + counts[\"hip\"]}): " &
      "every technique, target zone and force mechanism removed in turn, and hip loading switched off."
  if cfg.pairs:
    add &"- **Synergy** ({counts[\"pair\"]}): every pair of techniques removed together."
  add ""
  if exhaustiveStats.len > 0:
    var total = 0
    for (_, _, n) in exhaustiveStats: total += n
    add &"The exhaustive combination search scored {total} plans in total."
    add ""

  add "## What drives the recommendations"
  add ""
  add "How often a single-parameter change (any factor) flipped a situation's top response, summed " &
      "over situations and attacker types. Parameters that never flip anything are not listed."
  add ""
  var flipCount = initCountTable[string]()
  for a, lst in rob:
    for r in lst:
      for (lbl, _) in r.oatFlips:
        flipCount.inc lbl.split(" x")[0]
  flipCount.sort()
  if flipCount.len == 0:
    add "No single-parameter change flipped any top response."
  else:
    add "| Parameter | Flips |"
    add "|---|---|"
    var i = 0
    for k, v in flipCount:
      if i >= 25: break
      add &"| {k} | {v} |"
      inc i
  add ""

  add "## Robustness by situation"
  add ""
  for a in cfg.attackers:
    if a notin rob: continue
    add &"### Against a {a}"
    add ""
    add "| Situation | Top response | Joint perturbation: holds | P(safe) 5% / 50% / 95% | Single changes: holds | Finer grids |"
    add "|---|---|---|---|---|---|"
    for k, r in rob[a]:
      let mc = if r.mcChecks > 0: pts(r.mcHolds.float / r.mcChecks.float) else: "-"
      let g = r.grid.mapIt(&"{it[0]}: {it[1]}").join(", ")
      add &"| {scenarios[k].title} | {r.top} | {mc} | {pts(r.valueQ[0])} / {pts(r.valueQ[1])} / {pts(r.valueQ[2])} | " &
          &"{r.oatHolds}/{r.oatChecks} | {g} |"
    add ""

  add "## Against an attacker of unknown type"
  add ""
  add "The response with the best worst case over the three attacker types (each scored as " &
      "*expected* against that type's optimal play)."
  add ""
  add "| Situation | Response | Worst case | Average | Best response per type |"
  add "|---|---|---|---|---|"
  for c in crossProfile(matches):
    add &"| {c.scenario} | **{c.action.name}** | {pts(c.worst)} | {pts(c.mean)} | " &
        c.bestPer.mapIt(&"{it[0]}: {it[1].name}").join(", ") & " |"
  add ""

  add "## What training buys"
  add ""
  if untrained.len > 0:
    var head = "| Situation |"
    var sep = "|---|"
    for u in untrained:
      head &= &" vs {u.attacker}: untrained → trained |"
      sep &= "---|"
    add head
    add sep
    for k, sc in scenarios:
      var row = &"| {sc.title} |"
      for u in untrained:
        var tr = NaN
        for m in matches:
          if m.attacker == u.attacker: tr = m.scenarios[k].value
        row &= &" {pts(u.scenarios[k].value)} → {pts(tr)} |"
      add row
    add ""

  add "## Weapons, against every attacker type"
  add ""
  add "Average change in P(safe) over the ten situations, in percentage points, when the " &
      "trained defender cannot use it."
  add ""
  for (group, title) in [("zone", "Target zones"), ("mechanics", "How force is generated"),
                       ("ablate", "Techniques")]:
    add &"### {title}"
    add ""
    var labels: seq[string]
    var byAtt = initTable[string, Table[string, float]]()
    for a in cfg.attackers:
      if a notin ablations or group notin ablations[a]: continue
      byAtt[a] = initTable[string, float]()
      for (l, _, m) in ablations[a][group].rows:
        byAtt[a][l] = m
        if l notin labels: labels.add l
    var withMean: seq[(float, string)]
    for l in labels:
      var s = 0.0
      for a, t in byAtt: s += t.getOrDefault(l, 0.0)
      withMean.add (s, l)
    withMean.sort(proc(x, y: (float, string)): int = cmp(x[0], y[0]))
    var head = "| Without |"
    var sep = "|---|"
    for a in cfg.attackers:
      if a in byAtt:
        head &= &" vs {a} |"
        sep &= "---|"
    add head
    add sep
    for (_, l) in withMean:
      var row = &"| {l} |"
      for a in cfg.attackers:
        if a in byAtt: row &= &" {delta(byAtt[a].getOrDefault(l, 0.0))} |"
      add row
    add ""
  add "### Hip loading"
  add ""
  for a in cfg.attackers:
    if a notin hips or hips[a][0].len == 0: continue
    var d = 0.0
    for i in 0 ..< hips[a][0].len: d += (hips[a][0][i] - hips[a][1][i]) / hips[a][0].len.float
    add &"- vs {a}: if rotational strikes did not need the loaded side, average P(safe) would change by {delta(-d)} points."
  add ""

  if cfg.pairs:
    add "## Synergy between techniques"
    add ""
    add "Interaction = change when both are removed − change when each is removed alone " &
        "(average over situations, percentage points). Negative: the pair backs each other up — " &
        "losing both costs more than the sum. Positive: either one covers for the other."
    add ""
    for a in cfg.attackers:
      if a notin ablations or "pair" notin ablations[a] or "ablate" notin ablations[a]: continue
      let syn = synergy(ablations[a]["ablate"], ablations[a]["pair"])
      add &"### Against a {a}"
      add ""
      add "| Pair | Interaction | Both removed |"
      add "|---|---|---|"
      for i, (l, inter, both) in syn:
        if i >= 12: break
        add &"| {l} | {delta(inter)} | {delta(both)} |"
      var subs = syn.filterIt(it[1] > 1e-6)
      subs.reverse()
      if subs.len > 0:
        add ""
        add "Strongest substitutes:"
        add ""
        for i, (l, inter, both) in subs:
          if i >= 6: break
          add &"- {l}: interaction {delta(inter)}, both removed {delta(both)}"
      add ""

  add "## The tablebase"
  add ""
  add "`tablebase/<defender>-vs-<attacker>.json` holds every position reachable from the ten " &
      "situations: who is where, each fighter's damage, condition, hip loading and legs, " &
      "P(safe) under optimal play, and the three best responses with their scores. " &
      "`index.html` has an explorer for it."
  add ""
  for m in matches & untrained:
    add &"- {m.defender} vs {m.attacker}: {m.states} positions, exploitability {m.exploitability:.1e}"
  add ""
  o.join("\n")

proc buildDeepOutputs*(cfg: DeepConfig, units: seq[PlannedUnit]) =
  let generated = now().utc.format("yyyy-MM-dd HH:mm 'UTC'")
  createDir(cfg.outDir)
  createDir(cfg.outDir / "tablebase")
  var matches, untrained: seq[MatchReport]
  var tablebases = newJObject()
  var exhaustiveStats: seq[(string, string, int)]
  # exhaustive search results, by (defender, attacker, scenario)
  var exhaustive = initTable[string, JsonNode]()
  for u in units:
    if u.group != "combos": continue
    let r = loadResult(cfg, u)
    if r.isNil: continue
    exhaustive[&"{u.spec.defender}|{u.spec.attacker}|{u.spec.scenario}"] = r
    exhaustiveStats.add (&"{u.spec.defender}-vs-{u.spec.attacker}", u.spec.scenario, r["evaluated"].getInt)
  for u in units:
    if u.group != "full": continue
    let r = loadResult(cfg, u)
    if r.isNil: continue
    var m = parseMatchReport(r["match"])
    let name = &"{u.spec.defender}-vs-{u.spec.attacker}"
    writeFile(cfg.outDir / "tablebase" / (name & ".json"), $r["tablebase"])
    for rep in m.scenarios.mitems:
      let k = &"{u.spec.defender}|{u.spec.attacker}|{rep.scenario.id}"
      if k notin exhaustive: continue
      let ex = exhaustive[k]
      var combos: seq[ComboScore]
      for (key, n) in [("best", 6), ("striking", 4), ("decisive", 4)]:
        for i, c in ex[key].getElems:
          if i < n: combos.add parseCombo(c)
      for c in rep.combos:
        if not c.source.startsWith("discovered"): combos.add c    # classic / documented
      rep.combos = combos
    if u.spec.defender == "trained":
      tablebases[u.spec.attacker] = r["tablebase"]
      matches.add m
    else:
      untrained.add m
  # robustness from the summary units
  var rob = initTable[string, seq[ScenarioRobustness]]()
  for a in cfg.attackers:
    rob[a] = aggregateRobustness(cfg, units, a)
  for m in matches.mitems:
    let lst = rob.getOrDefault(m.attacker)
    for k in 0 ..< min(lst.len, m.scenarios.len):
      let r = lst[k]
      var rb = m.scenarios[k].robustness
      rb.oatChecks = r.oatChecks
      rb.oatHolds = r.oatHolds
      rb.mcChecks = r.mcChecks
      rb.mcHolds = r.mcHolds
      rb.checks = r.oatChecks + r.mcChecks
      rb.sameTop = r.oatHolds + r.mcHolds
      rb.displacedBy = r.oatFlips
      rb.valueLow = r.valueQ[0]
      rb.valueHigh = r.valueQ[2]
      rb.mcTops = @[]
      for t, n in r.mcTops: rb.mcTops.add (t, n)
      rb.mcTops.sort(proc(x, y: (string, int)): int = cmp(y[1], x[1]))
      rb.grid = r.grid
      rb.grid.sort(proc(x, y: (int, string, float)): int = cmp(x[0], y[0]))
      m.scenarios[k].robustness = rb
  # weapons
  var ablations = initTable[string, Table[string, AblationTable]]()
  var hips = initTable[string, (seq[float], seq[float])]()
  for a in cfg.attackers:
    ablations[a] = initTable[string, AblationTable]()
    for grp in ["ablate", "zone", "mechanics", "pair"]:
      ablations[a][grp] = aggregateAblation(cfg, units, a, grp)
    var base, hip: JsonNode
    for u in units:
      if u.spec.attacker != a: continue
      if u.group == "base": base = loadResult(cfg, u)
      if u.group == "hip": hip = loadResult(cfg, u)
    if not base.isNil and not hip.isNil:
      var on, off: seq[float]
      for k in 0 ..< base["scenarios"].len:
        on.add base["scenarios"][k]["value"].getFloat
        off.add hip["scenarios"][k]["value"].getFloat
      hips[a] = (on, off)
  var worths: seq[WorthTable]
  for a in cfg.attackers:
    let hip = hips.getOrDefault(a)
    worths.add worthFrom(ablations[a]["zone"], "Target zones", hip)
    worths.add worthFrom(ablations[a]["mechanics"], "How force is generated", (@[], @[]))
  if "brawler" in ablations:
    worths.add worthFrom(ablations["brawler"]["ablate"], "Techniques", (@[], @[]))
  var baseline = MatchReport(attacker: "brawler")
  for u in untrained:
    if u.attacker == "brawler": baseline = u
  let p = defaultParams()
  writeFile(cfg.outDir / "PLAYBOOK.md", markdown(matches, worths, baseline, p, generated))
  writeFile(cfg.outDir / "DEEP_ANALYSIS.md",
            deepMarkdown(cfg, units, matches, untrained, rob, ablations, hips, exhaustiveStats, generated))
  var glossary = newJArray()
  for a in Action:
    let t = tech[a]
    glossary.add %*{"action": a.name, "meaning": describeAction(a),
                    "mechanics": (if t.mech == mkNone: "" else: ($t.mech)[2 .. ^1]),
                    "target": (if a in Strikes: t.zone.zoneName else: "")}
  var worthJson = newJArray()
  for w in worths: worthJson.add w.toJson
  var cross = newJArray()
  for c in crossProfile(matches):
    cross.add %*{"scenario": c.scenario, "action": c.action.name, "worst": c.worst, "mean": c.mean,
                 "bestPer": c.bestPer.mapIt(%*[it[0], it[1].name])}
  let data = %*{
    "generated": generated, "damageLevels": 4, "robustnessChecked": true, "deep": true,
    "settings": {"comboLength": cfg.comboLength, "minExecuted": cfg.minExecuted,
                 "mcSamples": cfg.mcSamples, "mcSigma": cfg.mcSigma, "spreads": cfg.spreads,
                 "grids": cfg.grids, "units": units.len},
    "matches": matches.mapIt(it.toJson), "baseline": baseline.toJson,
    "untrained": untrained.mapIt(it.toJson),
    "worths": worthJson, "glossary": glossary, "params": p.toJson,
    "crossProfile": cross, "tablebase": tablebases}
  writeFile(cfg.outDir / "playbook.json",
            pretty(block:
              var d = data.copy
              d.delete("tablebase")
              d))
  writeFile(cfg.outDir / "index.html", html(data))
