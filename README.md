# Dice Roll

A simple 3D dice-tossing game in Godot 4.7. Six dice start in an inventory strip at the bottom of the screen — click and drag from a slot to throw the die into the arena, where it bounces, tumbles, and scores off whatever face ends up pointing up. Dice that land in the arena stay there and physically collide with each other.

## Running

Open the project in Godot 4.7+ (Jolt Physics, Forward+ renderer) and press **F5**. The main menu loads first; press **PLAY** (or Space / Enter) to enter the game.

## Controls

| Action | Input |
|---|---|
| Pick up a die from an inventory slot and toss it into the arena | Left-click + drag from a slot |
| Pick up and re-toss a die already in the arena | Left-click + drag on the die |
| Cancel a throw mid-drag (arena: die returns to rest pose, inventory: slot is refunded, die disappears). Once the left mouse is released, the throw is committed — right-click does nothing post-release | Right-click |
| Refill the inventory (arena dice + score are kept) | **R** |
| Roll in place (debug alternate, random rotation) | **Space** |

### Main Menu

| Action | Input |
|---|---|
| Start the game | **PLAY** button, **Space**, or **Enter** |
| Quit | **QUIT** button |

## Goal

Score points by rolling the dice. Reach the target (default 20) and a "You win this round!" message fades in at the center of the screen. Score keeps accumulating past the target — press **R** to refill the inventory without resetting the score or the dice already in play.

## Main Menu

A placeholder menu loads at startup with title, subtitle, a dashed `[ custom art slot ]` zone for art TBD, and PLAY / QUIT buttons. Space / Enter also starts the game from the menu. The whole layout is built programmatically in `main_menu.gd._ready()` — same pattern as the in-game HUD — so it's easy to iterate on while the design is in flux. When custom art arrives, swap the dashed-border placeholder for the new art node and tweak sizes in `ART_PLACEHOLDER_SIZE`.

## Project Layout

```
project.godot       — Godot project config (main scene, physics, rendering)
main_menu.tscn      — main menu scene (placeholder UI; loaded at startup)
main_menu.gd        — menu script: builds title, art slot, PLAY/QUIT buttons
World.tscn          — game scene: 3D world (floor + walls), camera, lighting, HUD
die.tscn            — die prefab: RigidBody3D + GLB model + box collision
die.gd              — die physics: drag-toss from arena OR inventory, face
                      detection via dot-product, roll_finished signal,
                      inventory_drag_canceled signal (right-click refund)
world.gd            — HUD, inventory strip (6 slots), audio subsystem,
                      target/win logic, die lifecycle, R-to-refill-inventory
sounds/             — placeholder SFX (synthesized WAVs, swappable):
                      select.wav (UI click), impact.wav (die contact thud),
                      score.wav (settle chime)
DiceTest1.glb       — die 3D model (imported)
icon.svg            — project icon
```

## How It Works

