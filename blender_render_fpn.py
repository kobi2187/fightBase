"""
Blender script to render FPN positions as photorealistic images
Usage: blender --background --python blender_render_fpn.py -- <FPN_string> <output.png>

Requirements:
- Blender 2.8+ installed
- Mannequin model (can use Blender's built-in rig or import one)

This script:
1. Parses FPN notation
2. Poses two mannequin models
3. Renders a high-quality image
"""

import bpy
import math
import sys

def parse_fpn(fpn_string):
    """Parse FPN notation into fight state"""
    parts = fpn_string.strip().split('/')
    if len(parts) != 5:
        raise ValueError(f"Invalid FPN format: {fpn_string}")

    def parse_fighter(fpn_fighter):
        parts = fpn_fighter.split('.')
        if len(parts) != 7:
            raise ValueError(f"Invalid fighter format: {fpn_fighter}")

        mom = parts[4].split(',')
        bio = parts[5].split(',')

        return {
            'stance': parts[0],
            'balance': int(parts[1]) / 100.0,
            'fatigue': int(parts[2]) / 100.0,
            'damage': int(parts[3]) / 100.0,
            'momentum': {
                'linear': int(mom[0]) / 10.0,
                'rotational': int(mom[1])
            },
            'biomech': {
                'hip_rot': int(bio[0]),
                'torso_rot': int(bio[1]),
                'weight': int(bio[2]) / 100.0,
                'recovering': bio[3] == '1',
                'frames': int(bio[4])
            },
            'limbs': parts[6]
        }

    return {
        'fighter_a': parse_fighter(parts[0]),
        'fighter_b': parse_fighter(parts[1]),
        'distance': parts[2],
        'turn': parts[3],
        'move_count': int(parts[4])
    }

def clear_scene():
    """Clear default Blender scene"""
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete()

def create_simple_mannequin(name, color):
    """Create a simple mannequin from primitives"""
    mannequin = bpy.data.objects.new(name, None)
    mannequin.empty_display_type = 'PLAIN_AXES'
    bpy.context.collection.objects.link(mannequin)

    # Material
    mat = bpy.data.materials.new(name=f"{name}_material")
    mat.use_nodes = True
    mat.node_tree.nodes["Principled BSDF"].inputs[0].default_value = color

    # Head
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.2, location=(0, 0, 3.6))
    head = bpy.context.active_object
    head.name = f"{name}_head"
    head.parent = mannequin
    head.data.materials.append(mat)

    # Torso
    bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, 2.9))
    torso = bpy.context.active_object
    torso.name = f"{name}_torso"
    torso.scale = (0.5, 0.3, 0.8)
    torso.parent = mannequin
    torso.data.materials.append(mat)

    # Hips
    bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, 2.35))
    hips = bpy.context.active_object
    hips.name = f"{name}_hips"
    hips.scale = (0.45, 0.3, 0.3)
    hips.parent = mannequin
    hips.data.materials.append(mat)

    # Arms (simplified)
    for side, sign in [('left', -1), ('right', 1)]:
        # Upper arm
        bpy.ops.mesh.primitive_cylinder_add(
            radius=0.06, depth=0.4,
            location=(sign * 0.35, 0, 3.0)
        )
        upper_arm = bpy.context.active_object
        upper_arm.name = f"{name}_{side}_upper_arm"
        upper_arm.parent = mannequin
        upper_arm.data.materials.append(mat)

        # Lower arm
        bpy.ops.mesh.primitive_cylinder_add(
            radius=0.05, depth=0.4,
            location=(sign * 0.35, 0, 2.6)
        )
        lower_arm = bpy.context.active_object
        lower_arm.name = f"{name}_{side}_lower_arm"
        lower_arm.parent = mannequin
        lower_arm.data.materials.append(mat)

        # Hand
        bpy.ops.mesh.primitive_uv_sphere_add(
            radius=0.07,
            location=(sign * 0.35, 0, 2.4)
        )
        hand = bpy.context.active_object
        hand.name = f"{name}_{side}_hand"
        hand.parent = mannequin
        hand.data.materials.append(mat)

    # Legs
    for side, sign in [('left', -1), ('right', 1)]:
        # Upper leg
        bpy.ops.mesh.primitive_cylinder_add(
            radius=0.08, depth=0.6,
            location=(sign * 0.15, 0, 1.85)
        )
        upper_leg = bpy.context.active_object
        upper_leg.name = f"{name}_{side}_upper_leg"
        upper_leg.parent = mannequin
        upper_leg.data.materials.append(mat)

        # Lower leg
        bpy.ops.mesh.primitive_cylinder_add(
            radius=0.06, depth=0.6,
            location=(sign * 0.15, 0, 1.25)
        )
        lower_leg = bpy.context.active_object
        lower_leg.name = f"{name}_{side}_lower_leg"
        lower_leg.parent = mannequin
        lower_leg.data.materials.append(mat)

        # Foot
        bpy.ops.mesh.primitive_cube_add(
            size=1,
            location=(sign * 0.15, 0.08, 0.05)
        )
        foot = bpy.context.active_object
        foot.name = f"{name}_{side}_foot"
        foot.scale = (0.12, 0.25, 0.1)
        foot.parent = mannequin
        foot.data.materials.append(mat)

    return mannequin

