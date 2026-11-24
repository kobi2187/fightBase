# Self-defense playbook

*Generated 2026-11-24 09:53 UTC by `fightsolve playbook` from the model in `src/solver/`. Every number below is an output of that model under its stated assumptions, not a measurement. Read the [model description](../SOLVER.md) before relying on any of it.*

## How to read this

- **P(safe)** is the probability that you come out safe when both sides play optimally: you get away, or the attacker is incapacitated or choked out. If the encounter ends without a finish, the score is the harm you carry at that moment.
- **Expected**: the response's P(safe) against an attacker who plays his optimal strategy, with optimal play afterwards. **If he picks the best reply**: the same, but he chooses this beat's reply knowing your move.
- **Answers to attacks**: your best replies once you know what he is opening with.
- **Lines**: the action sequences optimal play actually follows, with how often.
- **Combinations** are plans you commit to. *Expected* is against his optimal play; *if he reads it* is against an attacker who knows the whole plan. *Dealt*, *stuns* and *taken* are expected damage levels and stuns during the combination; *executed* is how often every step was possible in the position it reached.
- **Robustness**: the top response was re-derived with every family of assumptions scaled by ±25% (24 re-solves per attacker). *robust* means it stayed the best, or within half a point of the best, every time; *not checked* means the build skipped this step.

## Best first response, by situation

| Situation | vs brawler | vs striker | vs grappler | untrained vs brawler |
|---|---|---|---|---|
| Squared up at kicking range | **Teep** · P(safe) 95.9% · robust (24/24) | **Flee** · P(safe) 96.3% · robust (24/24) | **Teep** · P(safe) 88.6% · robust (24/24) | 83.1% |
| Aggressor at arm's length | **Teep** · P(safe) 94.8% · robust (24/24) | **Teep** · P(safe) 95.3% · robust (24/24) | **Teep** · P(safe) 86.3% · robust (24/24) | 83.2% |
| In your face | **Retreat** · P(safe) 93.2% · robust (24/24) | **Retreat** · P(safe) 94.1% · robust (24/24) | **Retreat** · P(safe) 83.7% · robust (24/24) | 82.0% |
| Grabbed (headlock / dominant grip) | **Break** · P(safe) 69.9% · robust (24/24) | **Break** · P(safe) 73.7% · robust (24/24) | **Break** · P(safe) 63.8% · robust (24/24) | 61.5% |
| Tied up | **Break** · P(safe) 86.3% · holds in 23/24 | **Break** · P(safe) 86.7% · holds in 22/24 | **Throw** · P(safe) 79.8% · holds in 21/24 | 75.5% |
| Grabbed from behind | **Turn** · P(safe) 54.1% · robust (24/24) | **GroinKick** · P(safe) 94.2% · robust (24/24) | **Turn** · P(safe) 50.5% · holds in 23/24 | 48.1% |
| Down, attacker standing over you | **GetUp** · P(safe) 91.1% · robust (24/24) | **GetUp** · P(safe) 91.9% · robust (24/24) | **GetUp** · P(safe) 78.1% · robust (24/24) | 80.6% |
| Tackled, attacker on top in your guard | **Sweep** · P(safe) 93.4% · robust (24/24) | **Sweep** · P(safe) 93.6% · robust (24/24) | **Escape** · P(safe) 70.7% · robust (24/24) | 83.2% |
| Mounted | **Cover** · P(safe) 69.4% · robust (24/24) | **Escape** · P(safe) 86.9% · robust (24/24) | **Cover** · P(safe) 53.4% · robust (24/24) | 62.6% |
| Back taken on the ground | **Cover** · P(safe) 58.4% · robust (24/24) | **Escape** · P(safe) 86.9% · robust (24/24) | **Cover** · P(safe) 45.6% · robust (24/24) | 52.7% |

