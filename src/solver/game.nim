## The whole confrontation as an explicit finite stochastic game: every
## position reachable from the given starting positions, the legal actions of
## each fighter there, and for every action pair the exact distribution over
## next positions.

import std/[deques]
import core, params, rules, matrix_game

type
  Game* = object
    dims*: Dims
    mode*: Mode
    params*: Params          ## effective parameters (global knobs folded in)
    arsenal*: array[Who, set[Action]]
    states*: seq[State]      ## id -> position
    idOf*: seq[int32]        ## dense state index -> id, or -1 if unreachable
    actOff*: array[Who, seq[int32]]   ## id -> offset into acts; length = states.len + 1
    acts*: array[Who, seq[Action]]
    pairOff*: seq[int32]     ## id -> first pair index; length = states.len + 1
    outOff*: seq[int32]      ## pair -> first outcome; length = pairs + 1
    target*: seq[int32]      ## outcome -> state id (>= 0) or terminal code (< 0)
    prob*: seq[float]
    stopValue*: seq[float]   ## id -> value for A if the encounter ends there
    start*: int32            ## id of the first starting position

proc nActs*(g: Game, w: Who, s: int): int {.inline.} =
  int(g.actOff[w][s + 1] - g.actOff[w][s])

proc act*(g: Game, w: Who, s, i: int): Action {.inline.} =
  g.acts[w][int(g.actOff[w][s]) + i]

proc actIndex*(g: Game, w: Who, s: int, a: Action): int =
  for i in 0 ..< g.nActs(w, s):
    if g.act(w, s, i) == a: return i
  -1

proc pairIndex*(g: Game, s, i, j: int): int {.inline.} =
  int(g.pairOff[s]) + i * g.nActs(wB, s) + j

proc outcomeCount*(g: Game): int = g.target.len

proc pairCount*(g: Game): int = g.outOff.len - 1

proc stateId*(g: Game, s: State): int =
  let x = encode(canonical(s), g.dims)
  if x < 0 or x >= g.idOf.len: return -1
  int(g.idOf[x])

proc buildGame*(base: Params, arsenalA, arsenalB: set[Action],
                dims = defaultDims, mode = mSelfDefense,
                starts: openArray[State] = [startState()]): Game =
  ## Breadth-first enumeration from the starting positions. Every transition
  ## is computed once and stored, so the state space is closed by
  ## construction.
  let p = effective(base)
  result.dims = dims
  result.mode = mode
  result.params = p
  result.arsenal = [arsenalA + CoreActions, arsenalB + CoreActions]
  result.idOf = newSeq[int32](stateCount(dims))
  for x in result.idOf.mitems: x = -1
  for w in Who: result.actOff[w].add 0'i32
  result.pairOff.add 0'i32
  result.outOff.add 0'i32

  var queue = initDeque[int32]()
  for st in starts:
    let s0 = canonical(st)
    let x = encode(s0, dims)
    if result.idOf[x] < 0:
      result.idOf[x] = int32(result.states.len)
      result.states.add s0
      queue.addLast result.idOf[x]
  var next = 0
  while queue.len > 0:
    let id = queue.popFirst()
    assert id == next, "states are processed in id order"
    inc next
    let s = result.states[id]
    var legal: array[Who, seq[Action]]
    for w in Who:
      legal[w] = legalActions(p, s, w, result.arsenal[w], dims, mode)
      if legal[w].len == 0 or legal[w].len > MaxActions:
        raise newException(ValueError, "bad action count " & $legal[w].len & " in " & $s)
      for a in legal[w]: result.acts[w].add a
      result.actOff[w].add int32(result.acts[w].len)
    for a in legal[wA]:
      for b in legal[wB]:
        for o in resolve(p, s, a, b, dims, mode):
          var t = o.target
          if t >= 0:
            var tid = result.idOf[t]
            if tid < 0:
              tid = int32(result.states.len)
              result.idOf[t] = tid
              result.states.add decodeState(t, dims)
              queue.addLast tid
            t = tid
          result.target.add t
          result.prob.add o.p
        result.outOff.add int32(result.target.len)
    result.pairOff.add int32(result.outOff.len - 1)
    result.stopValue.add stopValue(p, s, mode)
  result.start = 0

proc buildGame*(base: Params, styleA, styleB: Style, dims = defaultDims,
                mode = mSelfDefense, starts: openArray[State] = [startState()]): Game =
  buildGame(base, styleA.arsenal, styleB.arsenal, dims, mode, starts)

proc stateLabel*(g: Game, id: int): string = $g.states[id]
