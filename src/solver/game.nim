## The whole fight as an explicit finite stochastic game: every position
## reachable from the opening, the legal actions of each fighter there, and
## for every action pair the exact distribution over next positions.

import std/[deques]
import core, params, rules, matrix_game

type
  Game* = object
    dims*: Dims
    params*: Params          ## effective parameters (already rescaled to `dims`)
    arsenal*: array[Who, set[Action]]
    states*: seq[State]      ## id -> position
    idOf*: seq[int32]        ## dense state index -> id, or -1 if unreachable
    actOff*: array[Who, seq[int32]]   ## id -> offset into acts; length = states.len + 1
    acts*: array[Who, seq[Action]]
    pairOff*: seq[int32]     ## id -> first pair index; length = states.len + 1
    outOff*: seq[int32]      ## pair -> first outcome; length = pairs + 1
    target*: seq[int32]      ## outcome -> state id (>= 0) or terminal code (< 0)
    prob*: seq[float]
    stopValue*: seq[float]   ## id -> decision value if stopped there
    start*: int32

proc nActs*(g: Game, w: Who, s: int): int {.inline.} =
  int(g.actOff[w][s + 1] - g.actOff[w][s])

proc act*(g: Game, w: Who, s, i: int): Action {.inline.} =
  g.acts[w][int(g.actOff[w][s]) + i]

proc pairIndex*(g: Game, s, i, j: int): int {.inline.} =
  int(g.pairOff[s]) + i * g.nActs(wB, s) + j

proc outcomeCount*(g: Game): int = g.target.len

proc stateId*(g: Game, s: State): int =
  let x = encode(canonical(s), g.dims)
  int(g.idOf[x])

proc buildGame*(base: Params, arsenalA, arsenalB: set[Action],
                dims = defaultDims, start = startState()): Game =
  ## Breadth-first enumeration from `start`. Every transition is computed
  ## once and stored, so the state space is closed by construction.
  let p = effective(base, dims)
  result.dims = dims
  result.params = p
  result.arsenal = [arsenalA + CoreActions, arsenalB + CoreActions]
  result.idOf = newSeq[int32](stateCount(dims))
  for x in result.idOf.mitems: x = -1
  for w in Who: result.actOff[w].add 0'i32
  result.pairOff.add 0'i32
  result.outOff.add 0'i32

  var queue = initDeque[int32]()
  let s0 = canonical(start)
  result.idOf[encode(s0, dims)] = 0
  result.states.add s0
  queue.addLast 0'i32
  var next = 0
  while queue.len > 0:
    let id = queue.popFirst()
    assert id == next, "states are processed in id order"
    inc next
    let s = result.states[id]
    var legal: array[Who, seq[Action]]
    for w in Who:
      legal[w] = legalActions(p, s, w, result.arsenal[w], dims)
      if legal[w].len == 0 or legal[w].len > MaxActions:
        raise newException(ValueError, "bad action count in " & $s)
      for a in legal[w]: result.acts[w].add a
      result.actOff[w].add int32(result.acts[w].len)
    for a in legal[wA]:
      for b in legal[wB]:
        for o in resolve(p, s, a, b, dims):
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
    result.stopValue.add decisionValue(p, s)
  result.start = 0

proc buildGame*(base: Params, styleA, styleB: Style, dims = defaultDims): Game =
  buildGame(base, styleA.arsenal, styleB.arsenal, dims)

proc pairCount*(g: Game): int = g.outOff.len - 1

proc stateLabel*(g: Game, id: int): string = $g.states[id]
