# Dice Roll

A simple 3D dice-tossing game in Godot 4.7. Click and drag the die in the air to throw it — physics-based spin emerges from the off-center grab point, so it tumbles realistically instead of rolling in a fixed direction.

## Running

Open the project in Godot 4.7+ (Jolt Physics, Forward+ renderer) and press **F5**.

## Controls

| Action | Input |
|---|---|
| Grab and throw the die | Left-click + drag + release |
| Cancel a throw after pickup (die returns to where it was, no score) | Right-click |
| Respawn a fresh die at the start position | **R** |
| Roll in place (debug alternate, random rotation) | **Space** |

## Goal

Score points by rolling the die. Reach the target (default 20) and a "You win this round!" message fades in at the center of the screen. Score keeps accumulating past the target — press **R** to respawn the die without resetting.

## Project Layout

```
project.godot       — Godot project config (main scene, physics, rendering)
World.tscn          — main scene: 3D world (floor + walls), camera, lighting, HUD
die.tscn            — die prefab: RigidBody3D + GLB model + box collision
die.gd              — die physics: drag-toss, face detection via dot-product, roll_finished signal
world.gd            — HUD, target/win logic, die lifecycle, R-to-respawn
DiceTest1.glb       — die 3D model (imported)
icon.svg            — project icon
```

## How It Works

- **Drag-toss:** the die is frozen during drag and directly moved to follow the cursor on a horizontal plane at `drag_height`. The grab offset (cursor hit point − die center) is captured in 3D and used as the torque arm on release — `apply_impulse(impulse, grab_offset)` makes Godot compute both linear and angular momentum from the offset, so click near the top of the die → pitch/roll torque, click near an edge → bigger tumble.
- **Score detection:** when the die settles (RigidBody3D `sleeping = true`), each face's local normal is rotated into world space via `global_transform.basis` and the one with the highest dot product to `Vector3.UP` is the top face.
- **HUD:** `CanvasLayer` with a `PanelContainer` on each side (top-left score, top-right target) and a centered `Label` for the win message. The win message tweens `modulate:a` from 0 → 1 → 0 over 4.4s when the score first crosses the target.

## Tech

- **Godot 4.7** with Forward+ renderer
- **Jolt Physics 3D** for the rigid body
- **GDScript** for all gameplay code
