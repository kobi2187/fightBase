# MPN (Mannequin Position Notation)

Pure physical pose notation for 3D visualization - **NO game state**, just joint angles.

## Philosophy

MPN separates **physical pose** from **game state**:
- **MPN** = Joint angles, rotations, body position (visualization)
- **FPN** = Balance, fatigue, damage, recovery (game simulation)

The pose is "the position or state as a consequence of the last move."

## Format

### Single Fighter
```
lean.rotation.shoulders.elbows.hips.knees.stance
```

### Full Scene
```
fighter_a_mpn/fighter_b_mpn/distance
```

## Components

### 1. Lean (cm)
```
forward_back,left_right
```
- `forward_back`: -30 to +30 cm (+ = forward, - = back)
- `left_right`: -20 to +20 cm (+ = right, - = left)

**Example:** `5,0` = 5cm forward lean, no side lean

### 2. Rotation (degrees)
```
hip,torso,neck
```
- `hip`: -45 to +45° (rotation around vertical axis)
- `torso`: -35 to +35° (relative to hips)
- `neck`: -30 to +30° (head turn)

**Example:** `10,15,2` = 10° hip rotation, 15° torso rotation, 2° neck turn

### 3. Shoulders (degrees)
```
left_pitch,left_roll,right_pitch,right_roll
```
- `pitch`: -60 to +60° (forward/back swing)
- `roll`: 0 to 60° (raising arm sideways)

**Example:** `20,10,25,15` = Left shoulder (20° pitch, 10° roll), Right shoulder (25° pitch, 15° roll)

### 4. Elbows (degrees)
```
left_bend,right_bend
```
- `0` = straight arm
- `90` = right angle (guard position)
- `150` = fully bent

**Example:** `90,95` = Left elbow 90° bent, Right elbow 95° bent

### 5. Hips (degrees)
```
left_pitch,left_roll,right_pitch,right_roll
```
- `pitch`: -20 to +80° (leg forward/back)
- `roll`: -30 to +30° (leg sideways)

**Example:** `10,0,-5,0` = Left leg 10° forward, Right leg 5° back

### 6. Knees (degrees)
```
left_bend,right_bend
```
- `0` = straight leg
- `45` = deep stance
- `90` = bent (sitting position)

**Example:** `15,20` = Left knee 15° bent, Right knee 20° bent

### 7. Stance
```
width,facing
```
- `width`: 20-80 cm between feet
- `facing`: 0-180° which direction facing

**Example:** `45,90` = 45cm stance width, facing 90° (opponent)

## Complete Examples

### Neutral Orthodox Stance
```
0,0.0,0,0.20,5,20,5.90,90.10,0,-5,0.15,15.40,90
```
Decoded:
- Lean: 0cm forward, 0cm sideways
- Rotation: 0° hip, 0° torso, 0° neck
- Shoulders: L(20° pitch, 5° roll) R(20° pitch, 5° roll) - guard position
- Elbows: L(90° bent) R(90° bent) - guard position
- Hips: L(10° pitch, 0° roll) R(-5° pitch, 0° roll) - orthodox stance
- Knees: L(15° bent) R(15° bent) - slight bend
- Stance: 40cm width, facing 90°

### Jab Position
```
8,0.8,12,0.-35,8,-30,10.15,90.12,0,-5,0.20,15.40,90
```
Decoded:
- Lean: 8cm forward, 0cm sideways - leaning into punch
- Rotation: 8° hip, 12° torso, 0° neck - body rotation
- Shoulders: L(-35° pitch, 8° roll) R(-30° pitch, 10° roll) - left arm extended forward
- Elbows: L(15° bent) R(90° bent) - left arm almost straight, right at guard
- Hips: L(12° pitch, 0° roll) R(-5° pitch, 0° roll) - front leg forward
- Knees: L(20° bent) R(15° bent) - slight more bend on front leg
- Stance: 40cm width, facing 90°

### Round Kick
```
0,-15.60,30,0.20,5,20,5.90,90.10,0,80,45.25,40.15,90
```
Decoded:
- Lean: 0cm forward, -15cm to left - leaning away from kick
- Rotation: 60° hip, 30° torso, 0° neck - heavy rotation
- Shoulders: L(20° pitch, 5° roll) R(20° pitch, 5° roll) - arms at guard
- Elbows: L(90° bent) R(90° bent) - guard position
- Hips: L(10° pitch, 0° roll) R(80° pitch, 45° roll) - right leg high and out
- Knees: L(25° bent) R(40° bent) - standing leg bent, kicking leg partially extended
- Stance: 15cm width (narrow - one leg up), facing 90°

## Full Scene Example

```
0,0.0,0,0.20,5,20,5.90,90.10,0,-5,0.15,15.40,90/0,0.0,0,0.20,5,20,5.90,90.-10,0,5,0.15,15.40,90/m
```

This represents:
- Fighter A (Red): Neutral orthodox stance
- Fighter B (Blue): Neutral southpaw stance (mirrored hip positions)
- Distance: `m` (Medium - 4 meters apart)

## Using MPN

### In Nim Code

```nim
import mannequin_notation

# Create a pose
let pose = createJabPose()

# Convert to MPN string
let mpn = poseToMPN(pose)
echo mpn  # Output: 8,0.8,12,0.-35,8,-30,10.15,90.12,0,-5,0.20,15.40,90

# Parse MPN back to pose
let parsed = mpnToPose(mpn)
echo "Hip rotation: ", parsed.hipRotation, "°"

# Convert from fight state
import fight_types
let fighter: Fighter = ...  # From simulation
let pose = fighterStateToMannequinPose(fighter)
```

### In Web Viewer

Open `fpn_3d_viewer.html` in a browser:
1. Paste MPN string in the text area
2. Click "Load Position"
3. See articulated 3D mannequins with exact joint angles
4. Click "Generate Random Pose" for random valid poses

### Distance Codes

In full scene format (`fighter_a/fighter_b/distance`):
- `c` = Contact (1.5m)
- `s` = Short (2.5m)
- `m` = Medium (4m)
- `l` = Long (6m)
- `v` = Very Long (8m)

## MPN vs FPN

| Aspect | MPN | FPN |
|--------|-----|-----|
| **Purpose** | Visualization | Game simulation |
| **Contains** | Joint angles only | Balance, fatigue, damage, limb states |
| **Derived** | From move execution | From game rules |
| **Usage** | 3D viewer, animation | Fight engine, AI |
| **Deterministic** | Same MPN = same visual | Same FPN = same game state |

**Relationship:** FPN describes game state → `fighterStateToMannequinPose()` → MPN describes visual pose

## Benefits

1. **Clean separation**: Visualization logic separate from game logic
2. **Deterministic**: Same MPN always produces identical visual pose
3. **Portable**: MPN strings work across any renderer (Three.js, Blender, Unity, etc.)
4. **Precise**: Direct joint angles instead of derived approximations
5. **Reusable**: Can visualize poses from any source (not just fight simulation)

## Next Steps

- **Animation**: Interpolate between MPN states for smooth transitions
- **Physics validation**: Check if MPN poses are biomechanically valid
- **Pose library**: Build collection of named poses for common moves
- **ML training**: Use MPN as input/output for pose prediction networks

---

**MPN = The physical consequence of martial arts moves, frozen in notation** 🥋