Technique names are explained in the [glossary](#glossary).

## Squared up at kicking range

*The aggressor is a couple of steps away, both of you standing.*

### Against a brawler: P(safe) 95.9%

How it ends with optimal play: you get away 58.2%, incapacitate him 2.0%, choke him 0.2%; you are incapacitated 0.6%, choked 1.0%; no finish 38.0% (about 9 beats).

Robustness of the top response: robust (24/24). P(safe) across those perturbations: 93.6% to 97.9%.

| Response | Expected | If he picks the best reply | Optimal play uses it |
|---|---|---|---|
| Teep (push kick to the solar plexus) | 95.9% | 95.9% | 100.0% |
| Sprawl (sprawl against a tackle) | 95.4% | 95.0% | 0.0% |
| GroinKick (snap kick to the groin (whip)) | 94.4% | 94.4% | 0.0% |
| ObliqueKick (oblique / stop kick to the knee) | 94.1% | 94.1% | 0.0% |
| Retreat (step back) | 93.8% | 93.8% | 0.0% |
| Cover (cover / guard) | 93.7% | 93.7% | 0.0% |
| Counter (simultaneous block-and-counter) | 93.7% | 93.7% | 0.0% |
| Feint (feint) | 93.7% | 93.7% | 0.0% |

Answers to his attacks:

- **Shoot** (he opens with it 100.0% of the time): Teep 95.9%, Sprawl 95.4%, GroinKick 94.4%; worst reply Flee 87.5%

Lines optimal play follows:

- Teep → Teep: played 30.1% of the time, P(safe) 96.7%
- Teep → Retreat: played 27.4% of the time, P(safe) 92.9%
- Teep → Flee: played 20.9% of the time, P(safe) 98.8%, ends it safely within the line 93.6%
- Teep → Teep → Teep: played 17.3% of the time, P(safe) 96.4%
- Teep → Retreat → Teep: played 14.4% of the time, P(safe) 94.8%
- Teep → Sweep: played 13.7% of the time, P(safe) 93.8%

| Combination | Source | Expected | If he reads it | Dealt | Stuns | Taken | Executed |
|---|---|---|---|---|---|---|---|
| Teep → Teep | discovered | 95.5% | 95.5% | 0.32 | 0.35 | 0.00 | 50.4% |
| Sprawl → Retreat | discovered | 95.4% | 94.0% | 0.00 | 0.00 | 0.06 | 69.6% |
| Sprawl → Hold | discovered | 95.4% | 95.0% | 0.00 | 0.00 | 0.00 | 30.6% |
| Sprawl → Hold → Hold | discovered | 95.4% | 95.0% | 0.00 | 0.00 | 0.00 | 29.8% |
| Sprawl → Retreat → Teep | discovered | 95.4% | 94.0% | 0.11 | 0.12 | 0.06 | 59.5% |
| Sprawl → Retreat → Retreat | discovered | 95.4% | 93.9% | 0.00 | 0.00 | 0.06 | 66.6% |
| Teep → Teep | discovered (strikes) | 95.5% | 95.5% | 0.32 | 0.35 | 0.00 | 50.4% |
| Teep → GroinKick | discovered (strikes) | 95.3% | 95.1% | 0.35 | 0.40 | 0.00 | 50.4% |
| Teep → Teep → Teep | discovered (strikes) | 95.3% | 95.3% | 0.42 | 0.45 | 0.00 | 44.3% |
| Teep → GroinKick → Teep | discovered (strikes) | 95.1% | 94.8% | 0.44 | 0.49 | 0.00 | 38.9% |
| ObliqueKick → Flee | stop kick to the knee, then run | 94.1% | 88.1% | 0.09 | 0.14 | 0.00 | 1.3% |

### Against a striker: P(safe) 96.3%

How it ends with optimal play: you get away 81.0%, incapacitate him 0.4%, choke him 0.0%; you are incapacitated 2.4%, choked 0.0%; no finish 16.2% (about 4 beats).

Robustness of the top response: robust (24/24). P(safe) across those perturbations: 87.2% to 98.1%.

| Response | Expected | If he picks the best reply | Optimal play uses it |
|---|---|---|---|
| Flee (run) | 96.3% | 95.8% | 75.0% |
| Teep (push kick to the solar plexus) | 96.3% | 95.8% | 25.0% |
| GroinKick (snap kick to the groin (whip)) | 96.0% | 95.9% | 0.0% |
| ObliqueKick (oblique / stop kick to the knee) | 95.8% | 95.6% | 0.0% |

Answers to his attacks:

- **Teep** (he opens with it 74.9% of the time): Flee 96.4%, GroinKick 96.0%, Teep 95.8%; worst reply Advance 93.1%
- **Advance** (he opens with it 25.1% of the time): Teep 97.8%, ObliqueKick 96.5%, Retreat 96.4%; worst reply LowKick 95.2%
- **LowKick** (he opens with it 0.0% of the time): GroinKick 97.2%, Teep 97.0%, Counter 96.8%; worst reply Advance 95.8%

### Against a grappler: P(safe) 88.6%

How it ends with optimal play: you get away 55.8%, incapacitate him 1.9%, choke him 4.6%; you are incapacitated 0.2%, choked 8.7%; no finish 28.8% (about 7 beats).

Robustness of the top response: robust (24/24). P(safe) across those perturbations: 83.6% to 93.5%.

| Response | Expected | If he picks the best reply | Optimal play uses it |
|---|---|---|---|
| Teep (push kick to the solar plexus) | 88.6% | 88.6% | 100.0% |
| Sprawl (sprawl against a tackle) | 87.1% | 86.9% | 0.0% |
| GroinKick (snap kick to the groin (whip)) | 85.4% | 85.4% | 0.0% |
| ObliqueKick (oblique / stop kick to the knee) | 84.4% | 84.4% | 0.0% |

Answers to his attacks:

- **Shoot** (he opens with it 100.0% of the time): Teep 88.6%, Sprawl 87.1%, GroinKick 85.4%; worst reply Flee 82.0%

## Aggressor at arm's length

*Punching range: he can hit you and grab you.*

### Against a brawler: P(safe) 94.8%

How it ends with optimal play: you get away 55.0%, incapacitate him 2.0%, choke him 0.2%; you are incapacitated 1.1%, choked 1.1%; no finish 40.7% (about 10 beats).

Robustness of the top response: robust (24/24). P(safe) across those perturbations: 92.4% to 96.2%.

| Response | Expected | If he picks the best reply | Optimal play uses it |
|---|---|---|---|
| Teep (push kick to the solar plexus) | 94.8% | 94.3% | 58.3% |
| Retreat (step back) | 94.8% | 93.7% | 41.7% |
| GroinKick (snap kick to the groin (whip)) | 94.4% | 93.7% | 0.0% |
| Push (two-hand shove) | 94.1% | 93.5% | 0.0% |
| ObliqueKick (oblique / stop kick to the knee) | 93.7% | 93.5% | 0.0% |
| Sprawl (sprawl against a tackle) | 93.6% | 92.6% | 0.0% |
| Jab (jab to the nose) | 93.5% | 93.3% | 0.0% |
| FingerJab (finger jab to the eyes (whip)) | 93.5% | 93.3% | 0.0% |

Answers to his attacks:

- **Grab** (he opens with it 63.1% of the time): Retreat 95.4%, Teep 94.3%, GroinKick 94.3%; worst reply Grab 86.9%
- **Shoot** (he opens with it 36.9% of the time): Teep 95.5%, Sprawl 95.3%, Push 95.0%; worst reply Grab 92.2%
- **Haymaker** (he opens with it 0.0% of the time): Retreat 96.0%, Teep 95.9%, Slip 95.4%; worst reply Advance 91.3%
- **Push** (he opens with it 0.0% of the time): Teep 96.7%, GroinKick 96.5%, Retreat 96.0%; worst reply Grab 92.5%

Lines optimal play follows:

- Retreat → Teep: played 21.8% of the time, P(safe) 95.9%
- Teep → Teep: played 18.5% of the time, P(safe) 96.2%
- Retreat → Retreat: played 12.1% of the time, P(safe) 93.2%
- Teep → Flee: played 10.0% of the time, P(safe) 98.8%, ends it safely within the line 93.5%
- Teep → Teep → Teep: played 9.3% of the time, P(safe) 96.4%
- Teep → Break: played 9.2% of the time, P(safe) 87.7%

| Combination | Source | Expected | If he reads it | Dealt | Stuns | Taken | Executed |
|---|---|---|---|---|---|---|---|
| Retreat → Teep | discovered | 94.8% | 93.7% | 0.11 | 0.13 | 0.00 | 52.9% |
| Retreat → Teep → Teep | discovered | 94.6% | 93.7% | 0.18 | 0.20 | 0.00 | 31.2% |
| Retreat → Slip | discovered | 94.5% | 91.2% | 0.00 | 0.00 | 0.02 | 28.9% |
| Retreat → Slip → Retreat | discovered | 94.5% | 91.2% | 0.00 | 0.00 | 0.05 | 27.5% |
| Retreat → Teep → GroinKick | discovered | 94.4% | 93.6% | 0.20 | 0.23 | 0.00 | 31.2% |
| Teep → Teep | discovered | 94.4% | 93.8% | 0.33 | 0.36 | 0.00 | 55.7% |
| Teep → Teep | discovered (strikes) | 94.4% | 93.8% | 0.33 | 0.36 | 0.00 | 55.7% |
| Teep → Knee | discovered (strikes) | 94.3% | 93.8% | 0.27 | 0.31 | 0.05 | 25.7% |
| Teep → GroinKick | discovered (strikes) | 94.2% | 93.3% | 0.38 | 0.44 | 0.00 | 55.7% |
| GroinKick → Teep | discovered (strikes) | 94.2% | 93.7% | 0.43 | 0.52 | 0.00 | 41.3% |
| Slip → BodyHook → ObliqueKick → Flee | document: evasion path (L-step, shovel hook, oblique kick, exit) (he opens with Haymaker) | 95.4% | 95.4% | 0.00 | 0.00 | 0.03 | 0.0% |
| Parry → Jab → Grab → Knee | document: deflection path (tan sao, chain punch, control, knee) (he opens with Haymaker) | 89.5% | 87.0% | 0.19 | 0.31 | 0.15 | 55.1% |
| ObliqueKick → FingerJab → Flee | document: interception path (stop kick, whip hand, exit) (he opens with Haymaker) | 93.4% | 88.3% | 0.12 | 0.25 | 0.08 | 0.0% |
| Jab → Cross → Hook | classic: jab, cross, hook (hips reload each time) | 90.3% | 87.8% | 0.08 | 0.15 | 0.09 | 48.6% |
| Cross → Hook | rotation: cross then hook (lead side loaded by the cross) | 91.1% | 89.6% | 0.08 | 0.09 | 0.05 | 64.2% |
| Cross → Cross | rotation: cross then cross (second from the unwound side) | 91.1% | 89.4% | 0.05 | 0.07 | 0.05 | 64.2% |
| FingerJab → GroinKick → Flee | weak points: eye jab, groin kick, run | 93.3% | 90.0% | 0.20 | 0.32 | 0.00 | 1.7% |

### Against a striker: P(safe) 95.3%

How it ends with optimal play: you get away 76.0%, incapacitate him 0.6%, choke him 0.0%; you are incapacitated 2.9%, choked 0.0%; no finish 20.5% (about 5 beats).

Robustness of the top response: robust (24/24). P(safe) across those perturbations: 83.2% to 98.0%.

| Response | Expected | If he picks the best reply | Optimal play uses it |
|---|---|---|---|
| Teep (push kick to the solar plexus) | 95.3% | 94.9% | 53.5% |
| Retreat (step back) | 95.3% | 95.1% | 46.5% |
| GroinKick (snap kick to the groin (whip)) | 95.3% | 94.6% | 0.0% |
| ObliqueKick (oblique / stop kick to the knee) | 94.8% | 94.3% | 0.0% |

Answers to his attacks:

- **Teep** (he opens with it 69.1% of the time): Teep 95.5%, GroinKick 95.5%, Retreat 95.1%; worst reply Grab 90.9%
- **Grab** (he opens with it 30.9% of the time): Retreat 95.8%, Teep 94.9%, GroinKick 94.9%; worst reply Grab 87.2%
- **Cross** (he opens with it 0.0% of the time): Teep 96.4%, Retreat 96.4%, GroinKick 96.0%; worst reply Grab 92.7%
- **LowKick** (he opens with it 0.0% of the time): Teep 96.5%, Retreat 96.4%, GroinKick 96.0%; worst reply Grab 92.8%
- **Push** (he opens with it 0.0% of the time): Teep 97.3%, GroinKick 97.1%, Push 96.6%; worst reply Grab 93.1%

### Against a grappler: P(safe) 86.3%

How it ends with optimal play: you get away 40.0%, incapacitate him 1.4%, choke him 14.1%; you are incapacitated 0.3%, choked 10.2%; no finish 34.0% (about 8 beats).

Robustness of the top response: robust (24/24). P(safe) across those perturbations: 81.0% to 91.5%.

| Response | Expected | If he picks the best reply | Optimal play uses it |
|---|---|---|---|
| Teep (push kick to the solar plexus) | 86.3% | 85.9% | 24.6% |
| Sprawl (sprawl against a tackle) | 86.3% | 84.3% | 75.4% |
| Push (two-hand shove) | 84.7% | 84.3% | 0.0% |
| GroinKick (snap kick to the groin (whip)) | 84.2% | 84.0% | 0.0% |

Answers to his attacks:

- **Shoot** (he opens with it 92.8% of the time): Sprawl 86.5%, Teep 85.9%, Push 84.3%; worst reply LowKick 79.6%
- **Advance** (he opens with it 7.2% of the time): Teep 92.5%, Push 89.6%, Retreat 86.9%; worst reply Grab 83.0%
- **Push** (he opens with it 0.0% of the time): Teep 91.8%, GroinKick 91.2%, Push 89.5%; worst reply Grab 85.2%
- **Grab** (he opens with it 0.0% of the time): Teep 89.2%, Retreat 88.9%, GroinKick 88.4%; worst reply Grab 80.6%

## In your face

*Chest to chest distance, not yet holding each other.*

### Against a brawler: P(safe) 93.2%

How it ends with optimal play: you get away 52.7%, incapacitate him 1.9%, choke him 0.2%; you are incapacitated 1.5%, choked 1.3%; no finish 42.5% (about 10 beats).

Robustness of the top response: robust (24/24). P(safe) across those perturbations: 90.7% to 94.7%.

| Response | Expected | If he picks the best reply | Optimal play uses it |
|---|---|---|---|
| Retreat (step back) | 93.2% | 93.2% | 100.0% |
| Slip (slip or L-step off the line) | 92.3% | 89.9% | 0.0% |
| Parry (deflect (parry, tan sao)) | 91.6% | 89.9% | 0.0% |
| Counter (simultaneous block-and-counter) | 91.4% | 89.9% | 0.0% |
| Push (two-hand shove) | 90.9% | 90.9% | 0.0% |
| Knee (knee to the groin (to the face if bent over)) | 90.3% | 90.3% | 0.0% |
| FingerJab (finger jab to the eyes (whip)) | 90.0% | 90.0% | 0.0% |
| Circle (step offline to the outside angle) | 90.0% | 90.0% | 0.0% |

Answers to his attacks:

- **Knee** (he opens with it 100.0% of the time): Retreat 93.2%, Slip 92.3%, Parry 91.6%; worst reply Grab 86.3%
- **Haymaker** (he opens with it 0.0% of the time): Retreat 94.7%, Push 94.3%, Slip 93.5%; worst reply Grab 89.5%
- **Push** (he opens with it 0.0% of the time): Knee 94.6%, Retreat 94.6%, Push 94.3%; worst reply Grab 89.4%
- **Grab** (he opens with it 0.0% of the time): Retreat 93.7%, Knee 91.2%, Push 91.2%; worst reply Grab 86.9%
- **Shoot** (he opens with it 0.0% of the time): Sprawl 95.3%, Push 94.7%, Knee 94.4%; worst reply Grab 91.6%

Lines optimal play follows:

- Retreat → Teep: played 50.6% of the time, P(safe) 94.8%
- Retreat → Retreat: played 40.3% of the time, P(safe) 91.3%
- Retreat → Retreat → Teep: played 19.6% of the time, P(safe) 95.9%
- Retreat → Teep → Teep: played 18.6% of the time, P(safe) 96.2%
- Retreat → Retreat → Retreat: played 12.8% of the time, P(safe) 88.1%
- Retreat → Teep → Flee: played 9.7% of the time, P(safe) 98.9%, ends it safely within the line 93.6%

| Combination | Source | Expected | If he reads it | Dealt | Stuns | Taken | Executed |
|---|---|---|---|---|---|---|---|
| Retreat → Teep | discovered | 93.2% | 93.0% | 0.17 | 0.19 | 0.12 | 77.3% |
| Retreat → Retreat | discovered | 93.2% | 92.4% | 0.00 | 0.00 | 0.12 | 90.9% |
| Retreat → Retreat → Teep | discovered | 93.2% | 92.4% | 0.11 | 0.12 | 0.12 | 50.9% |
| Retreat → Retreat → Push | discovered | 93.0% | 91.3% | 0.00 | 0.00 | 0.16 | 25.5% |
| Retreat → GroinKick | discovered | 92.9% | 92.3% | 0.28 | 0.35 | 0.12 | 77.3% |
| Retreat → Retreat → Slip | discovered | 92.9% | 90.2% | 0.00 | 0.00 | 0.14 | 25.5% |
| Push → Teep | discovered (strikes) | 90.9% | 90.8% | 0.12 | 0.12 | 0.25 | 43.7% |
| Push → GroinKick | discovered (strikes) | 90.8% | 90.3% | 0.20 | 0.23 | 0.25 | 43.7% |
| Push → Teep → Teep | discovered (strikes) | 90.7% | 90.6% | 0.19 | 0.19 | 0.25 | 29.5% |
| Push → GroinKick → Teep | discovered (strikes) | 90.7% | 90.3% | 0.25 | 0.29 | 0.25 | 26.7% |
| Knee → Knee → Retreat → Flee | weak points: knee to the groin, knee to the bent-over head, back off, run | 87.9% | 85.8% | 0.34 | 0.44 | 0.35 | 9.2% |
| BodyHook → Cross | rotation: lead hook to the liver, rear cross to the jaw | 86.2% | 86.1% | 0.04 | 0.05 | 0.34 | 62.3% |

### Against a striker: P(safe) 94.1%

How it ends with optimal play: you get away 71.8%, incapacitate him 0.6%, choke him 0.0%; you are incapacitated 3.7%, choked 0.0%; no finish 23.8% (about 6 beats).

Robustness of the top response: robust (24/24). P(safe) across those perturbations: 80.0% to 97.6%.

| Response | Expected | If he picks the best reply | Optimal play uses it |
|---|---|---|---|
| Retreat (step back) | 94.1% | 94.1% | 100.0% |
| Slip (slip or L-step off the line) | 93.1% | 90.5% | 0.0% |
| Parry (deflect (parry, tan sao)) | 92.5% | 90.5% | 0.0% |
| Counter (simultaneous block-and-counter) | 92.3% | 90.5% | 0.0% |

Answers to his attacks:

- **Knee** (he opens with it 100.0% of the time): Retreat 94.1%, Slip 93.1%, Parry 92.5%; worst reply Grab 86.9%
- **Cross** (he opens with it 0.0% of the time): Retreat 95.5%, Push 95.0%, Knee 94.5%; worst reply Grab 90.1%
- **Push** (he opens with it 0.0% of the time): Knee 95.3%, Retreat 95.2%, Push 95.0%; worst reply Grab 89.9%
- **Grab** (he opens with it 0.0% of the time): Retreat 94.3%, Knee 91.8%, Push 91.7%; worst reply Grab 87.2%

### Against a grappler: P(safe) 83.7%

How it ends with optimal play: you get away 37.1%, incapacitate him 1.3%, choke him 11.1%; you are incapacitated 0.4%, choked 11.7%; no finish 38.3% (about 9 beats).

Robustness of the top response: robust (24/24). P(safe) across those perturbations: 77.3% to 89.7%.

| Response | Expected | If he picks the best reply | Optimal play uses it |
|---|---|---|---|
| Retreat (step back) | 83.7% | 82.6% | 70.0% |
| Sprawl (sprawl against a tackle) | 83.7% | 80.1% | 30.0% |
| Push (two-hand shove) | 83.0% | 82.5% | 0.0% |
| Knee (knee to the groin (to the face if bent over)) | 82.5% | 82.2% | 0.0% |

Answers to his attacks:

- **Shoot** (he opens with it 59.5% of the time): Sprawl 86.1%, Retreat 82.6%, Push 82.5%; worst reply Grab 78.6%
- **Knee** (he opens with it 40.5% of the time): Retreat 85.2%, Slip 84.0%, Push 83.8%; worst reply Grab 79.2%
- **Push** (he opens with it 0.0% of the time): Push 87.3%, Knee 87.2%, Retreat 86.6%; worst reply Grab 82.0%
- **Grab** (he opens with it 0.0% of the time): Retreat 86.4%, Push 85.0%, Knee 84.4%; worst reply Grab 80.6%

## Grabbed (headlock / dominant grip)

*He has hold of you with the better grip.*

### Against a brawler: P(safe) 69.9%

How it ends with optimal play: you get away 35.0%, incapacitate him 1.2%, choke him 0.1%; you are incapacitated 5.1%, choked 18.9%; no finish 39.7% (about 10 beats).

Robustness of the top response: robust (24/24). P(safe) across those perturbations: 61.7% to 71.6%.

| Response | Expected | If he picks the best reply | Optimal play uses it |
|---|---|---|---|
| Break (break the grip and separate) | 69.9% | 69.9% | 100.0% |
| Pummel (fight for the better grip) | 69.8% | 67.1% | 0.0% |
| Knee (knee to the groin (to the face if bent over)) | 66.9% | 63.8% | 0.0% |
| Throw (throw / trip / drag down) | 66.0% | 62.2% | 0.0% |
| FingerJab (finger jab to the eyes (whip)) | 65.7% | 62.2% | 0.0% |
| Headbutt (headbutt to the nose) | 65.4% | 61.9% | 0.0% |
| Elbow (elbow to the temple) | 64.7% | 62.0% | 0.0% |
| Stomp (stomp (foot; head if down)) | 64.6% | 62.0% | 0.0% |

Answers to his attacks:

- **Knee** (he opens with it 100.0% of the time): Break 69.9%, Pummel 69.8%, Knee 66.9%; worst reply Cover 64.5%
- **Stomp** (he opens with it 0.0% of the time): Break 75.2%, Pummel 74.6%, Knee 71.9%; worst reply Stomp 69.7%
- **Choke** (he opens with it 0.0% of the time): Break 70.3%, Pummel 67.1%, Cover 67.0%; worst reply Headbutt 61.9%

Lines optimal play follows:

- Break → Break: played 48.2% of the time, P(safe) 60.5%
- Break → Break → Break: played 23.8% of the time, P(safe) 62.0%
- Break → Retreat: played 22.4% of the time, P(safe) 88.2%
- Break → Cover: played 21.1% of the time, P(safe) 62.4%
- Break → Cover → Break: played 14.7% of the time, P(safe) 69.7%
- Break → Break → Retreat: played 14.4% of the time, P(safe) 86.7%

| Combination | Source | Expected | If he reads it | Dealt | Stuns | Taken | Executed |
|---|---|---|---|---|---|---|---|
| Break → Break | discovered | 69.7% | 69.7% | 0.00 | 0.00 | 0.43 | 53.9% |
| Break → Break → Break | discovered | 69.7% | 69.7% | 0.00 | 0.00 | 0.48 | 28.6% |
| Pummel → Break | discovered | 69.7% | 67.1% | 0.00 | 0.00 | 0.48 | 77.2% |
| Pummel → Break → Break | discovered | 69.7% | 67.0% | 0.00 | 0.00 | 0.56 | 38.6% |
| Pummel → Break → Retreat | discovered | 69.7% | 67.1% | 0.00 | 0.00 | 0.51 | 32.2% |
| Pummel → Break → Slip | discovered | 69.3% | 66.4% | 0.00 | 0.00 | 0.50 | 28.8% |
| Knee → Knee | discovered (strikes) | 64.1% | 58.4% | 0.18 | 0.23 | 0.43 | 36.1% |
| Knee → FingerJab | discovered (strikes) | 63.7% | 57.5% | 0.15 | 0.20 | 0.43 | 35.9% |
| Knee → Elbow | discovered (strikes) | 63.7% | 57.5% | 0.15 | 0.19 | 0.43 | 36.1% |
| Knee → Headbutt | discovered (strikes) | 63.6% | 57.3% | 0.14 | 0.19 | 0.43 | 35.9% |
| Knee → Break | knee the groin, then break away | 66.8% | 63.8% | 0.14 | 0.18 | 0.43 | 74.1% |

### Against a striker: P(safe) 73.7%

How it ends with optimal play: you get away 48.5%, incapacitate him 0.3%, choke him 0.0%; you are incapacitated 19.9%, choked 0.0%; no finish 31.2% (about 7 beats).

Robustness of the top response: robust (24/24). P(safe) across those perturbations: 50.3% to 91.9%.

| Response | Expected | If he picks the best reply | Optimal play uses it |
|---|---|---|---|
| Break (break the grip and separate) | 73.7% | 73.7% | 100.0% |
| Pummel (fight for the better grip) | 73.1% | 73.1% | 0.0% |
| Knee (knee to the groin (to the face if bent over)) | 71.5% | 71.5% | 0.0% |
| Throw (throw / trip / drag down) | 70.9% | 70.9% | 0.0% |

Answers to his attacks:

- **Knee** (he opens with it 100.0% of the time): Break 73.7%, Pummel 73.1%, Knee 71.5%; worst reply Cover 69.4%
- **Stomp** (he opens with it 0.0% of the time): Break 78.4%, Pummel 77.6%, Knee 75.7%; worst reply Cover 73.9%

### Against a grappler: P(safe) 63.8%

How it ends with optimal play: you get away 25.5%, incapacitate him 0.8%, choke him 6.4%; you are incapacitated 2.5%, choked 27.5%; no finish 37.3% (about 9 beats).

Robustness of the top response: robust (24/24). P(safe) across those perturbations: 58.7% to 68.4%.

| Response | Expected | If he picks the best reply | Optimal play uses it |
|---|---|---|---|
| Break (break the grip and separate) | 63.8% | 63.8% | 88.2% |
| Pummel (fight for the better grip) | 63.8% | 61.9% | 11.8% |
| Knee (knee to the groin (to the face if bent over)) | 61.1% | 58.8% | 0.0% |
| Throw (throw / trip / drag down) | 60.2% | 57.5% | 0.0% |

Answers to his attacks:

- **Knee** (he opens with it 84.0% of the time): Pummel 64.2%, Break 63.8%, Knee 61.5%; worst reply Cover 59.1%
- **Choke** (he opens with it 16.0% of the time): Break 64.1%, Pummel 61.9%, Cover 61.6%; worst reply Headbutt 56.9%
- **Stomp** (he opens with it 0.0% of the time): Pummel 68.8%, Break 68.7%, Knee 66.2%; worst reply Stomp 64.1%

## Tied up

*You are holding each other, neither has the better grip.*

### Against a brawler: P(safe) 86.3%

How it ends with optimal play: you get away 47.3%, incapacitate him 1.5%, choke him 0.1%; you are incapacitated 5.0%, choked 1.8%; no finish 44.3% (about 11 beats).

Robustness of the top response: holds in 23/24. Changes under: strike accuracy x1.25 → Knee. P(safe) across those perturbations: 79.6% to 90.6%.

| Response | Expected | If he picks the best reply | Optimal play uses it |
|---|---|---|---|
| Break (break the grip and separate) | 86.3% | 86.3% | 100.0% |
| Throw (throw / trip / drag down) | 86.2% | 84.3% | 0.0% |
| Knee (knee to the groin (to the face if bent over)) | 86.0% | 85.0% | 0.0% |
| Pummel (fight for the better grip) | 85.7% | 84.9% | 0.0% |
| FingerJab (finger jab to the eyes (whip)) | 85.0% | 82.8% | 0.0% |
| Headbutt (headbutt to the nose) | 84.7% | 82.5% | 0.0% |
| Elbow (elbow to the temple) | 84.2% | 82.7% | 0.0% |
| Stomp (stomp (foot; head if down)) | 84.2% | 82.7% | 0.0% |

Answers to his attacks:

- **Knee** (he opens with it 100.0% of the time): Break 86.3%, Throw 86.2%, Knee 86.0%; worst reply Cover 83.9%
- **Stomp** (he opens with it 0.0% of the time): Break 89.3%, Knee 88.5%, Pummel 88.3%; worst reply Cover 86.4%

Lines optimal play follows:

- Break → Retreat: played 43.4% of the time, P(safe) 90.3%
- Break → Break: played 34.9% of the time, P(safe) 81.4%
- Break → Retreat → Teep: played 23.2% of the time, P(safe) 93.2%
- Break → Retreat → Retreat: played 15.3% of the time, P(safe) 91.5%
- Break → Break → Retreat: played 15.2% of the time, P(safe) 86.6%
- Break → Throw: played 11.1% of the time, P(safe) 86.0%

| Combination | Source | Expected | If he reads it | Dealt | Stuns | Taken | Executed |
|---|---|---|---|---|---|---|---|
| Break → Break | discovered | 86.3% | 86.3% | 0.00 | 0.00 | 0.36 | 45.9% |
| Break → Retreat | discovered | 86.3% | 86.3% | 0.00 | 0.00 | 0.32 | 43.4% |
| Break → Retreat → Teep | discovered | 86.3% | 86.2% | 0.07 | 0.08 | 0.32 | 34.2% |
| Break → Retreat → Retreat | discovered | 86.3% | 85.9% | 0.00 | 0.00 | 0.32 | 38.5% |
| Throw → Break | discovered | 86.2% | 84.3% | 0.01 | 0.00 | 0.42 | 67.0% |
| Throw → Break → Retreat | discovered | 86.2% | 84.3% | 0.01 | 0.00 | 0.45 | 32.7% |
| Knee → Knee | discovered (strikes) | 84.9% | 81.7% | 0.38 | 0.48 | 0.37 | 56.4% |
| Knee → Elbow | discovered (strikes) | 84.7% | 80.8% | 0.32 | 0.40 | 0.36 | 56.4% |
| Knee → FingerJab | discovered (strikes) | 84.6% | 80.8% | 0.30 | 0.43 | 0.36 | 56.4% |
| Knee → Stomp | discovered (strikes) | 84.5% | 80.5% | 0.29 | 0.38 | 0.35 | 58.2% |

### Against a striker: P(safe) 86.7%

How it ends with optimal play: you get away 61.0%, incapacitate him 0.5%, choke him 0.0%; you are incapacitated 9.0%, choked 0.0%; no finish 29.5% (about 7 beats).

Robustness of the top response: holds in 22/24. Changes under: force & targets x1.25 → Knee; strike accuracy x1.25 → Knee. P(safe) across those perturbations: 69.7% to 95.6%.

| Response | Expected | If he picks the best reply | Optimal play uses it |
|---|---|---|---|
| Break (break the grip and separate) | 86.7% | 86.7% | 100.0% |
| Knee (knee to the groin (to the face if bent over)) | 86.4% | 86.3% | 0.0% |
| Throw (throw / trip / drag down) | 86.3% | 85.6% | 0.0% |
| Pummel (fight for the better grip) | 85.8% | 85.8% | 0.0% |

Answers to his attacks:

- **Knee** (he opens with it 100.0% of the time): Break 86.7%, Knee 86.4%, Throw 86.3%; worst reply Cover 84.0%
- **Stomp** (he opens with it 0.0% of the time): Break 89.9%, Knee 89.0%, Pummel 88.6%; worst reply Cover 86.7%

### Against a grappler: P(safe) 79.8%

How it ends with optimal play: you get away 38.5%, incapacitate him 1.0%, choke him 7.1%; you are incapacitated 1.9%, choked 12.9%; no finish 38.7% (about 9 beats).

Robustness of the top response: holds in 21/24. Changes under: force & targets x0.75 → Break; strike accuracy x0.75 → Break; strike accuracy x1.25 → Knee. P(safe) across those perturbations: 75.8% to 84.4%.

| Response | Expected | If he picks the best reply | Optimal play uses it |
|---|---|---|---|
| Throw (throw / trip / drag down) | 79.8% | 78.9% | 50.1% |
| Break (break the grip and separate) | 79.8% | 79.0% | 49.9% |
| Pummel (fight for the better grip) | 79.6% | 79.2% | 0.0% |
| Knee (knee to the groin (to the face if bent over)) | 79.5% | 79.0% | 0.0% |

Answers to his attacks:

- **Knee** (he opens with it 54.5% of the time): Throw 80.5%, Pummel 79.9%, Knee 79.9%; worst reply Cover 77.6%
- **Pummel** (he opens with it 45.5% of the time): Break 80.7%, Pummel 79.2%, Knee 79.0%; worst reply Cover 75.2%
- **Stomp** (he opens with it 0.0% of the time): Pummel 82.7%, Knee 82.5%, Throw 82.0%; worst reply Cover 80.2%

## Grabbed from behind

*Bear hug or rear choke attempt while standing.*

### Against a brawler: P(safe) 54.1%

How it ends with optimal play: you get away 26.1%, incapacitate him 0.8%, choke him 0.1%; you are incapacitated 2.8%, choked 38.2%; no finish 32.0% (about 8 beats).

Robustness of the top response: robust (24/24). P(safe) across those perturbations: 48.9% to 60.1%.

| Response | Expected | If he picks the best reply | Optimal play uses it |
|---|---|---|---|
| Turn (turn into him) | 54.1% | 54.1% | 100.0% |
| Cover (cover / guard) | 50.1% | 50.1% | 0.0% |
| GroinKick (snap kick to the groin (whip)) | 47.7% | 47.7% | 0.0% |
| Stomp (stomp (foot; head if down)) | 46.1% | 46.1% | 0.0% |
| Elbow (elbow to the temple) | 45.9% | 45.9% | 0.0% |
| Headbutt (headbutt to the nose) | 44.6% | 44.6% | 0.0% |

Answers to his attacks:

- **Choke** (he opens with it 100.0% of the time): Turn 54.1%, Cover 50.1%, GroinKick 47.7%; worst reply Headbutt 44.6%

Lines optimal play follows:

- Turn → Turn: played 44.9% of the time, P(safe) 52.8%
- Turn → Break: played 28.2% of the time, P(safe) 85.8%
- Turn → Turn → Turn: played 21.0% of the time, P(safe) 52.8%
- Turn → Turn → Break: played 13.2% of the time, P(safe) 85.8%
- Turn → Break → Retreat: played 12.7% of the time, P(safe) 90.3%
- Turn → Break → Break: played 10.2% of the time, P(safe) 81.4%

| Combination | Source | Expected | If he reads it | Dealt | Stuns | Taken | Executed |
|---|---|---|---|---|---|---|---|
| Turn → Turn | discovered | 54.1% | 54.1% | 0.00 | 0.00 | 0.00 | 35.7% |
| Turn → Break | discovered | 54.1% | 54.1% | 0.00 | 0.00 | 0.08 | 28.2% |
| Turn → Throw | discovered | 54.1% | 53.5% | 0.00 | 0.00 | 0.08 | 28.2% |
| Turn → Knee | discovered | 54.0% | 53.7% | 0.08 | 0.10 | 0.08 | 28.2% |
| Turn → Knee → Break | discovered | 54.0% | 53.7% | 0.08 | 0.10 | 0.12 | 25.4% |
| Turn → Pummel | discovered | 53.9% | 53.7% | 0.00 | 0.00 | 0.08 | 28.2% |
| GroinKick → GroinKick | discovered (strikes) | 43.3% | 43.3% | 0.36 | 0.44 | 0.00 | 57.4% |
| GroinKick → Stomp | discovered (strikes) | 41.1% | 41.1% | 0.22 | 0.28 | 0.00 | 61.3% |
| Stomp → GroinKick | discovered (strikes) | 41.0% | 41.0% | 0.16 | 0.23 | 0.00 | 58.1% |
| Elbow → GroinKick | discovered (strikes) | 41.0% | 41.0% | 0.19 | 0.23 | 0.00 | 57.7% |
| Stomp → Elbow → Turn | loosen the hold: stomp, elbow, turn | 39.4% | 39.4% | 0.04 | 0.08 | 0.00 | 46.4% |

### Against a striker: P(safe) 94.2%

How it ends with optimal play: you get away 68.0%, incapacitate him 2.1%, choke him 0.0%; you are incapacitated 3.4%, choked 0.0%; no finish 26.6% (about 6 beats).

Robustness of the top response: robust (24/24). P(safe) across those perturbations: 83.2% to 94.7%.

| Response | Expected | If he picks the best reply | Optimal play uses it |
|---|---|---|---|
| GroinKick (snap kick to the groin (whip)) | 94.2% | 94.2% | 100.0% |
| Headbutt (headbutt to the nose) | 93.9% | 93.9% | 0.0% |
| Cover (cover / guard) | 93.7% | 93.7% | 0.0% |
| Stomp (stomp (foot; head if down)) | 93.7% | 93.7% | 0.0% |

Answers to his attacks:

- **Break** (he opens with it 100.0% of the time): GroinKick 94.2%, Headbutt 93.9%, Cover 93.7%; worst reply Turn 91.2%

### Against a grappler: P(safe) 50.5%

How it ends with optimal play: you get away 21.3%, incapacitate him 0.6%, choke him 3.9%; you are incapacitated 1.0%, choked 44.3%; no finish 28.9% (about 7 beats).

Robustness of the top response: holds in 23/24. Changes under: strike accuracy x1.25 → GroinKick. P(safe) across those perturbations: 45.2% to 56.0%.

| Response | Expected | If he picks the best reply | Optimal play uses it |
|---|---|---|---|
| Turn (turn into him) | 50.5% | 50.5% | 100.0% |
| Cover (cover / guard) | 47.0% | 47.0% | 0.0% |
| GroinKick (snap kick to the groin (whip)) | 45.2% | 45.2% | 0.0% |
| Stomp (stomp (foot; head if down)) | 43.3% | 43.3% | 0.0% |

Answers to his attacks:

- **Choke** (he opens with it 100.0% of the time): Turn 50.5%, Cover 47.0%, GroinKick 45.2%; worst reply Headbutt 41.9%

## Down, attacker standing over you

*You are on the ground; he is standing.*

### Against a brawler: P(safe) 91.1%

How it ends with optimal play: you get away 47.8%, incapacitate him 1.7%, choke him 0.1%; you are incapacitated 1.9%, choked 1.4%; no finish 47.0% (about 11 beats).

Robustness of the top response: robust (24/24). P(safe) across those perturbations: 85.3% to 93.5%.

| Response | Expected | If he picks the best reply | Optimal play uses it |
|---|---|---|---|
| GetUp (technical stand-up) | 91.1% | 91.1% | 100.0% |
| Cover (cover / guard) | 90.5% | 90.5% | 0.0% |
| Upkick (upkick from the ground) | 89.9% | 89.9% | 0.0% |

Answers to his attacks:

- **Stomp** (he opens with it 100.0% of the time): GetUp 91.1%, Cover 90.5%, Upkick 89.9%; worst reply Upkick 89.9%

Lines optimal play follows:

- GetUp → Retreat: played 46.0% of the time, P(safe) 92.0%
- GetUp → GetUp: played 43.2% of the time, P(safe) 90.8%
- GetUp → Retreat → Teep: played 23.5% of the time, P(safe) 94.5%
- GetUp → GetUp → Retreat: played 20.6% of the time, P(safe) 91.7%
- GetUp → GetUp → GetUp: played 19.6% of the time, P(safe) 90.1%
- GetUp → Retreat → Retreat: played 19.1% of the time, P(safe) 90.9%

| Combination | Source | Expected | If he reads it | Dealt | Stuns | Taken | Executed |
|---|---|---|---|---|---|---|---|
| GetUp → Retreat | discovered | 91.1% | 91.1% | 0.00 | 0.00 | 0.10 | 46.1% |
| GetUp → GetUp | discovered | 91.1% | 91.1% | 0.00 | 0.00 | 0.07 | 43.2% |
| GetUp → Retreat → Teep | discovered | 91.1% | 90.9% | 0.08 | 0.09 | 0.10 | 36.1% |
| GetUp → Retreat → Retreat | discovered | 91.1% | 90.6% | 0.00 | 0.00 | 0.10 | 42.7% |
| GetUp → Retreat → GroinKick | discovered | 90.9% | 90.6% | 0.13 | 0.16 | 0.10 | 36.1% |
| GetUp → Retreat → Push | discovered | 90.8% | 90.6% | 0.01 | 0.00 | 0.10 | 36.9% |
| Upkick → Upkick | discovered (strikes) | 88.7% | 88.7% | 0.02 | 0.03 | 0.13 | 83.9% |
| Upkick → Upkick → Upkick | discovered (strikes) | 87.7% | 87.7% | 0.03 | 0.04 | 0.18 | 73.8% |

### Against a striker: P(safe) 91.9%

How it ends with optimal play: you get away 65.1%, incapacitate him 0.5%, choke him 0.0%; you are incapacitated 4.4%, choked 0.0%; no finish 30.0% (about 7 beats).

Robustness of the top response: robust (24/24). P(safe) across those perturbations: 74.4% to 95.7%.

| Response | Expected | If he picks the best reply | Optimal play uses it |
|---|---|---|---|
| GetUp (technical stand-up) | 91.9% | 91.9% | 100.0% |
| Cover (cover / guard) | 91.3% | 91.3% | 0.0% |
| Upkick (upkick from the ground) | 90.7% | 90.7% | 0.0% |

Answers to his attacks:

- **Stomp** (he opens with it 100.0% of the time): GetUp 91.9%, Cover 91.3%, Upkick 90.7%; worst reply Upkick 90.7%

### Against a grappler: P(safe) 78.1%

How it ends with optimal play: you get away 35.0%, incapacitate him 1.2%, choke him 7.1%; you are incapacitated 0.3%, choked 16.5%; no finish 39.9% (about 10 beats).

Robustness of the top response: robust (24/24). P(safe) across those perturbations: 72.8% to 83.2%.

| Response | Expected | If he picks the best reply | Optimal play uses it |
|---|---|---|---|
| GetUp (technical stand-up) | 78.1% | 78.1% | 100.0% |
| Upkick (upkick from the ground) | 74.5% | 74.5% | 0.0% |
| Cover (cover / guard) | 72.4% | 72.4% | 0.0% |

Answers to his attacks:

- **Follow** (he opens with it 100.0% of the time): GetUp 78.1%, Upkick 74.5%, Cover 72.4%; worst reply Cover 72.4%
- **Stomp** (he opens with it 0.0% of the time): GetUp 80.4%, Cover 78.1%, Upkick 77.4%; worst reply Upkick 77.4%

## Tackled, attacker on top in your guard

*On your back with your legs around him.*

### Against a brawler: P(safe) 93.4%

How it ends with optimal play: you get away 26.6%, incapacitate him 0.9%, choke him 0.1%; you are incapacitated 0.3%, choked 0.5%; no finish 71.7% (about 17 beats).

Robustness of the top response: robust (24/24). P(safe) across those perturbations: 89.0% to 95.0%.

| Response | Expected | If he picks the best reply | Optimal play uses it |
|---|---|---|---|
| Sweep (sweep from guard) | 93.4% | 93.4% | 100.0% |
| Cover (cover / guard) | 93.0% | 93.0% | 0.0% |
| Escape (escape from underneath) | 89.1% | 89.1% | 0.0% |
| GuardSub (submission from guard) | 87.8% | 87.8% | 0.0% |

Answers to his attacks:

- **Hold** (he opens with it 100.0% of the time): Sweep 93.4%, Cover 93.0%, Escape 89.1%; worst reply GuardSub 87.8%

Lines optimal play follows:

- Sweep → Sweep: played 83.9% of the time, P(safe) 93.7%
- Sweep → Sweep → Sweep: played 73.3% of the time, P(safe) 93.7%
- Sweep → Sweep → Sweep → Sweep: played 64.0% of the time, P(safe) 93.7%
- Sweep → Hold: played 8.3% of the time, P(safe) 97.1%
- Sweep → Sweep → Hold: played 7.2% of the time, P(safe) 97.1%
- Sweep → Hold → Hold: played 6.8% of the time, P(safe) 97.2%

| Combination | Source | Expected | If he reads it | Dealt | Stuns | Taken | Executed |
|---|---|---|---|---|---|---|---|
| Sweep → Sweep | discovered | 93.4% | 93.4% | 0.00 | 0.00 | 0.00 | 83.9% |
| Sweep → Sweep → Sweep | discovered | 93.4% | 93.4% | 0.00 | 0.00 | 0.00 | 73.3% |
| Sweep → Sweep → Cover | discovered | 93.1% | 93.1% | 0.00 | 0.00 | 0.00 | 73.3% |
| Sweep → Cover | discovered | 93.1% | 93.1% | 0.00 | 0.00 | 0.00 | 83.9% |
| Sweep → Cover → Sweep | discovered | 93.1% | 93.1% | 0.00 | 0.00 | 0.00 | 80.5% |
| Cover → Sweep | discovered | 93.0% | 93.0% | 0.00 | 0.00 | 0.00 | 92.2% |

### Against a striker: P(safe) 93.6%

How it ends with optimal play: you get away 37.0%, incapacitate him 0.2%, choke him 0.0%; you are incapacitated 1.1%, choked 0.0%; no finish 61.7% (about 15 beats).

Robustness of the top response: robust (24/24). P(safe) across those perturbations: 84.4% to 95.2%.

| Response | Expected | If he picks the best reply | Optimal play uses it |
|---|---|---|---|
| Sweep (sweep from guard) | 93.6% | 93.6% | 100.0% |
| Cover (cover / guard) | 93.2% | 93.2% | 0.0% |
| Escape (escape from underneath) | 92.8% | 92.8% | 0.0% |
| GuardSub (submission from guard) | 91.9% | 91.9% | 0.0% |

Answers to his attacks:

- **Hold** (he opens with it 100.0% of the time): Sweep 93.6%, Cover 93.2%, Escape 92.8%; worst reply GuardSub 91.9%

### Against a grappler: P(safe) 70.7%

How it ends with optimal play: you get away 35.7%, incapacitate him 1.2%, choke him 2.9%; you are incapacitated 0.1%, choked 23.8%; no finish 36.2% (about 9 beats).

Robustness of the top response: robust (24/24). P(safe) across those perturbations: 66.1% to 75.1%.

| Response | Expected | If he picks the best reply | Optimal play uses it |
|---|---|---|---|
| Escape (escape from underneath) | 70.7% | 70.7% | 100.0% |
| Sweep (sweep from guard) | 70.4% | 70.4% | 0.0% |
| Cover (cover / guard) | 67.6% | 67.6% | 0.0% |
| GuardSub (submission from guard) | 67.6% | 67.6% | 0.0% |

Answers to his attacks:

- **Pass** (he opens with it 100.0% of the time): Escape 70.7%, Sweep 70.4%, Cover 67.6%; worst reply GuardSub 67.6%

## Mounted

*He is sitting on your chest.*

### Against a brawler: P(safe) 69.4%

How it ends with optimal play: you get away 16.5%, incapacitate him 0.6%, choke him 0.0%; you are incapacitated 0.2%, choked 21.8%; no finish 60.9% (about 15 beats).

Robustness of the top response: robust (24/24). P(safe) across those perturbations: 64.2% to 73.7%.

| Response | Expected | If he picks the best reply | Optimal play uses it |
|---|---|---|---|
| Cover (cover / guard) | 69.4% | 69.4% | 99.1% |
| Escape (escape from underneath) | 69.4% | 66.7% | 0.9% |

Answers to his attacks:

- **Pound** (he opens with it 50.5% of the time): Escape 72.0%, Cover 69.4%; worst reply Cover 69.4%
- **Choke** (he opens with it 49.5% of the time): Cover 69.4%, Escape 66.7%; worst reply Escape 66.7%

Lines optimal play follows:

- Cover → Cover: played 71.7% of the time, P(safe) 69.3%
- Cover → Cover → Cover: played 54.0% of the time, P(safe) 69.3%
- Cover → Cover → Cover → Cover: played 40.7% of the time, P(safe) 69.3%
- Cover → Sweep: played 14.1% of the time, P(safe) 93.7%
- Cover → Sweep → Sweep: played 12.3% of the time, P(safe) 93.7%
- Cover → Sweep → Sweep → Sweep: played 10.8% of the time, P(safe) 93.7%

| Combination | Source | Expected | If he reads it | Dealt | Stuns | Taken | Executed |
|---|---|---|---|---|---|---|---|
| Escape → Sweep | discovered | 69.4% | 66.7% | 0.00 | 0.00 | 0.02 | 28.1% |
| Cover → Cover | discovered | 69.3% | 69.3% | 0.00 | 0.00 | 0.00 | 83.3% |
| Escape → Cover | discovered | 69.3% | 66.6% | 0.00 | 0.00 | 0.02 | 79.8% |
| Escape → Cover → Sweep | discovered | 69.3% | 66.6% | 0.00 | 0.00 | 0.02 | 36.8% |
| Cover → Cover → Cover | discovered | 69.2% | 69.1% | 0.00 | 0.00 | 0.00 | 77.0% |
| Escape → Cover → Cover | discovered | 69.1% | 66.4% | 0.00 | 0.00 | 0.02 | 74.0% |

### Against a striker: P(safe) 86.9%

How it ends with optimal play: you get away 31.4%, incapacitate him 0.2%, choke him 0.0%; you are incapacitated 1.7%, choked 0.0%; no finish 66.8% (about 16 beats).

Robustness of the top response: robust (24/24). P(safe) across those perturbations: 69.0% to 90.6%.

| Response | Expected | If he picks the best reply | Optimal play uses it |
|---|---|---|---|
| Escape (escape from underneath) | 86.9% | 86.9% | 100.0% |
| Cover (cover / guard) | 86.2% | 86.2% | 0.0% |

Answers to his attacks:

- **Pound** (he opens with it 100.0% of the time): Escape 86.9%, Cover 86.2%; worst reply Cover 86.2%

### Against a grappler: P(safe) 53.4%

How it ends with optimal play: you get away 22.6%, incapacitate him 0.8%, choke him 1.9%; you are incapacitated 0.1%, choked 39.5%; no finish 35.3% (about 8 beats).

Robustness of the top response: robust (24/24). P(safe) across those perturbations: 48.1% to 59.7%.

| Response | Expected | If he picks the best reply | Optimal play uses it |
|---|---|---|---|
| Cover (cover / guard) | 53.4% | 52.9% | 84.6% |
| Escape (escape from underneath) | 53.4% | 51.6% | 15.4% |

Answers to his attacks:

- **Choke** (he opens with it 57.6% of the time): Cover 53.7%, Escape 51.6%; worst reply Escape 51.6%
- **Pass** (he opens with it 42.4% of the time): Escape 55.9%, Cover 52.9%; worst reply Cover 52.9%

## Back taken on the ground

*He is behind you on the ground.*

### Against a brawler: P(safe) 58.4%

How it ends with optimal play: you get away 15.0%, incapacitate him 0.5%, choke him 0.0%; you are incapacitated 0.1%, choked 35.6%; no finish 48.6% (about 12 beats).

Robustness of the top response: robust (24/24). P(safe) across those perturbations: 51.1% to 65.2%.

| Response | Expected | If he picks the best reply | Optimal play uses it |
|---|---|---|---|
| Cover (cover / guard) | 58.4% | 58.4% | 100.0% |
| Escape (escape from underneath) | 53.3% | 53.3% | 0.0% |

Answers to his attacks:

- **Choke** (he opens with it 100.0% of the time): Cover 58.4%, Escape 53.3%; worst reply Escape 53.3%

Lines optimal play follows:

- Cover → Cover: played 49.1% of the time, P(safe) 57.9%
- Cover → Sweep: played 26.4% of the time, P(safe) 93.7%
- Cover → Cover → Cover: played 25.1% of the time, P(safe) 57.9%
- Cover → Sweep → Sweep: played 23.1% of the time, P(safe) 93.7%
- Cover → Sweep → Sweep → Sweep: played 20.2% of the time, P(safe) 93.7%
- Cover → Cover → Sweep: played 13.5% of the time, P(safe) 93.7%

| Combination | Source | Expected | If he reads it | Dealt | Stuns | Taken | Executed |
|---|---|---|---|---|---|---|---|
| Cover → Sweep | discovered | 58.4% | 58.4% | 0.00 | 0.00 | 0.00 | 26.4% |
| Cover → Cover | discovered | 58.3% | 58.3% | 0.00 | 0.00 | 0.00 | 66.7% |
| Cover → Cover → Sweep | discovered | 58.3% | 58.3% | 0.00 | 0.00 | 0.00 | 38.9% |
| Cover → Cover → Cover | discovered | 58.2% | 58.2% | 0.00 | 0.00 | 0.00 | 59.5% |
| Cover → GuardSub | discovered | 56.9% | 56.9% | 0.00 | 0.00 | 0.00 | 26.4% |
| Cover → GuardSub → Cover | discovered | 56.8% | 56.8% | 0.00 | 0.00 | 0.00 | 25.1% |

### Against a striker: P(safe) 86.9%

How it ends with optimal play: you get away 31.1%, incapacitate him 0.1%, choke him 0.0%; you are incapacitated 1.6%, choked 0.0%; no finish 67.2% (about 16 beats).

Robustness of the top response: robust (24/24). P(safe) across those perturbations: 69.9% to 90.7%.

| Response | Expected | If he picks the best reply | Optimal play uses it |
|---|---|---|---|
| Escape (escape from underneath) | 86.9% | 86.9% | 100.0% |
| Cover (cover / guard) | 86.2% | 86.2% | 0.0% |

Answers to his attacks:

- **Pound** (he opens with it 100.0% of the time): Escape 86.9%, Cover 86.2%; worst reply Cover 86.2%

### Against a grappler: P(safe) 45.6%

How it ends with optimal play: you get away 20.1%, incapacitate him 0.7%, choke him 1.7%; you are incapacitated 0.1%, choked 48.8%; no finish 28.6% (about 7 beats).

Robustness of the top response: robust (24/24). P(safe) across those perturbations: 39.0% to 53.3%.

| Response | Expected | If he picks the best reply | Optimal play uses it |
|---|---|---|---|
| Cover (cover / guard) | 45.6% | 45.6% | 100.0% |
| Escape (escape from underneath) | 41.6% | 41.6% | 0.0% |

Answers to his attacks:

- **Choke** (he opens with it 100.0% of the time): Cover 45.6%, Escape 41.6%; worst reply Escape 41.6%

## What your weapons are worth

Each row removes something from your arsenal and re-solves every situation. The number is the average change in P(safe) across the ten situations, in percentage points (removing an option can never help you, so it is always zero or negative).

### Techniques: trained vs brawler

| Without | Change in P(safe) | Situations hurt most |
|---|---|---|
| Sweep | -4.2 | Tackled, attacker on top in your guard (-9.0); Mounted (-6.0); Back taken on the ground (-5.1) |
| Teep | -2.9 | Tied up (-3.9); Squared up at kicking range (-3.8); In your face (-3.7) |
| Flee | -2.8 | Tied up (-5.1); Grabbed (headlock / dominant grip) (-4.3); Down, attacker standing over you (-3.5) |
| Throw | -0.1 | Tied up (-0.2); Grabbed from behind (-0.1); Grabbed (headlock / dominant grip) (-0.1) |
| Sprawl | -0.0 |  |
| Knee | -0.0 |  |
| Push | -0.0 |  |
| GroinKick | -0.0 |  |
| Pound | -0.0 |  |
| Pummel | -0.0 |  |
| Grab | -0.0 |  |
| Pass | -0.0 |  |
| Elbow | -0.0 |  |
| Circle | -0.0 |  |
| Stomp | -0.0 |  |
| FingerJab | -0.0 |  |
| ObliqueKick | -0.0 |  |
| Headbutt | -0.0 |  |
| Hook | -0.0 |  |
| Parry | -0.0 |  |
| Upkick | -0.0 |  |
| Feint | +0.0 |  |
| BodyHook | +0.0 |  |
| Jab | +0.0 |  |
| Counter | +0.0 |  |
| LowKick | +0.0 |  |
| Cross | +0.0 |  |
| Slip | +0.0 |  |
| GuardSub | +0.0 |  |

### Target zones: trained vs brawler

Hip loading: if every rotational strike had full power and speed from either side (no need to chain rotations), your average P(safe) would change by -0.7 points.

| Without | Change in P(safe) | Situations hurt most |
|---|---|---|
| SolarPlexus | -2.9 | Tied up (-3.9); Squared up at kicking range (-3.8); In your face (-3.7) |
| Groin | -0.0 |  |
| Jaw | -0.0 |  |
| Temples | -0.0 |  |
| Foot | -0.0 |  |
| Eyes | -0.0 |  |
| Nose | -0.0 |  |
| KneeLateral | -0.0 |  |
| Liver | +0.0 |  |
| ThighMuscle | +0.0 |  |

### How force is generated: trained vs brawler

| Without | Change in P(safe) | Situations hurt most |
|---|---|---|
| Push | -2.9 | Tied up (-3.9); Squared up at kicking range (-3.8); In your face (-3.7) |
| Rotational | -0.0 |  |
| Whip | -0.0 |  |
| Drop | -0.0 |  |
| Linear | +0.0 |  |

### Target zones: trained vs striker

Hip loading: if every rotational strike had full power and speed from either side (no need to chain rotations), your average P(safe) would change by -0.6 points.

| Without | Change in P(safe) | Situations hurt most |
|---|---|---|
| Groin | -1.4 | Grabbed from behind (-5.5); Squared up at kicking range (-1.2); Tied up (-1.1) |
| SolarPlexus | -1.0 | Tied up (-1.3); Grabbed (headlock / dominant grip) (-1.2); In your face (-1.2) |
| Eyes | -0.0 |  |
| Temples | -0.0 |  |
| Foot | -0.0 |  |
| Jaw | -0.0 |  |
| ThighMuscle | +0.0 |  |
| Nose | +0.0 |  |
| Liver | +0.0 |  |
| KneeLateral | +0.0 |  |

### How force is generated: trained vs striker

| Without | Change in P(safe) | Situations hurt most |
|---|---|---|
| Whip | -1.3 | Grabbed from behind (-5.4); Squared up at kicking range (-1.2); Tied up (-1.1) |
| Push | -1.0 | Tied up (-1.3); Grabbed (headlock / dominant grip) (-1.2); In your face (-1.2) |
| Rotational | -0.0 |  |
| Drop | -0.0 |  |
| Linear | +0.0 |  |

### Target zones: trained vs grappler

Hip loading: if every rotational strike had full power and speed from either side (no need to chain rotations), your average P(safe) would change by -0.5 points.

| Without | Change in P(safe) | Situations hurt most |
|---|---|---|
| SolarPlexus | -3.7 | Squared up at kicking range (-6.1); Aggressor at arm's length (-5.1); In your face (-4.5) |
| Groin | -0.0 | Tied up (-0.1) |
| Temples | -0.0 |  |
| Foot | -0.0 |  |
| Eyes | -0.0 |  |
| Nose | -0.0 |  |
| KneeLateral | -0.0 |  |
| Jaw | -0.0 |  |
| ThighMuscle | -0.0 |  |
| Liver | -0.0 |  |

### How force is generated: trained vs grappler

| Without | Change in P(safe) | Situations hurt most |
|---|---|---|
| Push | -3.7 | Squared up at kicking range (-6.1); Aggressor at arm's length (-5.1); In your face (-4.5) |
| Rotational | -0.0 | Tied up (-0.1) |
| Whip | -0.0 |  |
| Drop | -0.0 |  |
| Linear | -0.0 |  |

## What training buys (untrained vs brawler)

| Situation | Untrained P(safe) | Best untrained response | Trained P(safe) |
|---|---|---|---|
| Squared up at kicking range | 83.1% | Advance | 95.9% |
| Aggressor at arm's length | 83.2% | Push | 94.8% |
| In your face | 82.0% | Retreat | 93.2% |
| Grabbed (headlock / dominant grip) | 61.5% | Break | 69.9% |
| Tied up | 75.5% | Break | 86.3% |
| Grabbed from behind | 48.1% | Turn | 54.1% |
| Down, attacker standing over you | 80.6% | GetUp | 91.1% |
| Tackled, attacker on top in your guard | 83.2% | Cover | 93.4% |
| Mounted | 62.6% | Cover | 69.4% |
| Back taken on the ground | 52.7% | Cover | 58.4% |

## Glossary

| Technique | Meaning | How it generates force | Target |
|---|---|---|---|
| Advance | step in |  |  |
| Retreat | step back |  |  |
| Circle | step offline to the outside angle |  |  |
| Flee | run |  |  |
| Cover | cover / guard |  |  |
| Slip | slip or L-step off the line |  |  |
| Parry | deflect (parry, tan sao) |  |  |
| Counter | simultaneous block-and-counter | Linear | Nose |
| Feint | feint |  |  |
| FingerJab | finger jab to the eyes (whip) | Whip | Eyes |
| Jab | jab to the nose | Linear | Nose |
| Cross | rear cross / palm heel to the jaw | Rotational | Jaw |
| Hook | lead hook to the temple | Rotational | Temples |
| Haymaker | wild haymaker | Rotational | Temples |
| BodyHook | shovel hook to the liver | Rotational | Liver |
| Elbow | elbow to the temple | Rotational | Temples |
| GroinKick | snap kick to the groin (whip) | Whip | Groin |
| ObliqueKick | oblique / stop kick to the knee | Linear | KneeLateral |
| LowKick | low round kick to the thigh | Rotational | ThighMuscle |
| RoundKick | round kick to the body | Rotational | Liver |
| Teep | push kick to the solar plexus | Push | SolarPlexus |
| Knee | knee to the groin (to the face if bent over) | Rotational | Groin |
| Headbutt | headbutt to the nose | Linear | Nose |
| Stomp | stomp (foot; head if down) | Drop | Foot |
| Push | two-hand shove | Push |  |
| Grab | grab / tie up |  |  |
| Shoot | tackle / takedown |  |  |
| Sprawl | sprawl against a tackle |  |  |
| Pummel | fight for the better grip |  |  |
| Throw | throw / trip / drag down |  |  |
| Break | break the grip and separate |  |  |
| Choke | choke |  |  |
| Turn | turn into him |  |  |
| Follow | follow him to the ground |  |  |
| BackOff | step away from the downed fighter |  |  |
| GetUp | technical stand-up |  |  |
| Upkick | upkick from the ground | Linear | Jaw |
| Pound | strike from top | Drop | Jaw |
| Pass | improve top position |  |  |
| Hold | hold / control |  |  |
| Disengage | get up and away from top |  |  |
| Escape | escape from underneath |  |  |
| Sweep | sweep from guard |  |  |
| GuardSub | submission from guard |  |  |

## Certificate

- trained vs brawler: 21232 positions, 967312 action pairs, 15412890 explicit outcomes; largest gap between the guaranteed floor and ceiling over all positions 2.1e-10 (0 = exact equilibrium).
- trained vs striker: 25222 positions, 2267090 action pairs, 40716672 explicit outcomes; largest gap between the guaranteed floor and ceiling over all positions 2.7e-15 (0 = exact equilibrium).
- trained vs grappler: 21232 positions, 951312 action pairs, 12294800 explicit outcomes; largest gap between the guaranteed floor and ceiling over all positions 7.6e-12 (0 = exact equilibrium).
- untrained vs brawler: 5480 positions, 85984 action pairs, 573400 explicit outcomes; largest gap between the guaranteed floor and ceiling over all positions 3.4e-10 (0 = exact equilibrium).