def pose_mannequin(mannequin, fighter_data):
    """Apply fighter state to mannequin pose"""
    name = mannequin.name

    # Balance affects lean
    lean = (1 - fighter_data['balance']) * 0.2
    mannequin.rotation_euler[1] = lean  # Y-axis lean

    # Hip rotation
    hips = bpy.data.objects.get(f"{name}_hips")
    if hips:
        hips.rotation_euler[2] = math.radians(fighter_data['biomech']['hip_rot'])

    # Torso rotation
    torso = bpy.data.objects.get(f"{name}_torso")
    if torso:
        torso.rotation_euler[2] = math.radians(fighter_data['biomech']['torso_rot'])

    # Arm positions based on extended state
    limbs = fighter_data['limbs']

    # Left arm
    left_extended = limbs[0] in ['E', 'B']
    left_upper = bpy.data.objects.get(f"{name}_left_upper_arm")
    if left_upper:
        left_upper.rotation_euler[1] = math.pi / 3 if left_extended else math.pi / 6

    # Right arm
    right_extended = limbs[1] in ['E', 'B']
    right_upper = bpy.data.objects.get(f"{name}_right_upper_arm")
    if right_upper:
        right_upper.rotation_euler[1] = -math.pi / 3 if right_extended else -math.pi / 6

    # Adjust material based on damage
    damage = fighter_data['damage']
    for obj in bpy.data.objects:
        if obj.name.startswith(name) and obj.type == 'MESH':
            if obj.data.materials:
                mat = obj.data.materials[0]
                # Darken color with damage
                color = mat.node_tree.nodes["Principled BSDF"].inputs[0].default_value
                factor = 1 - (damage * 0.5)
                mat.node_tree.nodes["Principled BSDF"].inputs[0].default_value = (
                    color[0] * factor,
                    color[1] * factor,
                    color[2] * factor,
                    1.0
                )

def setup_scene(state):
    """Setup complete scene with fighters, lights, camera"""
    clear_scene()

    # Distance mapping
    distance_map = {'c': 1.5, 's': 2.5, 'm': 4, 'l': 6, 'v': 8}
    dist = distance_map.get(state['distance'], 4)

    # Create mannequins
    fighter_a = create_simple_mannequin("FighterA", (1.0, 0.3, 0.3, 1.0))  # Red
    fighter_b = create_simple_mannequin("FighterB", (0.3, 0.3, 1.0, 1.0))  # Blue

    # Position fighters
    fighter_a.location = (-dist / 2, 0, 0)
    fighter_b.location = (dist / 2, 0, 0)

    fighter_a.rotation_euler[2] = math.pi / 2
    fighter_b.rotation_euler[2] = -math.pi / 2

    # Pose them
    pose_mannequin(fighter_a, state['fighter_a'])
    pose_mannequin(fighter_b, state['fighter_b'])

    # Ground plane
    bpy.ops.mesh.primitive_plane_add(size=20, location=(0, 0, 0))
    ground = bpy.context.active_object
    ground.name = "Ground"

    ground_mat = bpy.data.materials.new(name="GroundMaterial")
    ground_mat.use_nodes = True
    ground_mat.node_tree.nodes["Principled BSDF"].inputs[0].default_value = (0.3, 0.3, 0.3, 1.0)
    ground.data.materials.append(ground_mat)

    # Lighting
    bpy.ops.object.light_add(type='SUN', location=(5, -5, 10))
    sun = bpy.context.active_object
    sun.data.energy = 3
    sun.rotation_euler = (math.radians(45), 0, math.radians(45))

    bpy.ops.object.light_add(type='AREA', location=(-5, 5, 5))
    fill_light = bpy.context.active_object
    fill_light.data.energy = 200
    fill_light.data.size = 5

    # Camera
    bpy.ops.object.camera_add(location=(0, -10, 5))
    camera = bpy.context.active_object
    camera.rotation_euler = (math.radians(60), 0, 0)

    bpy.context.scene.camera = camera

    return fighter_a, fighter_b

def render_scene(output_path):
    """Render the scene to an image"""
    scene = bpy.context.scene

    # Render settings
    scene.render.engine = 'CYCLES'
    scene.cycles.samples = 128  # Lower for speed, increase for quality
    scene.render.resolution_x = 1920
    scene.render.resolution_y = 1080
    scene.render.filepath = output_path

    # Render
    bpy.ops.render.render(write_still=True)
    print(f"✓ Rendered: {output_path}")

def main():
    # Get arguments after --
    try:
        argv = sys.argv
        argv = argv[argv.index("--") + 1:]
    except ValueError:
        print("Usage: blender --background --python blender_render_fpn.py -- <FPN_string> <output.png>")
        print("\nExample:")
        print('  blender --background --python blender_render_fpn.py -- "o.95.15.0.3,5.10,15,55,0,0.----/s.90.20.5.-1,0.-5,-10,45,0,0.----/m/A/5" output.png')
        sys.exit(1)

    if len(argv) < 2:
        print("Error: Missing arguments")
        print("Usage: <FPN_string> <output.png>")
        sys.exit(1)

    fpn_string = argv[0]
    output_path = argv[1]

    print(f"Parsing FPN: {fpn_string}")
    state = parse_fpn(fpn_string)

    print(f"Setting up scene...")
    setup_scene(state)

    print(f"Rendering to: {output_path}")
    render_scene(output_path)

    print("Done!")

if __name__ == "__main__":
    main()
