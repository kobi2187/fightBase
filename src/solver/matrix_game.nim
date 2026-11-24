## Exact solution of small two-player zero-sum matrix games.
##
## The row player maximises, the column player minimises. The game value and
## both optimal mixed strategies come from one linear program solved with a
## dense simplex (Dantzig pricing with Bland's rule as an anti-cycling
## fallback). Pure saddle points are detected first, which settles most
## positions without the LP.

const MaxActions* = 16

type
  Matrix* = array[MaxActions, array[MaxActions, float]]
  Strategy* = array[MaxActions, float]

  GameSolution* = object
    value*: float
    x*: Strategy   ## row player's optimal mix (first m entries used)
    y*: Strategy   ## column player's optimal mix (first n entries used)
    pure*: bool    ## solved by a saddle point, no LP needed
    gap*: float    ## certified duality gap: max_i (M y)_i - min_j (x^T M)_j

proc certify*(M: Matrix, m, n: int, x, y: Strategy): (float, float) =
  ## (guaranteed floor for the row mix, guaranteed ceiling for the column mix)
  var lo = Inf
  for j in 0 ..< n:
    var s = 0.0
    for i in 0 ..< m: s += x[i] * M[i][j]
    lo = min(lo, s)
  var hi = -Inf
  for i in 0 ..< m:
    var s = 0.0
    for j in 0 ..< n: s += y[j] * M[i][j]
    hi = max(hi, s)
  (lo, hi)

proc saddle(M: Matrix, m, n: int, sol: var GameSolution): bool =
  var bestRow = 0
  var maximin = -Inf
  for i in 0 ..< m:
    var rmin = Inf
    for j in 0 ..< n: rmin = min(rmin, M[i][j])
    if rmin > maximin:
      maximin = rmin
      bestRow = i
  var bestCol = 0
  var minimax = Inf
  for j in 0 ..< n:
    var cmax = -Inf
    for i in 0 ..< m: cmax = max(cmax, M[i][j])
    if cmax < minimax:
      minimax = cmax
      bestCol = j
  if maximin >= minimax - 1e-15:
    sol.value = maximin
    for i in 0 ..< m: sol.x[i] = 0.0
    for j in 0 ..< n: sol.y[j] = 0.0
    sol.x[bestRow] = 1.0
    sol.y[bestCol] = 1.0
    sol.pure = true
    sol.gap = minimax - maximin
    return true
  false

proc solveMatrixGame*(M: Matrix, m, n: int): GameSolution =
  assert m >= 1 and n >= 1 and m <= MaxActions and n <= MaxActions
  if saddle(M, m, n, result): return

  # Shift so every payoff is >= 1; the value shifts by the same amount.
  var lo = Inf
  for i in 0 ..< m:
    for j in 0 ..< n: lo = min(lo, M[i][j])
  let shift = 1.0 - lo

  # Column player's LP: maximise sum(q) s.t. A q <= 1, q >= 0, A = M + shift.
  # Tableau: rows 1..m constraints, row 0 objective; columns 0..n-1 q,
  # n..n+m-1 slacks, last column rhs.
  const W = 2 * MaxActions + 1
  var t: array[MaxActions + 1, array[W, float]]
  let rhs = n + m
  for i in 0 ..< m:
    for j in 0 ..< n: t[i + 1][j] = M[i][j] + shift
    t[i + 1][n + i] = 1.0
    t[i + 1][rhs] = 1.0
  for j in 0 ..< n: t[0][j] = -1.0
  var basis: array[MaxActions, int]
  for i in 0 ..< m: basis[i] = n + i

  const eps = 1e-12
  var iterations = 0
  while true:
    inc iterations
    let bland = iterations > 50
    var enter = -1
    var best = -eps
    for j in 0 ..< n + m:
      if t[0][j] < best:
        enter = j
        if bland: break
        best = t[0][j]
    if enter < 0: break
    var leave = -1
    var ratio = Inf
    for i in 0 ..< m:
      let a = t[i + 1][enter]
      if a > eps:
        let r = t[i + 1][rhs] / a
        if r < ratio - eps or (abs(r - ratio) <= eps and leave >= 0 and basis[i] < basis[leave]):
          ratio = r
          leave = i
    if leave < 0:
      raise newException(ArithmeticDefect, "matrix game LP unbounded (should not happen)")
    let pv = t[leave + 1][enter]
    for j in 0 .. rhs: t[leave + 1][j] /= pv
    for i in 0 .. m:
      if i != leave + 1:
        let f = t[i][enter]
        if f != 0.0:
          for j in 0 .. rhs: t[i][j] -= f * t[leave + 1][j]
    basis[leave] = enter
    if iterations > 10_000:
      raise newException(ArithmeticDefect, "simplex did not terminate")

  let z = t[0][rhs]                 # = sum(q) = 1 / shifted value
  let v = 1.0 / z
  for j in 0 ..< n: result.y[j] = 0.0
  for i in 0 ..< m:
    if basis[i] < n: result.y[basis[i]] = t[i + 1][rhs] * v
  for i in 0 ..< m: result.x[i] = max(0.0, t[0][n + i]) * v
  # Renormalise away rounding noise.
  var sx, sy = 0.0
  for i in 0 ..< m: sx += result.x[i]
  for j in 0 ..< n: sy += result.y[j]
  for i in 0 ..< m: result.x[i] /= sx
  for j in 0 ..< n: result.y[j] /= sy
  let (floor, ceiling) = certify(M, m, n, result.x, result.y)
  result.value = 0.5 * (floor + ceiling)
  result.gap = ceiling - floor
  result.pure = false
