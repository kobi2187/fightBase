## Render the playbook as static files: Markdown for reading in the repo, a
## self-contained HTML page, and the JSON data both are built from.

import std/[algorithm, json, math, sequtils, strformat, strutils, tables, times]
import core, params, studies, playbook

proc pts(x: float): string =
  ## A probability as a percentage with one decimal.
  formatFloat(100.0 * x, ffDecimal, 1) & "%"

proc delta(x: float): string =
  ## A change in probability, in percentage points.
  let v = 100.0 * x
  (if v >= 0: "+" else: "") & formatFloat(v, ffDecimal, 1)

proc plan(c: seq[Action]): string = c.mapIt(it.name).join(" → ")

proc robustLabel*(r: Robustness): string =
  if r.mcChecks > 0:
    return "holds " & $int(round(100.0 * r.mcHolds.float / r.mcChecks.float)) & "%"
  if r.checks == 0: return "not checked"
  if r.sameTop == r.checks: return &"robust ({r.checks}/{r.checks})"
  &"holds in {r.sameTop}/{r.checks}"

proc robustParagraph*(r: Robustness): string =
  if r.mcChecks == 0:
    return &"Robustness of the top response: {robustLabel(r)}" &
      (if r.displacedBy.len > 0:
         ". Changes under: " & r.displacedBy.mapIt(&"{it[0]} → {it[1]}").join("; ")
       else: "") & &". P(safe) across those perturbations: {pts(r.valueLow)} to {pts(r.valueHigh)}."
  let mcPct = 100.0 * r.mcHolds.float / r.mcChecks.float
  result = &"Robustness of the top response: with every assumption perturbed at once, it stays " &
           &"the best (or within half a point of it) in {mcPct:.0f}% of {r.mcChecks} samples"
  var others: seq[string]
  for (t, n) in r.mcTops:
    others.add &"{t} {n}"
  if others.len > 1: result &= " (best response per sample: " & others.join(", ") & ")"
  result &= &". One parameter at a time: holds in {r.oatHolds}/{r.oatChecks} changes"
  if r.displacedBy.len > 0:
    let shown = r.displacedBy[0 ..< min(6, r.displacedBy.len)]
    result &= "; flips under " & shown.mapIt(&"{it[0]} → {it[1]}").join("; ") &
              (if r.displacedBy.len > 6: &" and {r.displacedBy.len - 6} more" else: "")
  result &= &". P(safe) under joint perturbation: {pts(r.valueLow)} to {pts(r.valueHigh)} (5th to 95th percentile)."
  if r.grid.len > 0:
    result &= " Finer damage grids: " & r.grid.mapIt(&"{it[0]} levels → {it[1]} ({pts(it[2])})").join(", ") & "."

proc describeAction*(a: Action): string =
  case a
  of aAdvance: "step in"
  of aRetreat: "step back"
  of aCircle: "step offline to the outside angle"
  of aFlee: "run"
  of aCover: "cover / guard"
  of aSlip: "slip or L-step off the line"
  of aParry: "deflect (parry, tan sao)"
  of aCounter: "simultaneous block-and-counter"
  of aFeint: "feint"
  of aFingerJab: "finger jab to the eyes (whip)"
  of aJab: "jab to the nose"
  of aCross: "rear cross / palm heel to the jaw"
  of aHook: "lead hook to the temple"
  of aHaymaker: "wild haymaker"
  of aBodyHook: "shovel hook to the liver"
  of aElbow: "elbow to the temple"
  of aGroinKick: "snap kick to the groin (whip)"
  of aObliqueKick: "oblique / stop kick to the knee"
  of aLowKick: "low round kick to the thigh"
  of aRoundKick: "round kick to the body"
  of aTeep: "push kick to the solar plexus"
  of aKnee: "knee to the groin (to the face if bent over)"
  of aHeadbutt: "headbutt to the nose"
  of aStomp: "stomp (foot; head if down)"
  of aPush: "two-hand shove"
  of aGrab: "grab / tie up"
  of aShoot: "tackle / takedown"
  of aSprawl: "sprawl against a tackle"
  of aPummel: "fight for the better grip"
  of aThrow: "throw / trip / drag down"
  of aBreak: "break the grip and separate"
  of aChoke: "choke"
  of aTurn: "turn into him"
  of aFollow: "follow him to the ground"
  of aBackOff: "step away from the downed fighter"
  of aGetUp: "technical stand-up"
  of aUpkick: "upkick from the ground"
  of aPound: "strike from top"
  of aPass: "improve top position"
  of aHold: "hold / control"
  of aDisengage: "get up and away from top"
  of aEscape: "escape from underneath"
  of aSweep: "sweep from guard"
  of aGuardSub: "submission from guard"

