# The equilibrium solver and the self-defense playbook

`src/solver/` turns the FightBase idea, a chess-style tablebase for fighting,
into something that can actually be computed exactly, and uses it to produce a
**static self-defense playbook** (`docs/playbook/`): for ten common situations,
which response is best, how good every alternative is, which combinations work,
and what each weak point and way of generating force is worth.

Everything here is a model. The solver is exact *for the model*; the model is
a set of explicit, documented assumptions. Read [Limits](#limits) before
relying on any number.

## Why not the original tree generator?

The original `game_tree.nim` approach cannot converge to a tablebase:

- The position hash includes raw floats (position, balance, momentum) and
  momentum never decays, so positions almost never repeat. Measured: the
  frontier grows about 8x per ply with no sign of closing.
- Moves call `rand()` inside `apply`, so expanding a move once keeps one random
  outcome and records it as if it were certain.
- Fighters alternate turns, which hands the second mover perfect knowledge of
  the first mover's commitment. Real exchanges are simultaneous.
- The win condition depends on damage that is kept outside the position, so
  a position's value depends on how you reached it, and backward induction
  is undefined.

The solver keeps the vision (exhaustive, exact, backward-solved positions)
and fixes the formulation.

## Formulation

A confrontation is a **two-player, zero-sum, simultaneous-move stochastic
game** (a Shapley game):

- Every beat (an exchange of roughly a second) both fighters choose an action
  at the same time.
- Each pair of actions resolves into an **explicit probability distribution**
  over next positions. There is no hidden randomness.
- The game ends by incapacitation, a choke, an escape, or a stoppage (each
  beat has a `stopChance` of the encounter just ending).
- The value of a position is the probability that you (fighter A) come out
  safe:

```
V(s) = stop * stopValue(s) + (1 - stop) * val( M_s )
M_s[i][j] = sum over outcomes o of P(o | s, i, j) * V(o)
```

where `val` is the value of the matrix game (you maximise, the attacker
minimises). Optimal play is generally a **mixed strategy**, a probability for
each action, because a predictable fighter can be exploited. That is the
formal reason for feints and for varying your responses.

**Self-defense mode** (default): A is the defender. Getting away, or the
attacker being incapacitated or choked, is worth 1; being incapacitated or
choked is worth 0. A stoppage is scored by the harm you carry (damage levels,
hurt legs) and by whether you are down or pinned. Only the defender can run.

**Sport mode** (`--sport`): symmetric, no escaping, and judges score
stoppages on damage and position. A symmetric matchup must be worth exactly
0.5, which the tests use as a check.

## The position

Everything that can change the outcome is in the position, so a position's
value depends on the position only, and everything is discrete:

| Part | Values |
|---|---|
| Geometry (shared) | kicking range; punching range and elbow range, each with or without one fighter holding the outside angle; tie-up (even or one fighter dominant); held from behind; one fighter down; guard, mount and back on the ground. 20 positions in total, each "advantaged" form named after the fighter who holds it |
| Damage (each fighter) | 0–3; the 4th level incapacitates (`--damage-levels` to change) |
| Condition | ok, off-balance (after a committed miss, a push, a hit), or **stunned** (pain/reflex shock from a weak-point hit). Lasts one beat unless renewed. A stunned fighter can only cover, back off or hold on |
| Hip loading | which side is wound up for a rotational strike (normal stance loads the rear side) |
| Legs | hurt or not (knee and thigh damage): no hard kicks, slower footwork, harder to run or chase |

A trained defender facing a brawler starting from the ten playbook situations
gives about 21,000 reachable positions, 1 million action pairs and
14 million explicit outcomes.

## Techniques and the body

Each technique has a **mechanism**, a **side**, a **speed**, a **force** and
a **target zone** (`src/solver/core.nim`, `tech` table):

| Mechanism | Examples | Character |
|---|---|---|
| Whip | finger jab to the eyes, snap kick to the groin | fastest, light; made for low-threshold targets |
| Linear | jab, oblique (stop) kick to the knee, headbutt | fast, little wind-up; good for interception |
| Rotational | cross / palm heel, hook, shovel hook, elbow, knee, low and round kicks | heavy; needs the side to be loaded |
| Push | push kick (teep), shove | moves the opponent back and off-balance |
| Drop | stomp, strikes from top | body weight; for a downed opponent |

**Rotational force and combinations.** A rotational strike from the loaded
side gets full power and speed. From the unwound side it has `unloadedPower`
(0.55) of its force and is one speed step slower (it needs a wind-up).
Throwing it unwinds that side and loads the other. So a cross loads the lead
hook, the hook reloads the cross, and two crosses in a row are weaker: chaining
rotations matters, and the solver can see it. The playbook reports damage
dealt per combination, which shows it directly: cross→hook deals noticeably
more than cross→cross.

**Weak points.** Target data comes from the repo's body model,
`src/vulnerabilities.nim`: the force each zone needs, how exposed it is, and
what kind of effect it has (reflex, pain, structural, disabling, systemic,
compliance, recovery time). `src/solver/body.nim` turns that into
probabilities:

- **Effect strength** `e = clamp(0.2 + 0.2 * log2(force / threshold), 0, 1)`.
  Just reaching the threshold gives 0.2; 16x the threshold is certain.
- **Precision:** a landed strike hits its zone squarely with probability
  set by the zone's size (eyes 35%, thigh 90%). Otherwise it glances off
  with 30% of its force.
- **Effects** scale with `e`:
  - **Stun:** reflex zones, with probability compliance × pain.
  - **Damage:** disabling and systemic zones, more likely two levels at once
    when the recovery time is long.
  - **Legs hurt:** structural leg zones.

That is why low-threshold targets (eyes 5 N, groin 10 N, solar plexus 30 N)
stun reliably when hit squarely, while the jaw (200 N) mostly accumulates
damage.

## Rules of a beat

`src/solver/rules.nim`, in order:

1. **Primary events.** Strikes miss or land, with their effect. Grabs,
   tackles, throws, turns, escapes and runs succeed or fail. Probabilities
   depend on both actions:
   - defending (cover, slip, parry, counter) works differently against each
     mechanism;
   - stepping in jams kicks but walks into punches;
   - straight techniques intercept committing attacks;
   - a feint draws a fighter who waits to counter.
2. **Initiative.** The faster action resolves first; if it succeeds, it cuts
   the slower one's chance. Equal speeds trade.
3. **Coin flips.** Knockdowns, ending off-balance, taking the outside angle,
   being caught while running (maybe from behind).
4. **New position**, in priority order: finish > escape > knockdown >
   takedown > grab > footwork. Damage, stuns and leg injuries are recorded,
   and hips re-load.

The rules refer only to "a fighter" and "their opponent", never to A or B.
The test suite checks the mirror symmetry exhaustively in sport mode (more
than 10,000 state-and-action-pair combinations).

## The solver and its certificate

`src/solver/matrix_game.nim` solves each position's matrix game exactly: a
saddle-point check first, then a dense simplex (Dantzig pricing, Bland's rule
against cycling) that yields both players' optimal mixes. Each solution's
duality gap is certified.

`src/solver/solve.nim` runs Shapley value iteration (Gauss–Seidel) with an
acceleration: after each exact sweep the strategies are frozen for a few cheap
sweeps over only the action pairs actually played. If progress stalls it
backs off, down to plain value iteration.

**Certificate.** With your computed strategy frozen, the attacker's best
response gives the value you are *guaranteed*. With his frozen, your best
response gives the most you can get. Their gap is the **exploitability**. For
the playbook games it is about 10⁻¹⁰ or less at every position, which makes
these equilibria exact to numerical precision, not approximations.

## What you can ask it

| Command | Answers |
|---|---|
| `fightsolve playbook` | the static playbook: Markdown, HTML and JSON in `docs/playbook/` |
| `fightsolve solve --pos Mid --a trained --b brawler` | value, certificate, how encounters end, technique use and accuracy, targets hit |
| `fightsolve explain --pos ClinchB --b-stun` | mixed strategies and the full payoff matrix at one position |
| `fightsolve ablate --by zone` | what each target zone (or technique, or mechanism) is worth |
| `fightsolve matchups --pos Mid` | defender profiles × attacker profiles |
| `fightsolve sensitivity --query ablate:GroinKick` | does a conclusion survive ±25% on every parameter? |
| `fightsolve params` | every assumption, as JSON; `--params FILE` overrides any subset |
| `fightsolve calibrate` | sport mode: fit the global knobs to UFC finish rates (`data/calibration_targets.json`) |

The playbook scores responses and combinations several ways:

- **Expected:** P(safe) against an attacker playing his optimal strategy.
- **If he picks the best reply:** that beat's worst case.
- **Combinations** are plans you commit to. They are scored against an optimal
  attacker and against an attacker who knows the whole plan, with damage
  dealt, stuns, damage taken, and how often every step could be executed.
- **Lines:** the sequences optimal play actually follows.
- **Weapons:** remove a target zone, a mechanism or a technique, re-solve
  every situation, and report the drop in P(safe). In a zero-sum game removing
  an option can never help, and the tests check that.
- **Robustness:** each top response is re-derived with every family of
  assumptions (`paramFamilies` in `params.nim`) scaled by ±25%.

## Profiles

Defenders:
- `trained`: footwork, deflection, counters, weak-point strikes, escapes.
- `untrained`: instinctive covering, shoving, wild swings, running.

Attackers:
- `brawler`: shoves, grabs, haymakers, tackles, headlocks, stomps.
- `striker`: trained striking.
- `grappler`: takedowns, clinch, chokes.

`complete` has every technique (sport mode). Arsenals are listed in
`core.nim`.

## Limits

- **The numbers are assumptions.** Forces follow the repo's biomechanics
  documents; thresholds and effect flags follow `vulnerabilities.nim`. Hit
  chances, defensive multipliers and the rest are judgement calls. The solver
  finds the best play *given them*. Conclusions marked robust survive ±25%
  changes to whole families of assumptions; others may be artefacts.
- **Discretisation.** Range is three bands plus angles, damage is four
  levels, condition is three states. Finer detail (exact footwork, specific
  grips, multiple attackers, weapons, environment) is not modelled.
- **Rational opponents.** Equilibrium play assumes both sides choose well.
  Against a predictable attacker, the "answers to his attacks" tables are
  the relevant ones.
- **Calibration.** In sport mode the global knobs can be fitted to aggregate
  UFC outcomes (finish rates, strike accuracy). That calibrates the overall
  pace, not individual techniques, and street encounters differ from sport.
- **Not advice.** This is a research model. Avoiding and leaving a
  confrontation beats any technique in this document, and the model agrees:
  escape dominates wherever it is possible.

## Code map

| File | Role |
|---|---|
| `src/solver/core.nim` | positions, fighter state, encoding, techniques (mechanism, side, speed, target), profiles |
| `src/solver/params.nim` | every number, named; JSON overrides; families for robustness checks |
| `src/solver/body.nim` | target zones from `vulnerabilities.nim` → effect probabilities |
| `src/solver/rules.nim` | legal actions and the resolution of a beat |
| `src/solver/game.nim` | breadth-first enumeration into an explicit game |
| `src/solver/matrix_game.nim` | exact zero-sum matrix games |
| `src/solver/solve.nim` | value iteration, best responses, certificate |
| `src/solver/analysis.nim` | exact statistics of optimal play |
| `src/solver/studies.nim` | ablation, matchups, sensitivity, calibration |
| `src/solver/playbook.nim` | scenarios, response scoring, lines, combination search, robustness |
| `src/solver/playbook_render.nim` | Markdown / HTML / JSON output |
| `src/fightsolve.nim` | command-line interface |
| `tests/` | 35 tests: matrix games, model invariants, symmetry, solver, playbook identities |

Run the tests with `nimble test`, and regenerate the playbook with
`nimble playbook` (about 40 minutes with robustness checks).
