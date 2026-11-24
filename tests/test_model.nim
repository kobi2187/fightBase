## Invariants of the fight model: encodings, distributions, mirror symmetry,
## body effects and hip loading.

import std/[unittest, math, tables]
import solver/[core, params, body, rules, game]

const small = Dims(damageLevels: 2)

proc sportSymmetricGame(): Game =
  ## A symmetric sport game small enough to check exhaustively.
  let arsenal = {aCircle, aSlip, aParry, aCounter, aFeint, aJab, aCross, aHook,
                 aGroinKick, aTeep, aKnee, aPush, aGrab, aShoot, aSprawl, aPummel,
                 aThrow, aChoke, aStomp, aUpkick, aPound, aPass, aSweep, aGuardSub,
                 aElbow, aHeadbutt, aFingerJab}
  buildGame(defaultParams(), arsenal, arsenal, small, mSport,
            [State(pos: pLong), State(pos: pClinch), State(pos: pBehindA),
             State(pos: pOverA), State(pos: pMountA)])

suite "encoding":
  test "every state index round-trips":
    let d = defaultDims
    for x in 0 ..< stateCount(d):
      check encode(decodeState(x, d), d) == x

  test "swapping labels twice is the identity":
    for p in Pos:
      check swapPos(swapPos(p)) == p
    let s = State(pos: pMidAngA, f: [wA: Fighter(dmg: 1, cond: cOff), wB: Fighter(coil: coLead, legs: true)])
    check swap(swap(s)) == s

  test "canonical form clears what does not matter on the ground":
    let s = canonical(State(pos: pMountB, f: [wA: Fighter(cond: cOff, coil: coLead), wB: Fighter(cond: cOff)]))
    check s.f[wA].cond == cOk
    check s.f[wA].coil == coRear
    check s.f[wB].cond == cOk

suite "distributions":
  test "every action pair resolves to a probability distribution (self-defense)":
    let g = buildGame(defaultParams(), findStyle("trained"), findStyle("brawler"), small,
                      mSelfDefense, [State(pos: pMid), State(pos: pBehindB), State(pos: pOverB)])
    check g.states.len > 100
    for pair in 0 ..< g.pairCount:
      var total = 0.0
      for o in g.outOff[pair] ..< g.outOff[pair + 1]:
        check g.prob[o] > 0.0
        check g.target[o] < int32(g.states.len)
        total += g.prob[o]
      check abs(total - 1.0) < 1e-9

  test "legal actions are never empty and fit the solver":
    let g = sportSymmetricGame()
    for s in 0 ..< g.states.len:
      for w in Who:
        check g.nActs(w, s) >= 1

  test "only the defender can run, and only in self-defense":
    let p = defaultParams()
    let s = State(pos: pLong)
    check aFlee in legalActions(p, s, wA, AllActions, small, mSelfDefense)
    check aFlee notin legalActions(p, s, wB, AllActions, small, mSelfDefense)
    check aFlee notin legalActions(p, s, wA, AllActions, small, mSport)

  test "a stunned fighter can only protect himself":
    let p = defaultParams()
    let s = State(pos: pMid, f: [wA: Fighter(cond: cStunned), wB: Fighter()])
    for a in legalActions(p, s, wA, AllActions, small, mSelfDefense):
      check a in StunnedActions

suite "mirror symmetry (sport mode)":
  test "swapping the fighters swaps every outcome distribution":
    let g = sportSymmetricGame()
    let p = g.params
    var checked = 0
    for id in 0 ..< g.states.len:
      let s = g.states[id]
      let m = swap(s)
      for i in 0 ..< g.nActs(wA, id):
        for j in 0 ..< g.nActs(wB, id):
          let a = g.act(wA, id, i)
          let b = g.act(wB, id, j)
          var lhs = initTable[int32, float]()
          for o in resolve(p, s, a, b, small, mSport):
            let t = if o.target >= 0: int32(encode(canonical(swap(decodeState(o.target, small))), small))
                    else:
                      case toTerminal(o.target)
                      of tAKO: terminalCode(tBKO)
                      of tBKO: terminalCode(tAKO)
                      of tASub: terminalCode(tBSub)
                      of tBSub: terminalCode(tASub)
                      else: o.target
            lhs.mgetOrPut(t, 0.0) += o.p
          var rhs = initTable[int32, float]()
          for o in resolve(p, m, b, a, small, mSport):
            rhs.mgetOrPut(o.target, 0.0) += o.p
          check lhs.len == rhs.len
          for t, v in lhs:
            check abs(v - rhs.getOrDefault(t, -1.0)) < 1e-12
          inc checked
    check checked > 10_000

suite "body":
  test "effect strength grows with force and saturates":
    var last = -1.0
    for f in [1.0, 5.0, 10.0, 20.0, 50.0, 200.0, 1000.0]:
      let e = effectStrength(f, 20.0, 0.2, 0.2)
      check e >= last
      check e >= 0.0 and e <= 1.0
      last = e
    check effectStrength(20.0, 20.0, 0.2, 0.2) == 0.2
    check effectStrength(320.0, 20.0, 0.2, 0.2) == 1.0

  test "zone profiles come from the repo's body model":
    for z in VulnerabilityZone:
      let pr = zoneProfiles[z]
      check pr.stun >= 0.0 and pr.stun <= 1.0
      check pr.dmg1 >= 0.0 and pr.dmg2 >= 0.0 and pr.dmg1 + pr.dmg2 <= 1.0
      check pr.force > 0.0
    check zoneProfiles[vzKneeLateral].legs > 0.0      # structural leg target
    check zoneProfiles[vzJaw].legs == 0.0
    check zoneProfiles[vzEyes].force < zoneProfiles[vzJaw].force
    check zoneProfiles[vzGroin].stun > zoneProfiles[vzThighMuscle].stun

  test "strike effects form a distribution":
    for z in [vzEyes, vzJaw, vzLiver, vzKneeLateral]:
      var total = 0.0
      for e in strikeEffects(z, 0.7, 1.2, 1.0, 1.0): total += e.p
      check abs(total - 1.0) < 1e-12

suite "hip loading":
  test "a rotational strike unwinds its side and loads the other":
    let f = Fighter(coil: coRear)
    check loaded(f, aCross)
    check not loaded(f, aHook)
    check nextCoil(f, aCross) == coLead
    check loaded(Fighter(coil: nextCoil(f, aCross)), aHook)
    check nextCoil(Fighter(coil: coLead), aHook) == coRear
    check nextCoil(f, aJab) == coRear          # linear strikes keep the hips

  test "the second rotational strike lands harder from the loaded side":
    # Cross then hook (loaded) vs cross then cross (unwound): compare the
    # damage the second strike does from the position the cross leaves.
    let p = effective(defaultParams())
    let afterCross = State(pos: pClose, f: [wA: Fighter(coil: coLead), wB: Fighter()])
    proc dealt(a: Action): float =
      for o in resolve(p, afterCross, a, aCover, small, mSelfDefense):
        if o.target >= 0:
          result += o.p * decodeState(o.target, small).f[wB].dmg.float
        elif toTerminal(o.target) == tAKO:
          result += o.p * small.damageLevels.float
    check dealt(aHook) > dealt(aCross)