- **Inventory drag:** the bottom-center strip holds six numbered slots, each containing a die. Click and hold on a slot, drag across the arena to aim, and release to throw. Spawning uses the same cursor-projection math as an arena drag — the die appears at drag height (5.0) directly under your cursor on release-mouse-down, then tracks your cursor as you aim. The slot becomes empty ("used") on press; right-click while left is still held refunds the slot and the die disappears without scoring. Once left is released the throw is committed — whatever the die lands on is what you get. Release uses a dedicated toss-feel path — see the next bullet.
- **Inventory toss feel:** inventory-spawned dice have `_grab_offset = Vector3.ZERO` because the cursor can't grab off-axis from a 2D button. That means `apply_impulse(impulse, offset)` produces zero torque (r × F = 0 × F = 0) and the die would just slide straight down. Instead, on release we set `linear_velocity = drag_velocity + upward lift` and spin around the axis perpendicular to drag in the XZ plane (the natural end-over-end tumble axis for a horizontal throw). Spin magnitude scales with drag speed and is capped so whip-fast throws don't go orbital. Drop-in-place (no real drag) still gets the lift + a default forward flip around +X so the die visibly tumbles. All deterministic — no randomness.
- **Arena drag-throw:** the die is frozen during drag and directly moved to follow the cursor on a horizontal plane at `drag_height`. The grab offset (cursor hit point − die center) is captured in 3D and used as the torque arm on release — `apply_impulse(impulse, grab_offset)` makes Godot compute both linear and angular momentum from the offset, so click near the top of the die → pitch/roll torque, click near an edge → bigger tumble.
- **Drop-in-place (arena):** if the cursor barely moved between grab and release (drag-end speed < `min_release_speed`, default 50 u/s), the toss falls back to a small downward impulse (`min_release_force`, default 5 N·s) applied at the grab point. A top-corner grab flips the die; a dead-center grab drops flat. Inventory throws don't hit this path — they have their own toss-feel handler above. Fully deterministic — no randomness.
- **Arena drag-throw:** the die is frozen during drag and directly moved to follow the cursor on a horizontal plane at `drag_height`. The grab offset (cursor hit point − die center) is captured in 3D and used as the torque arm on release — `apply_impulse(impulse, grab_offset)` makes Godot compute both linear and angular momentum from the offset, so click near the top of the die → pitch/roll torque, click near an edge → bigger tumble.
- **Drop-in-place:** if the cursor barely moved between grab and release (drag-end speed < `min_release_speed`, default 50 u/s), the toss falls back to a small downward impulse (`min_release_force`, default 5 N·s). For arena throws, applied at the grab point — a top-corner grab flips the die. For inventory throws, `_grab_offset` is zero so the impulse is purely linear; tumbling still happens from the floor impact when the die falls from `drag_height`. Fully deterministic — no randomness.
- **Cross-die collision:** all dice share the default collision layer / mask (layer 1, mask 1), so dice that land in the arena physically bounce off each other on impact. No special collision setup required.
- **Bounce:** the die has a `physics_material_override` (bounce 0.3, friction 0.5) so impacts feel alive instead of landing dead. Tune in the inspector on `die.tscn`.
- **Score detection:** when the die settles (RigidBody3D `sleeping = true`), each face's local normal is rotated into world space via `global_transform.basis` and the one with the highest dot product to `Vector3.UP` is the top face. Each die's score is additive into the total — and re-throwing the same die produces another score (each toss arms the signal afresh).
- **HUD:** `CanvasLayer` with a `PanelContainer` (top-left score + last roll), a target panel (top-right), a controls legend (top-left under the score), a centered `Label` for the win message, and the inventory strip (bottom-center, six numbered slot buttons). The win message tweens `modulate:a` from 0 → 1 → 0 over 4.4s when the score first crosses the target.
- **Audio:** three non-positional `AudioStreamPlayer`s (not `AudioStreamPlayer3D` — the camera is fixed, so spatialization doesn't add anything). Streams are loaded from `res://sounds/{select,impact,score}.wav` at runtime via `load()`, so a missing wav degrades to a no-op rather than crashing. Trigger points:
  - **select** — fires on `button_down` of any inventory slot. Sharp 1500 Hz click with a 6 ms exp decay.
  - **impact** — connected to each die's `body_entered` signal. Die.tscn sets `contact_monitor = true` + `max_contacts_reported = 4`. Low thud (120/250/80 Hz with brown-noise overlay) with a 70 ms exp decay. Globally throttled to one sound per 70 ms (`IMPACT_COOLDOWN_MS`) so a chaotic roll doesn't drown the score chime — two dice colliding at the same instant register as one impact (single physical event).
  - **score** — fires from `_on_die_rolled` (one chime per settled die). 880/1320/1760 Hz triad (A5 + E6 + A6) bell-like decay. Multiple dice settling in the same frame layer their chimes; the additive overlap sounds pleasing rather than clipping.

## Tech

- **Godot 4.7** with Forward+ renderer
- **Jolt Physics 3D** for the rigid body
- **GDScript** for all gameplay code
