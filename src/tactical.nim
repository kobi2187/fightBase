## Tactical decision making - integrates vulnerabilities with move selection

import fight_types
import vulnerabilities

proc scoreMoveByTarget*(
  move: Move,
  attacker: Fighter,
  defender: Fighter,
  distance: float,
  preferLowExposure: bool = false
): float =
  ## Score a move based on its target effectiveness
  ## Higher score = better tactical choice

  # Non-offensive moves get base score
  if move.moveType != mtOffensive:
    result = 1.0
    # Positional moves create options
    if move.moveType == mtPositional:
      result = float(move.optionsCreated) * 0.5
    # Evasion and deflection preserve energy
    elif move.moveType in [mtEvasion, mtDeflection]:
      result = 2.0 / (move.energyCost + 0.1)
    # Defensive moves reduce exposure
    elif move.moveType == mtDefensive:
      result = (1.0 - move.exposureRisk) * 1.5
    return result

  # Offensive moves - score by target quality
  if move.targets.len == 0:
    return 0.5  # No specific target = low score

  var bestTargetScore = 0.0

  for targetName in move.targets:
    # Parse target name to VulnerabilityZone
    # For now, assume targets are named like VulnerabilityZone enum values
    var zone: VulnerabilityZone
    try:
      zone = parseEnum[VulnerabilityZone](targetName)
    except:
      continue  # Skip invalid target names

    let vulnData = getVulnerabilityData(zone)
    let reachability = calculateReachability(attacker, defender, zone, distance)

    if reachability < 0.1:
      continue  # Target not reachable

    # Base score: compliance / force required
    var targetScore = (vulnData.effectOnHit.compliance * 100.0) / (vulnData.forceRequired + 1.0)

    # Multiply by reachability
    targetScore *= reachability

    # Prefer disabling targets
    if vulnData.effectOnHit.disabling:
      targetScore *= 2.0

    # Prefer systemic effects
    if vulnData.effectOnHit.systemic:
      targetScore *= 1.5

    # In tight spots (close distance), strongly prefer low-force targets
    if distance < 0.5:
      targetScore *= (100.0 / (vulnData.forceRequired + 10.0))

    # If preferring low exposure (defensive mindset)
    if preferLowExposure:
      targetScore *= (1.0 - move.exposureRisk + 0.1)

    bestTargetScore = max(bestTargetScore, targetScore)

  # Factor in move's own characteristics
  result = bestTargetScore
  result *= (1.0 - move.energyCost * 0.3)  # Prefer energy-efficient
  result *= float(move.optionsCreated + 1)  # Prefer moves that create options

proc calculateOptionAdvantage*(
  state: FightState,
  who: FighterID,
  viableMoves: seq[Move]
): float =
  ## Calculate how many more options we have than opponent
  ## This implements the "tactical liquidity" concept

  let ourOptions = viableMoves.len

  # Estimate opponent's options (would need actual calculation)
  # For now, use balance and fatigue as proxy
  let opponent = if who == FighterA: state.b else: state.a
  let estimatedOpponentOptions = int(10.0 * opponent.pos.balance * (1.0 - opponent.fatigue))

  result = float(ourOptions) / float(max(estimatedOpponentOptions, 1))

proc scoreMoveTactically*(
  move: Move,
  state: FightState,
  who: FighterID,
  viableMoves: seq[Move]
): float =
  ## Complete tactical scoring combining target selection and option advantage

  let attacker = if who == FighterA: state.a else: state.b
  let defender = if who == FighterA: state.b else: state.a

  # Calculate distance in meters (use state.distance as proxy)
  let distanceMeters = case state.distance:
    of Contact: 0.2
    of Short: 0.5
    of Medium: 1.0
    of Long: 2.0
    of VeryLong: 3.0

  # Defensive fighter prefers low exposure
  let preferLowExposure = attacker.damage > 0.3 or attacker.fatigue > 0.5

  # Base score from target selection
  var score = scoreMoveByTarget(move, attacker, defender, distanceMeters, preferLowExposure)

  # Multiply by option advantage
  let optionAdv = calculateOptionAdvantage(state, who, viableMoves)
  if move.optionsCreated > 0:
    score *= (1.0 + optionAdv * 0.2)  # Reward moves that maintain option advantage

  # Penalize high-exposure moves when we already have advantage
  if optionAdv > 2.0 and move.exposureRisk > 0.5:
    score *= 0.5  # Don't risk it when already winning

  # Reward low-exposure moves in tight spots
  if attacker.pos.balance < 0.5 or state.distance == Contact:
    score *= (1.0 - move.exposureRisk + 0.5)

  result = score
