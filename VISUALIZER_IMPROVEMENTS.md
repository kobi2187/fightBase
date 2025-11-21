# Visualizer Improvements

## Changes Made

### 1. Added Nose to Mannequin (✓)
The 3D mannequins now have a **cone-shaped nose** pointing forward so you can clearly see which direction they're facing.

**Location:** `fpn_3d_viewer.html` lines 478-489

- Nose is a small cone (0.04m radius, 0.12m length)
- Points forward from the head
- Same color as the mannequin (red/blue)
- Has shadow casting for realism

### 2. Biomechanically Correct Stance Width (✓)

Stance width is now **calculated properly** based on leg geometry:

#### The Physics:
- When you spread your legs, they form triangles with your hip joints
- Leg length is constant (thigh: 45cm + shin: 45cm = 90cm total)
- Hip joints are 30cm apart
- **You cannot keep legs straight when spreading them wide!**

#### What's Calculated:
1. **Knee Bend**: Automatically calculated from stance width
   - Narrow stance (25cm): ~15° bend
   - Normal stance (40cm): ~17° bend
   - Wide stance (60cm): ~23° bend
   - Wrestling stance (70cm): ~27° base + 20° extra = ~47° total

2. **Hip Roll**: Legs angle outward from the hip
   - Calculated from leg geometry
   - Wider stance = more hip roll

#### Implementation:

**JavaScript (fpn_3d_viewer.html):**
- `calculateLegBiomechanics(stanceWidthCm)` function (lines 692-727)
- Calculates knee bend and hip roll based on triangle geometry
- Integrated into `poseMannequin()` function (lines 778-820)

**Nim (mannequin_notation.nim):**
- New `LegBiomechanics` type (lines 124-128)
- `calculateLegBiomechanics(stanceWidthM)` function (lines 130-165)
- Integrated into `fighterStateToMannequinPose()` (lines 209-247)

### 3. Key Formulas Used

```
horizontal_distance = |foot_offset - hip_joint_offset|
leg_angle = arctan(horizontal_distance / total_leg_length)
knee_bend = base_bend + (leg_angle × 1.2)
hip_roll = leg_angle × 0.6
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
