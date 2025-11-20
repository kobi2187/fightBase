# 3D Mannequin Visualization

Visualize FPN fight positions as 3D articulated mannequins.

## Option 1: Web Viewer (Easiest - No Installation!)

**Just open in browser:**
```bash
open fpn_3d_viewer.html
# or
firefox fpn_3d_viewer.html
```

### Features:
- ✅ **3D mannequin models** with articulated joints
- ✅ **Interactive rotation** - drag to orbit camera
- ✅ **Zoom** - scroll wheel
- ✅ **Real-time FPN parsing** - paste and see instantly
- ✅ **4 built-in examples**
- ✅ **Color-coded** - Red (Fighter A), Blue (Fighter B)
- ✅ **Damage visualization** - darker/transparent when damaged
- ✅ **Works offline** - no server needed

### Controls:
- **Left drag** = Rotate camera
- **Scroll** = Zoom in/out
- **Reset View button** = Return to default camera

### Visual Elements:
- **Head** - Sphere (balance affects lean)
- **Torso/Hips** - Box geometry (shows rotation from biomech)
- **Arms/Legs** - Cylinders (extended = punching/kicking)
- **Damage** - Darker color, transparent (>50% damage)
- **Balance** - Mannequin leans when unbalanced
- **Stance** - Leg spread varies (wide, wrestling, etc)

---

## Option 2: Blender Renders (Photorealistic)

**For high-quality images:**

### Requirements:
- Blender 2.8+ installed

### Usage:
```bash
blender --background --python blender_render_fpn.py -- \
  "o.95.15.0.3,5.10,15,55,0,0.----/s.90.20.5.-1,0.-5,-10,45,0,0.----/m/A/5" \
  output.png
```

### Features:
- ✅ Photorealistic rendering with Cycles engine
- ✅ 1920x1080 resolution
- ✅ Professional lighting setup
- ✅ Shadow and ambient occlusion
- ✅ Save as PNG image

### Customization:
Edit `blender_render_fpn.py` to adjust:
- `scene.cycles.samples = 128` - Higher = better quality, slower
- `scene.render.resolution_x/y` - Image size
- Camera position/angle
- Lighting setup
- Material properties

### Advanced: Use Custom Rigged Model

Replace the `create_simple_mannequin()` function to:
1. Import your own rigged character (.fbx, .blend, etc)
2. Map FPN data to bone rotations
3. Support IK (Inverse Kinematics) for realistic poses

Example with Armature:
```python
def pose_armature(armature, fighter_data):
    # Get pose bones
    pose_bones = armature.pose.bones

    # Hip rotation
    pose_bones['Hips'].rotation_euler[2] = math.radians(
        fighter_data['biomech']['hip_rot']
    )

    # Torso rotation
    pose_bones['Spine'].rotation_euler[2] = math.radians(
        fighter_data['biomech']['torso_rot']
    )

    # Arms extended
    if fighter_data['limbs'][0] in ['E', 'B']:  # Left arm
        pose_bones['UpperArm.L'].rotation_euler[1] = math.radians(45)

    # And so on...
```

---

## Comparison: Web vs Blender

| Feature | Web Viewer | Blender |
|---------|-----------|---------|
| **Setup** | None (just open HTML) | Install Blender |
| **Speed** | Instant | ~10 seconds per render |
| **Quality** | Good (real-time 3D) | Photorealistic |
| **Interactive** | Yes (rotate, zoom) | No (static image) |
| **Use Case** | Quick inspection | Publication quality |
| **Customization** | Limited | Full control |

---

## Tips for Best Visualization

### 1. Understand the Pose Data

FPN encodes:
- **Balance** → Mannequin lean angle
- **Hip rotation** → Hips object rotation
- **Torso rotation** → Torso object rotation
- **Limb status** → Arm/leg extension
  - `-` = Neutral guard position
  - `E` = Extended (striking)
  - `X` = Damaged (darker material)
  - `B` = Both (damaged + extended)

### 2. Distance Visualization

Distance affects mannequin positioning:
- `c` (Contact) = 1.5m apart
- `s` (Short) = 2.5m apart
- `m` (Medium) = 4m apart
- `l` (Long) = 6m apart
- `v` (Very Long) = 8m apart

### 3. Creating Animations

To animate a fight sequence:

**Web Viewer:**
- Load FPN states sequentially with delays
- Use Three.js tweening for smooth transitions

**Blender:**
- Render each FPN as separate frame
- Combine frames into video with ffmpeg:
```bash
ffmpeg -framerate 30 -i frame_%03d.png -c:v libx264 fight.mp4
```

### 4. Custom Mannequin Models

For better visuals, use:
- **Mixamo** - Free rigged character models
- **Ready Player Me** - Customizable avatars
- **Blender built-in** - Human Base Mesh addon
- **MakeHuman** - Parametric human generator

Import into Blender, then modify script to map FPN → bone rotations.

---

## Example FPN Strings to Try

### Fresh fighters (neutral)
```
o.100.0.0.0,0.0,0,50,0,0.----/s.100.0.0.0,0.0,0,50,0,0.----/m/A/0
```

### After exchange (damaged, fatigued, arms extended)
```
o.85.25.5.2,10.15,20,55,0,0.--E-/s.80.30.8.-1,5.-10,-15,45,0,0.-E--/s/B/5
```

### Close range combat (unbalanced, recovering)
```
o.70.40.12.3,15.25,30,60,0,0.----/s.65.45.15.1,8.-15,-25,40,1,2.----/c/A/8
```

### One fighter badly damaged (50% damage, low balance)
```
o.90.20.2.1,5.10,15,55,0,0.----/s.50.35.35.-2,0.-20,-30,35,1,4.X-E-/s/A/12
```

---

## Troubleshooting

### Web Viewer

**Problem:** Black screen
- **Solution:** Check browser console (F12) for errors
- **Solution:** Try different browser (Chrome/Firefox recommended)

**Problem:** Mannequins not posing correctly
- **Solution:** Verify FPN format is valid
- **Solution:** Check browser console for parsing errors

### Blender

**Problem:** "blender: command not found"
- **Solution:** Add Blender to PATH or use full path:
  ```bash
  /Applications/Blender.app/Contents/MacOS/Blender --background --python ...
  ```

**Problem:** Render takes too long
- **Solution:** Reduce samples: `scene.cycles.samples = 32`
- **Solution:** Lower resolution
- **Solution:** Use EEVEE engine instead of Cycles

**Problem:** Mannequins look weird
- **Solution:** Check FPN parsing (print debug info)
- **Solution:** Verify rotation values are in correct units (radians)

---

## Next Steps

### Interactive Fight Viewer
Combine with `visualize.nim` to:
1. Run simulation
2. Generate FPN for each move
3. Display in 3D viewer with animation
4. Watch fights unfold in 3D!

### VR/AR Support
The Three.js viewer can be extended with WebXR for:
- VR headset viewing
- AR on mobile devices
- Immersive fight analysis

### Machine Learning Integration
- Train neural network to predict next pose
- Generate realistic transition animations
- Detect biomechanically impossible poses

---

**Now you can SEE the fight positions as articulated 3D mannequins!** 🥋
