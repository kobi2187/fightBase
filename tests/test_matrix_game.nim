## The exact matrix-game solver: known games, and random games checked by
## their own certificate (the guaranteed floor and ceiling must meet).

import std/[unittest, random, math]
import solver/matrix_game

proc mat(rows: seq[seq[float]]): (Matrix, int, int) =
  var M: Matrix
  for i, r in rows:
    for j, v in r: M[i][j] = v
  (M, rows.len, rows[0].len)

proc check(sol: GameSolution, M: Matrix, m, n: int) =
  var sx, sy = 0.0
  for i in 0 ..< m:
    check sol.x[i] >= -1e-12
    sx += sol.x[i]
  for j in 0 ..< n:
    check sol.y[j] >= -1e-12
    sy += sol.y[j]
  check abs(sx - 1.0) < 1e-9
  check abs(sy - 1.0) < 1e-9
  let (lo, hi) = certify(M, m, n, sol.x, sol.y)
  check hi - lo < 1e-9
  check lo <= sol.value + 1e-9
  check sol.value <= hi + 1e-9

suite "matrix games":
  test "rock-paper-scissors is worth 0 with uniform play":
    let (M, m, n) = mat(@[@[0.0, -1, 1], @[1.0, 0, -1], @[-1.0, 1, 0]])
    let s = solveMatrixGame(M, m, n)
    check abs(s.value) < 1e-12
    for i in 0 .. 2:
      check abs(s.x[i] - 1/3) < 1e-9
      check abs(s.y[i] - 1/3) < 1e-9
    check(s, M, m, n)

  test "matching pennies is worth 1/2":
    let (M, m, n) = mat(@[@[1.0, 0], @[0.0, 1]])
    let s = solveMatrixGame(M, m, n)
    check abs(s.value - 0.5) < 1e-12
    check(s, M, m, n)

  test "2x2 without a saddle point matches the closed form":
    let (a, b, c, d) = (0.9, 0.2, 0.3, 0.7)
    let (M, m, n) = mat(@[@[a, b], @[c, d]])
    let s = solveMatrixGame(M, m, n)
    check abs(s.value - (a * d - b * c) / (a + d - b - c)) < 1e-12
    check abs(s.x[0] - (d - c) / (a + d - b - c)) < 1e-9
    check(s, M, m, n)

  test "saddle points are found without the LP":
    let (M, m, n) = mat(@[@[0.4, 0.6, 0.5], @[0.3, 0.2, 0.1]])
    let s = solveMatrixGame(M, m, n)
    check s.pure
    check abs(s.value - 0.4) < 1e-12
    check s.x[0] == 1.0
    check s.y[0] == 1.0

  test "dominated strategies get no weight":
    let (M, m, n) = mat(@[@[1.0, 0, 0.5], @[0.0, 1, 0.5], @[-1.0, -1, -1]])
    let s = solveMatrixGame(M, m, n)
    check s.x[2] < 1e-12
    check(s, M, m, n)

  test "one row or one column":
    let (M, m, n) = mat(@[@[0.3, 0.8, 0.5]])
    let s = solveMatrixGame(M, m, n)
    check abs(s.value - 0.3) < 1e-12
    let (M2, m2, n2) = mat(@[@[0.3], @[0.8], @[0.5]])
    check abs(solveMatrixGame(M2, m2, n2).value - 0.8) < 1e-12

  test "300 random games up to 24x24 certify themselves":
    var r = initRand(20261124)
    for t in 0 ..< 300:
      let m = r.rand(1 .. MaxActions)
      let n = r.rand(1 .. MaxActions)
      var M: Matrix
      for i in 0 ..< m:
        for j in 0 ..< n:
          # include ties and degenerate structure now and then
          M[i][j] = if r.rand(1.0) < 0.2: round(r.rand(1.0) * 4) / 4 else: r.rand(1.0)
      let s = solveMatrixGame(M, m, n)
      check(s, M, m, n)
