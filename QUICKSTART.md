# Quick Start - See It In Action! 🥊

## 1. Install Nim (if not already installed)

```bash
curl https://nim-lang.org/choosenim/init.sh -sSf | sh
export PATH=$HOME/.nimble/bin:$PATH
```

## 2. Test the Notation System

```bash
cd /home/user/fightBase
nim c -r src/fight_notation.nim
```

You'll see:
- **FPN** (Fight Position Notation) - compact state like chess FEN
- **Visual Board** - ASCII art fight visualization
- **Compact representation** - one-line state summary

Example output:
```
=== FPN Test ===
FPN: o.95.15.0.3,5.10,15,55,0,0.----/s.90.20.5.-1,0.-5,-10,45,0,0.----/m/A/5

=== Visual Board ===
╔═══════════════════════════════════════════════════════════╗
║                    FIGHT STATE                            ║
╠═══════════════════════════════════════════════════════════╣
║ Fighter A (o)                                               ║
║   Balance:  95%  Fatigue:  15%  Damage:   0%   ║
║   Limbs: ----  Momentum:  +3 lin,  +5 rot ║
║                                                           ║
║                  ←    MEDIUM    →                  ║
║                                                           ║
║ Fighter B (s)                                               ║
║   Balance:  90%  Fatigue:  20%  Damage:   5%   ║
║   Limbs: ----  Momentum:  -1 lin,  +0 rot ║
╠═══════════════════════════════════════════════════════════╣
║ Turn: A   Move:   5                                      ║
╚═══════════════════════════════════════════════════════════╝
```

## 3. Watch a Live Fight Simulation!

### Interactive Mode (step-by-step)
```bash
nim c -r src/visualize.nim --mode=interactive
```

Press ENTER to advance each move. You'll see:
- Viable moves at each position
- Selected action sequence
- Vulnerability targets
- Updated fight state after each ply

### Auto Mode (watch it flow)
```bash
nim c -r src/visualize.nim --mode=auto
```

Fights play automatically with 500ms delay between moves.

### Batch Mode (statistics)
```bash
nim c -r src/visualize.nim --mode=batch --fights=10
```

Runs multiple fights and shows summary stats.

## 4. Understanding the Visualization

### Fighter Status
```
Balance:  95%   # How stable (0% = falling, 100% = perfect)
Fatigue:  15%   # Energy spent (0% = fresh, 100% = exhausted)
Damage:   5%    # Accumulated damage (100% = incapacitated)
```

### Limb Status
```
----   All limbs free
-E--   Right arm extended
X---   Left arm damaged
BE--   Right arm both damaged and extended
```

### Stance Codes
```
o = Orthodox (left foot forward)
s = Southpaw (right foot forward)
n = Neutral
q = Square
w = Wide
b = Bladed
z = Wrestling
```

### Distance Codes
```
c = Contact (0-0.3m) - grappling range
s = Short (0.3-0.8m) - elbow/knee range
m = Medium (0.8-1.5m) - punching range
l = Long (1.5-2.5m) - kicking range
v = Very Long (2.5m+) - out of range
```

## 5. What You're Seeing

The simulation demonstrates:

### Vulnerability Targeting
Watch how strikes target specific body zones:
```
Selected sequence (2 moves):
  → Straight Strike [targets: vzNose, vzThroat, vzSolarPlexus, vzEyes]
  → Low Kick [targets: vzThighMuscle, vzKneeLateral, vzCalf]
```

### Tactical Liquidity
The system picks moves that:
- Create more options (high optionsCreated)
- Minimize exposure (low exposureRisk)
- Conserve energy (low energyCost)

### Physics-Based Combinations
Notice how moves combine realistically:
```
Selected sequence (3 moves):
  → Slip Left [mtEvasion]
  → Parry Left [mtDeflection]
  → Straight Strike [mtOffensive]
```
This works because: different limbs, different categories, within time budget (0.6s).

### Momentum & Biomechanics
Watch the momentum values change:
```
Momentum:  +3 lin,  +5 rot   # Before strike
Momentum:  +6 lin, +45 rot   # After low kick (heavy rotation!)
```

## 6. The "AlphaGo Moment"

You're watching the engine:
1. Calculate which moves are **viable** (physics-based)
2. Score by **target vulnerability** (force required vs compliance)
3. Consider **tactical liquidity** (options created)
4. Build **multi-move sequences** (within 0.6s ply budget)
5. Update **biomechanical state** (momentum, balance, recovery)

Eventually, backward propagation will find surprising optimal sequences like:
- "Groin strike is 95% optimal from close orthodox vs southpaw"
- "Parry-slip-throat is faster than slip-parry-throat by 0.3 compliance points"

## 7. Next Steps

### Run More Simulations
```bash
# Long fight
nim c -r src/visualize.nim --mode=auto

# Many fights for statistics
nim c -r src/visualize.nim --mode=batch --fights=100
```

### Build the Tablebase
```bash
nim c src/fightBase.nim
./fightBase batch --runs=1000 --threads=1
```

This will:
- Run 1000 fight simulations
- Store all states in SQLite
- Log unknown states for review
- Build the graph of reachable positions

### Analyze Results
```bash
./fightBase stats
./fightBase list --limit=20
```

## FPN Examples (for later analysis)

Save interesting positions as FPN strings:

```
# Initial orthodox vs southpaw at medium range
o.100.0.0.0,0.0,0,50,0,0.----/s.100.0.0.0,0.0,0,50,0,0.----/m/A/0

# After a successful low kick (B damaged, off-balance)
o.95.20.0.2,15.15,25,55,0,0.----/s.75.25.8.-3,0.-5,-12,40,1,3.--E-/s/A/3

# Close-range exchange (both fatigued, damaged)
o.70.55.12.1,8.25,30,60,0,0.-E--/s.65.60.15.-2,5.-10,-15,45,1,2.E---/c/B/8
```

These strings are:
- **Deterministic** - Same FPN always = same state
- **Compact** - Easy to store/transmit
- **Parseable** - Can reconstruct exact state
- **Human-readable** - With practice!

---

## Troubleshooting

### "nim: command not found"
Add Nim to PATH:
```bash
export PATH=$HOME/.nimble/bin:$PATH
```

### Compilation errors
Make sure Nim version is 1.6.0+:
```bash
nim --version
```

### "No viable moves" immediately
This means the initial state has no physics-valid moves. This is a bug - report it!

---

Enjoy watching the martial arts tablebase come to life! 🥋
