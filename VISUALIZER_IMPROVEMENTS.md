# Visualizer Improvements

## Changes Made

### 1. Added Nose to Mannequin (✓)
The 3D mannequins now have a **cone-shaped nose** pointing forward so you can clearly see which direction they're facing.

**Location:** `fpn_3d_viewer.html` lines 478-489

- Nose is a small cone (0.04m radius, 0.12m length)
- Points forward from the head
- Same color as the mannequin (red/blue)
- Has shadow casting for realism

### 2. Mannequins Face Each Other (✓)
- Fighter A (red) at x=-2 faces forward (rotation.y = 0)
- Fighter B (blue) at x=+2 faces backward (rotation.y = π)
- They now look at each other properly

### 3. Biomechanically Correct Hip Mechanics (✓)

**Major insight:** The hip is a **ball-and-socket joint** (acetabulum + femur head) that **rotates**, not a sliding joint that repositions!

#### Hip Joint Anatomy:
- **Ball-and-socket joint** at the pelvis (femur head in acetabulum)
- Hip socket position is **FIXED** at ±15cm from centerline (30cm total hip width)
- The joint **rotates in 3D**, it doesn't slide horizontally

#### Three Types of Hip Movement:
1. **Hip Abduction (Z-axis)**: Spreading legs sideways for stance width
   - Rotates leg outward at the socket
   - Used for: wide stances, horse stance, sumo squat
2. **Hip Pitch (X-axis)**: Lifting leg forward/backward
   - Rotates leg up/down
   - Used for: front kicks, back kicks, knee strikes
3. **Hip Rotation (Y-axis)**: Rotating leg inward/outward
   - Twists the femur in the socket
   - Used for: round kicks (leg rotates inward as it lifts)

#### Stance Width Biomechanics:
- **Input**: Desired stance width (e.g., 60cm between feet)
- **Fixed**: Hip sockets are 30cm apart (anatomical constant)
- **Calculate**: Hip abduction angle needed to achieve desired foot separation
  ```
  additional_spread = stance_width - hip_width
  abduction_angle = arctan((additional_spread/2) / leg_length)
  ```
- **Result**: Hip abduction = 8° for narrow stance, 18° for wide stance

#### Knee Bend Compensation:
As hips abduct (legs spread), knees must bend more to keep feet on ground:
- Base knee bend: 15° (even in neutral stance)
- Additional bend: abduction_angle × 1.5
- Wrestling stance adds extra 20° for low posture
- Maximum: 60° (realistic squat limit)

#### Implementation:

**JavaScript (fpn_3d_viewer.html):**
- `calculateLegBiomechanics(stanceWidthCm)` - calculates abduction angle and knee bend
- `poseMannequin()` - applies hip abduction (Z-axis) for stance, pitch/roll for kicks
- Hip socket stays at fixed position (±15cm), only rotations change

**Nim (mannequin_notation.nim):**
- `LegBiomechanics` type with `hipAbduction`, `kneeBend`, `legAngle`
- `calculateLegBiomechanics(stanceWidthM)` - same logic as JavaScript
- Separates stance abduction from kick pitch/roll

### 4. Key Formulas

#### Stance Width → Hip Abduction:
```
additional_spread = stance_width - 30cm
abduction_angle = arctan((additional_spread / 2) / leg_length)
knee_bend = 15° + (abduction_angle × 1.5)
```

#### Round Kick (example):
```
hip_pitch = 90° (lift leg to horizontal)
hip_rotation = 45° (rotate leg inward)
knee_bend = 20° (partially extended)
```

## Testing

### To Test the Visualizer:

1. **Open the HTML file:**
   ```bash
   open fpn_3d_viewer.html
   # or
   firefox fpn_3d_viewer.html
   ```

2. **Check the nose:**
   - Both mannequins should have a small cone pointing forward
   - The nose shows which way they're facing

3. **Test stance width biomechanics:**
   - Adjust the "Stance Width" slider (20-80cm)
   - Watch the knees automatically bend more as stance widens
   - Watch the hips roll outward as legs spread
   - Try the preset poses (Neutral, Jab, Guard, Kick)

4. **Try these scenarios:**
   - **Narrow stance (25cm)**: Legs nearly straight, minimal knee bend
   - **Normal stance (40cm)**: Natural fighting position
   - **Wide stance (70cm)**: Deep knee bend, legs angled out
   - **Kicks**: Explicit knee/hip angles override automatic calculation

## What This Fixes

### Before:
- ❌ No way to see mannequin orientation
- ❌ Stance width was just leg position (unrealistic)
- ❌ Knee bend was fixed per stance type
- ❌ Legs stayed straight even in wide stances

### After:
- ✅ Nose shows orientation clearly
- ✅ Stance width affects biomechanics realistically
- ✅ Knee bend calculated from geometry
- ✅ Hip roll calculated from leg angles
- ✅ Wider stance = deeper squat (as in real life!)

## Technical Details

### Assumptions:
- Hip width: 30cm (average adult)
- Thigh length: 45cm
- Shin length: 45cm
- Base knee bend: 15° (natural fighting stance)
- Maximum knee bend: 45° (realistic squat limit)
- Maximum hip roll: 25° (realistic abduction limit)

### Why This Matters:

This is important for the martial arts engine because:

1. **Striking Distance**: Stance width affects reach and balance
2. **Weak Points**: Wider stance exposes inner thighs more
3. **Mobility**: Deep knee bend in wide stance limits movement speed
4. **Recovery Time**: Moving from wide to narrow stance takes more frames
5. **Vulnerability**: Cannot move quickly from deep squat position

## Related Files

- `fpn_3d_viewer.html` - Web visualizer with nose and biomechanics
- `src/mannequin_notation.nim` - Nim implementation of same logic
- `src/fight_types.nim` - Core types (unchanged)
- `src/physics.nim` - Physics validation (uses biomech state)

## Next Steps

The visualizer now correctly shows:
- ✅ Orientation (nose)
- ✅ Stance biomechanics (calculated angles)
- 🔲 Striking distance visualization (TODO)
- 🔲 Weak point exposure zones (TODO)
- 🔲 Balance/momentum indicators (TODO)

These features will be added next to make the visualizer useful for understanding fight dynamics!
