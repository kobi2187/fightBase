# MPN (Mannequin Position Notation), version 2

MPN records the physical pose of a fighter as joint angles, for drawing. It holds no
game state: balance, damage and fatigue belong to FPN and the solver.

`fpn_3d_viewer.html` reads and writes it (Notation tab), and so does
`src/mannequin_notation.nim` (`poseToMPN`, `mpnToPose`).

## Format

One fighter:

```
v2:lean.rotation.shoulders.elbows.hips.knees.stance
```

A scene:

```
fighterA/fighterB/distance
```

Groups are separated by `.` and values inside a group by `,`. Every value is an
integer.

| Group | Values | Meaning |
|---|---|---|
| lean | `fwd,side` | degrees; `fwd` > 0 leans toward the opponent, `side` > 0 leans to the fighter's left |
| rotation | `hip,torso,neck` | degrees about the vertical; > 0 turns the front toward the fighter's left (the right side comes forward). `torso` is relative to the hips. `neck` is an offset on top of looking at the opponent. |
| shoulders | `lFlex,lAbd,lRot,rFlex,rAbd,rRot` | degrees; flexion raises the arm forward, abduction raises it sideways, internal rotation turns its front toward the body |
| elbows | `l,r` | bend in degrees, 0 = straight |
| hips | `lFlex,lAbd,lRot,rFlex,rAbd,rRot` | degrees; same conventions as the shoulders, for the legs |
| knees | `l,r` | bend in degrees, 0 = straight |
| stance | `width` | sideways distance between the feet in cm |

Flexion is positive everywhere: the arm hanging at the side is 0, and pointing
straight ahead is about 90. The mannequin is about 1.75 m tall. When a pose is loaded,
its lowest sole is placed on the floor.

Distance codes are the space between the two fighters' hips:

| Code | Range | Metres |
|---|---|---|
| `c` | clinch | 0.50 |
| `s` | close (elbows, knees) | 0.72 |
| `m` | punching | 0.98 |
| `l` | kicking | 1.12 |
| `v` | out of range | 2.10 |

## Examples

These were exported from the viewer. They are also the reference poses in
`mannequin_notation.nim`.

Orthodox guard: bladed hips, hands at the chin, lead leg forward.

```
v2:6,0.-35,-8,0.45,14,30,38,16,38.118,132.28,17,-17,7,18,-20.34,35.30
```

Jab at impact, at punching range. The hips are bladed by 57° in total, so the lead
arm is flexed 103° and abducted 49°: it swings back across to the centre line, where
the nose is.

```
v2:0,0.-45,-12,0.103,49,5,38,16,38.18,132.24,20,-27,3,19,-10.39,26.30
```

Rear round kick at impact, at kicking range. The hips are turned over (102°), the right
leg is abducted 108° and turned in, the knee is almost straight, and the body leans
away.

```
v2:-6,24.102,18,0.45,14,30,38,16,38.118,132.29,-9,7,12,108,35.42,6.30
```

Scene, a jab against a guard at punching range:

```
v2:0,0.-45,-12,0.103,49,5,38,16,38.18,132.24,20,-27,3,19,-10.39,26.30/v2:6,0.-35,-8,0.45,14,30,38,16,38.118,132.28,17,-17,7,18,-20.34,35.30/m
```

## The viewer

`fpn_3d_viewer.html` animates sequences of the solver's actions, such as
`Jab > Cross > Hook` or `Jab / Slip` for a simultaneous beat. During playback, leg angles
come from foot-planting IK, and strikes are aimed at the opponent's target points
(nose, jaw, temple, liver, groin, lead thigh or knee, and so on). The Notation tab
always shows the MPN of the frame on screen, with its solved angles.

URL parameters:

- `?seq=Jab>Cross&dist=m`: a sequence and a distance.
- `&b=southpaw`: a southpaw stance for fighter B (`&a=southpaw` for A).
- `&mpn=<scene>`: start from a static scene.
- `&autoplay=0`: load without playing.

## Legacy format

Strings without the `v2:` prefix are read in the original format:

- Lean is in cm and is converted at 60 cm of lever; a positive side value meant
  leaning right.
- Shoulder pitch is negative for forward.
- Shoulders and hips may have 4 values (pitch and roll per side) or 6.
- The stance group is `width_cm,facing`.