proc markdown*(matches: seq[MatchReport], worths: seq[WorthTable],
               baseline: MatchReport, p: Params, generated: string): string =
  var o: seq[string]
  template add(s: string) = o.add s
  add "# Self-defense playbook"
  add ""
  add &"*Generated {generated} by `fightsolve` from the model in `src/solver/`. " &
      "Every number below is an output of that model under its stated assumptions, " &
      "not a measurement. Read the [model description](../SOLVER.md) before relying on any of it.*"
  add ""
  add "## How to read this"
  add ""
  add "- **P(safe)** is the probability that you come out safe when both sides play optimally: " &
      "you get away, or the attacker is incapacitated or choked out. If the encounter ends " &
      "without a finish, the score is the harm you carry at that moment."
  add "- **Expected**: the response's P(safe) against an attacker who plays his optimal " &
      "strategy, with optimal play afterwards. **If he picks the best reply**: the same, " &
      "but he chooses this beat's reply knowing your move."
  add "- **Answers to attacks**: your best replies once you know what he is opening with."
  add "- **Lines**: the action sequences optimal play actually follows, with how often."
  add "- **Combinations** are plans you commit to. *Expected* is against his optimal play; " &
      "*if he reads it* is against an attacker who knows the whole plan. *Dealt*, *stuns* and " &
      "*taken* are expected damage levels and stuns during the combination; *executed* is how " &
      "often every step was actually performed (each step must be possible in the position the " &
      "previous one led to)."
  if matches.len > 0 and matches[0].scenarios.len > 0 and matches[0].scenarios[0].robustness.mcChecks > 0:
    add "- **Robustness**: every top response was re-derived hundreds of times with all " &
        "assumptions perturbed at once (each parameter scaled by an independent random factor " &
        "around 1), and again with each parameter changed on its own. *holds N%* is the share of " &
        "joint perturbations in which it stayed the best response or within half a point of it. " &
        "Details in [DEEP_ANALYSIS.md](DEEP_ANALYSIS.md)."
  else:
    add "- **Robustness**: the top response was re-derived with every family of assumptions " &
        "scaled by ±25% (24 re-solves per attacker). *robust* means it stayed the best, or within " &
        "half a point of the best, every time; *not checked* means the build skipped this step."
  add ""

  # ---- summary table
  add "## Best first response, by situation"
  add ""
  var head = "| Situation |"
  var sep = "|---|"
  for m in matches:
    head &= &" vs {m.attacker} |"
    sep &= "---|"
  let hasBaseline = baseline.scenarios.len > 0
  if hasBaseline:
    head &= &" untrained vs {baseline.attacker} |"
    sep &= "---|"
  add head
  add sep
  for k, sc in scenarios:
    var row = &"| {sc.title} |"
    for m in matches:
      let r = m.scenarios[k]
      row &= &" **{r.responses[0].action.name}** · P(safe) {pts(r.value)} · {robustLabel(r.robustness)} |"
    if hasBaseline: row &= &" {pts(baseline.scenarios[k].value)} |"
    add row
  add ""
  add "Technique names are explained in the [glossary](#glossary)."
  add ""

  # ---- per scenario
  for k, sc in scenarios:
    add &"## {sc.title}"
    add ""
    add &"*{sc.situation}*"
    add ""
    for mi, m in matches:
      let r = m.scenarios[k]
      let oc = r.outcome
      add &"### Against a {m.attacker}: P(safe) {pts(r.value)}"
      add ""
      add &"How it ends with optimal play: you get away {pts(oc.finishes[tAEscape])}, " &
          &"incapacitate him {pts(oc.finishes[tAKO])}, choke him {pts(oc.finishes[tASub])}; " &
          &"you are incapacitated {pts(oc.finishes[tBKO])}, choked {pts(oc.finishes[tBSub])}; " &
          &"no finish {pts(oc.stopped)} (about {int(round(oc.beats))} beats)."
      add ""
      add robustParagraph(r.robustness)
      add ""
      let full = mi == 0
      add "| Response | Expected | If he picks the best reply | Optimal play uses it |"
      add "|---|---|---|---|"
      for i, x in r.responses:
        if i >= (if full: 8 else: 4): break
        add &"| {x.action.name} ({describeAction(x.action)}) | {pts(x.expected)} | {pts(x.guaranteed)} | {pts(x.mix)} |"
      add ""
      var atk: seq[string]
      for a in r.answers:
        if a.attackerMix < 0.005 and a.attack notin {aHaymaker, aGrab, aShoot, aPush, aChoke, aKnee, aStomp, aCross, aLowKick}:
          continue
        let best = a.answers.mapIt(&"{it[0].name} {pts(it[1])}").join(", ")
        atk.add &"- **{a.attack.name}** (he opens with it {pts(a.attackerMix)} of the time): {best}; worst reply {a.worst[0].name} {pts(a.worst[1])}"
      if atk.len > 0:
        add "Answers to his attacks:"
        add ""
        for x in atk: add x
        add ""
      if full and r.lines.len > 0:
        add "Lines optimal play follows:"
        add ""
        for l in r.lines:
          add &"- {plan(l.actions)}: played {pts(l.prob)} of the time, P(safe) {pts(l.value)}" &
              (if l.finishedSafe > 0.005: &", ends it safely within the line {pts(l.finishedSafe)}" else: "")
        add ""
      if full:
        add "| Combination | Source | Expected | If he reads it | Dealt | Stuns | Taken | Executed |"
        add "|---|---|---|---|---|---|---|---|"
        for c in r.combos:
          let src = c.source & (if c.vsAttack.len > 0: &" (he opens with {c.vsAttack})" else: "")
          add &"| {plan(c.plan)} | {src} | {pts(c.expected)} | {pts(c.guaranteed)} | " &
              &"{c.dealt:.2f} | {c.stuns:.2f} | {c.taken:.2f} | {pts(c.executed)} |"
        add ""

  # ---- body and mechanics
  add "## What your weapons are worth"
  add ""
  add "Each row removes something from your arsenal and re-solves every situation. " &
      "The number is the average change in P(safe) across the ten situations, in percentage points " &
      "(removing an option can never help you, so it is always zero or negative)."
  add ""
  for w in worths:
    add &"### {w.title}: {w.defender} vs {w.attacker}"
    add ""
    if w.hipOn.len > 0:
      var d = 0.0
      for i in 0 ..< w.hipOn.len: d += (w.hipOn[i] - w.hipOff[i]) / w.hipOn.len.float
      add &"Hip loading: if every rotational strike had full power and speed from either side " &
          &"(no need to chain rotations), your average P(safe) would change by {delta(-d)} points."
      add ""
    add "| Without | Change in P(safe) | Situations hurt most |"
    add "|---|---|---|"
    for r in w.rows:
      var worst: seq[(float, int)]
      for i, d in r.deltas: worst.add (d, i)
      worst.sort(proc(x, y: (float, int)): int = cmp(x[0], y[0]))
      var names: seq[string]
      for (d, i) in worst:
        if d < -0.0005 and names.len < 3: names.add &"{scenarios[i].title} ({delta(d)})"
      add &"| {r.label} | {delta(r.mean)} | {names.join(\"; \")} |"
    add ""

  # ---- training
  if hasBaseline:
    add &"## What training buys (untrained vs {baseline.attacker})"
    add ""
    add "| Situation | Untrained P(safe) | Best untrained response | Trained P(safe) |"
    add "|---|---|---|---|"
    let trainedSame = block:
      var t = -1
      for i, m in matches:
        if m.attacker == baseline.attacker: t = i
      t
    for k, sc in scenarios:
      let u = baseline.scenarios[k]
      let tr = if trainedSame >= 0: pts(matches[trainedSame].scenarios[k].value) else: "-"
      add &"| {sc.title} | {pts(u.value)} | {u.responses[0].action.name} | {tr} |"
    add ""

  # ---- glossary
  add "## Glossary"
  add ""
  add "| Technique | Meaning | How it generates force | Target |"
  add "|---|---|---|---|"
  for a in Action:
    let t = tech[a]
    let mech = if t.mech == mkNone: "" else: ($t.mech)[2 .. ^1]
    let zone = if a in Strikes: t.zone.zoneName else: ""
    add &"| {a.name} | {describeAction(a)} | {mech} | {zone} |"
  add ""
  add "## Certificate"
  add ""
  for m in (if hasBaseline: matches & baseline else: matches):
    add &"- {m.defender} vs {m.attacker}: {m.states} positions, {m.pairs} action pairs, " &
        &"{m.outcomes} explicit outcomes; largest gap between the guaranteed floor and " &
        &"ceiling over all positions {m.exploitability:.1e} (0 = exact equilibrium)."
  add ""
  o.join("\n")

const htmlTemplate = staticRead("playbook_template.html")

proc html*(data: JsonNode): string =
  htmlTemplate.replace("/*__PLAYBOOK_DATA__*/null", $data)
