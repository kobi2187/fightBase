## Human body particularities: what a landed strike does to a target zone.
##
## The target data (force needed, how exposed the zone is, and what kind of
## effect it has) comes straight from `src/vulnerabilities.nim`, the repo's
## body model. This module turns it into explicit probabilities:
##
##   ratio  r = effective force / force the zone needs
##   effect e = clamp(effBase + effSlope * log2(r), 0, 1)
##              (defaults: just reaching the threshold -> 0.2; 16x -> certain)
##
## and, scaled by e, the zone's profile:
## - stun: reflex/pain zones (eyes, groin, nose, liver, solar plexus) cause a
##   one-beat shock, with probability = the zone's compliance x pain
## - damage: disabling/systemic zones (jaw, temples, liver, groin) move the
##   damage level toward incapacitation; zones with long recovery times are
##   more likely to cost two levels at once
## - legs: structural leg zones (knee, thigh, foot) hurt mobility for the rest
##   of the encounter
##
## Small targets are hard to hit exactly: a landed strike is solid with the
## zone's `zonePrecision` (by target size), otherwise it glances off with a
## fraction of its force (`impactEvents` in rules.nim).

import std/[math]
import ../vulnerabilities
import core

type
  ZoneProfile* = object
    force*: float        ## force the zone needs (N), from vulnerabilities.nim
    exposure*: float     ## default exposure, from vulnerabilities.nim
    stun*: float         ## P(stun) at full effect
    dmg1*: float         ## P(+1 damage level) at full effect
    dmg2*: float         ## P(+2 damage levels) at full effect
    legs*: float         ## P(legs hurt) at full effect

  StrikeEffect* = object
    ## One way a landed strike can turn out, with its probability.
    p*: float
    dmg*: int
    stun*: bool
    legs*: bool

proc deriveProfile*(z: VulnerabilityZone): ZoneProfile =
  ## Turn the qualitative flags of the repo's body model into numbers.
  let v = getVulnerabilityData(z)
  let e = v.effectOnHit
  result.force = v.forceRequired
  result.exposure = v.exposureDefault
  result.stun = if e.reflex: clamp(e.compliance * e.pain, 0.0, 1.0) else: 0.0
  # Expected damage levels at full effect.
  var expected = (if e.disabling: 0.6 else: 0.2) + (if e.systemic: 0.2 else: 0.0)
  expected *= clamp(e.pain, 0.0, 1.0)
  # Long recovery = severe: more of the damage comes as two levels at once.
  let share2 = clamp((log10(max(1.0, e.recoveryTime.float)) - 2.0) / 3.0, 0.0, 0.8)
  result.dmg2 = expected * share2 / 2.0
  result.dmg1 = expected * (1.0 - share2)
  result.legs = if z in LegZones and e.structural: (if e.disabling: 0.8 else: 0.4) else: 0.0

const zonePrecision*: array[VulnerabilityZone, float] = [
  ## P(a landed strike hits the zone squarely), by target size.
  vzEyes: 0.35, vzTemples: 0.45, vzNose: 0.6, vzJaw: 0.55, vzEars: 0.5,
  vzThroat: 0.4, vzBackOfHead: 0.6, vzNeck: 0.6,
  vzSolarPlexus: 0.45, vzFloatingRibs: 0.6, vzLiver: 0.45, vzKidneys: 0.5,
  vzSpine: 0.5, vzCollarbone: 0.5,
  vzShoulder: 0.7, vzElbow: 0.5, vzWrist: 0.5, vzFingers: 0.4, vzBicepTendon: 0.5,
  vzGroin: 0.55, vzHip: 0.8, vzKneeFront: 0.5, vzKneeLateral: 0.5, vzAnkle: 0.4,
  vzFoot: 0.6, vzCalf: 0.8, vzThighMuscle: 0.9,
  vzBaseOfSkull: 0.4, vzCenterMass: 1.0]

proc buildProfiles(): array[VulnerabilityZone, ZoneProfile] =
  for z in VulnerabilityZone:
    result[z] = deriveProfile(z)

let zoneProfiles* = buildProfiles()

proc effectStrength*(force, needed, base, slope: float): float =
  if needed <= 0.0: return 1.0
  if force <= 0.0: return 0.0
  clamp(base + slope * log2(force / needed), 0.0, 1.0)

proc strikeEffects*(z: VulnerabilityZone, e: float, dmgMult, stunMult,
                    legsMult: float): seq[StrikeEffect] =
  ## Distribution of what one landed strike of effect strength `e` does.
  ## Damage, stun and leg effects are drawn independently.
  let pr = zoneProfiles[z]
  var d1 = pr.dmg1 * e * dmgMult
  var d2 = pr.dmg2 * e * dmgMult
  if d1 + d2 > 1.0:
    let k = 1.0 / (d1 + d2)
    d1 *= k
    d2 *= k
  let st = clamp(pr.stun * e * stunMult, 0.0, 1.0)
  let lg = clamp(pr.legs * e * legsMult, 0.0, 1.0)
  for (dmg, pd) in [(0, 1.0 - d1 - d2), (1, d1), (2, d2)]:
    if pd <= 1e-15: continue
    for (stun, ps) in [(true, st), (false, 1.0 - st)]:
      if ps <= 1e-15: continue
      for (legs, pl) in [(true, lg), (false, 1.0 - lg)]:
        if pl <= 1e-15: continue
        result.add StrikeEffect(p: pd * ps * pl, dmg: dmg, stun: stun, legs: legs)
