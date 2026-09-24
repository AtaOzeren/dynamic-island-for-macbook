# Island Pet

This document specifies the pet: the small pixel dog that can live on the compact island. It covers where the pet stands and how it shares the pill with activity icons, the art and the animation it is drawn with, the routine it performs, and what it costs. It is a design specification — the code follows it, not the other way round.

## What it is

A Shiba Inu puppy, 32 × 24 pixels of pixel art drawn in 16 × 12 points, that lives on the leading (left) flank of the compact island. It walks, sits, blinks, pants and wags its tail. It is switched on in Settings › Pet and is **off by default**: the idle island draws nothing that moves (`02-performance-contract.md`), and a pet walking across it is a change the user opts into rather than one made for them.

KerNotch ships one pet in one coat. `IslandPet` carries the sprite sheet a pet is drawn from, so a second pet or a second coat is a second sheet, not a second code path.

## Where the pet stands

The pet lives in the places the activities' icons leave free on the leading flank. The icons keep every rule from `05-activity-model.md` — the pet never takes a place an icon needs, and never moves an icon to the other side of the notch.

| Leading icons | Stage | What the pet does |
|---|---|---|
| None | `roaming` | Walks the whole flank — both places and the gap between them — and sits at points along it |
| One | `resting` | Runs to the outer place, the one the icon does not use, and sits there |
| Two | `away` | Runs out past the island's outer edge and is no longer drawn |

While a pet is switched on, the leading flank is always drawn two places wide (`CompactSlotLayout.leadingPlaceCount`). The icons take the flank from the notch side and the pet lives in what they leave, so an icon arriving beside the pet takes the pet's place rather than widening the island: the pill keeps one width while icons come and go beside the pet. Without a pet the flank is exactly as wide as its icons, as before.

Everything that sizes the compact pill reads the same answer — the icons, the black surface behind them, the mask that clips them, the offset onto the notch, the attention glow, and the hover target in `PresentationController`. The island reaches all of them through `compactSlotLayout(for:hiding:housing:)`, which takes the pet without a default; the secondary islands pass `nil` for it explicitly.

The island is filled in before its panel is first ordered in, so with the pet on it appears at its resting width rather than growing to it on a spring at every launch.

The pet is drawn behind the icons, so an icon growing into the spot the pet is leaving is drawn over it. The view that draws the pet reaches from the pill's outer edge to the notch-side end of the flank and clips at that edge: leaving, the pet walks out through the pill's margin and disappears at its side.

The pet lives on the primary island only. With "All displays", the other islands draw the activities but no pet: a second dog on another screen would be a copy, not company.

## The art

`PetSpriteSheet.shiba` holds every frame as rows of palette keys, drawn facing right; facing left is the same art mirrored. The art is drawn two image pixels to a point (`pixelsPerPoint`), which on a Retina panel is one image pixel per device pixel: as dense as the screen allows, and shown at exactly its own size, so it is never resampled. On a 1x display it is halved, and averaged rather than thinned out. Ten colours give it volume — a highlight where the light falls on the head, back and tail, shade on the belly, the far legs and the haunch, the deepest shade inside the ears — and a face: cream cheeks and eyebrow, an eye with a catchlight, a black nose. The coat is orange rather than white because the island's icons are white, and a white dog beside them read as one more glyph.

The head is the same in every frame; only the body moves under it. A blink and a pant are the same pose with the eye or the mouth painted over, so a frame never changes more than it needs to.

| Frame | Used for |
|---|---|
| `stand`, `standBlink` | Standing still, and blinking while standing |
| `strideA`, `strideB` | The walk: each leg's paw reaches a point forward or back, cycling `strideA`, `stand`, `strideB`, `stand` |
| `crouch` | Half-way between standing and sitting, in both directions |
| `sit`, `sitBlink`, `sitPant`, `sitWag` | Sitting, and the three gestures made while sitting |

Every frame stands on the same bottom row, and the pet's paws are level with the bottom of the icons' band, so switching frames never makes it hop and it stands on the same line as the glyphs beside it.

## The routine

`PetRoutine` is what the pet does on a stage: an **entrance** from wherever the pet was when the stage began, then a **loop** repeated for as long as the stage lasts. Both are `PetTimeline`s — keyframes of position, facing and frame — written by `PetChoreographer` as a script (walk here, sit there, blink) rather than as a table.

| Motion | Pace |
|---|---|
| Walk | 15 points a second, one point per step; legs change every 2/15 s |
| Run — out of an icon's way, or off the island | 30 points a second; legs change every 1/15 s |
| Turn | On the spot, standing square — a sitting pet stands up first, a leg mid-stride comes back under it — then held 0.15 s |
| Sit down, stand up | Through `crouch`, held 0.12 s |

| Loop | Length | What happens |
|---|---|---|
| Roaming | About 21 s | Sits, strolls to the far end, sits, strolls back part-way, sits, walks to the near end, turns, sits, walks home. A blink, a wag or a pant in every sit |
| Resting | About 16 s | Sits with a blink and a wag, stands to look back towards the island's edge, turns back, sits and pants |

Both loops sit for well over half their length. A pet that never stopped moving would be a distraction on the edge of the screen, and sitting is when the pet asks nothing of the display.

The routine is decided the moment the stage changes. `PetRoutineTracker`, held by the presenter, keeps the routine and the moment it began — in system uptime, the clock Core Animation plays it on, so the pose the tracker reads is always the pose on screen, whatever the wall clock does; a refresh that finds the pet on the same stage changes nothing, and a stage change starts the new routine from the pose the old one had reached at that instant. The pet therefore never jumps: every entrance begins where the pet was and ends in exactly the pose its loop opens with, and no two consecutive keyframes are more than one point apart. A pet switched on enters from beyond the island's outer edge.

The tracker lives in the presenter rather than in the view because the compact view is rebuilt on every expand and collapse; a routine kept in the view would start over on every hover. When the island collapses, the new view joins the routine where it has got to.

## Drawing and cost

The pet is one `CALayer` in `PetLayerHostView`. Each timeline becomes a `CAAnimationGroup` of two discrete keyframe tracks — `contents` (the frame image) and `position.x` — so each value holds until the next replaces it. The entrance plays once and is removed; the loop repeats indefinitely and stays attached, as the equaliser's strokes do, so Core Animation cannot quietly drop it while the view stays in its window. The layer's model values always hold where the routine leaves the pet, so it is in place whenever nothing is animating it.

- **No work in KerNotch per frame.** The routine plays in the render server. There is no timer, no task, no display link, and no SwiftUI animation; the view's body is evaluated only when the routine, the placement or the motion setting changes. Source tests keep clocks out of every file that draws the pet.
- **No wake-ups.** Stage changes happen on events the presenter already handles; the routine needs nothing to keep it going.
- **A low frame rate.** Every animation asks for 15 frames a second (`PetAnimation.frameRateRange`) — the walk's step rate — and allows at most 30, so on a ProMotion panel the pet never holds the display at 120 Hz, and the long sits cost the render server a fraction of a full-rate animation. A run is then drawn two points at a time, which pixel art carries well.
- **Tiny images.** Each frame is drawn once into a 32 × 24 image, for both facings: about 55 KB for the whole pet, kept for the app's lifetime.
- **Never resampled.** Shown pixel for pixel on a Retina panel, and held at that size through the hover peek, which scales the rest of the island: the pet rides the peek's movement with the peek's scale undone (`islandHoverScale`, `islandPeekCounterScale(for:)`).
- **Nothing runs when there is nothing to see.** The island expanded, hidden or asleep, or the pet away once it has left: no animation is attached.

With motion reduced — by the system's Reduce Motion or by KerNotch's own Motion setting in General, whichever the user chose — and while the CPU watchdog holds the island still, the pet sits where its loop rests and nothing animates; with the flank full it is not drawn at all. KerNotch's setting reaches the pet, as it reaches every island animation, through the `prefersReducedIslandMotion` environment value, because SwiftUI's own reduce-motion value is the system's alone.

## Settings

Settings › Pet has one switch, "Show the pet on the island" (`pet.enabled`, default off — see `08-settings-and-localization.md`), and a strip of island black with the pet walking its roaming routine, dimmed while the switch is off. The switch applies live on the island: the pill widens and the pet walks in, or the pill narrows and the pet goes.

## Tests

- `KerNotchCoreTests` — the stage rule, the stage geometry, every frame's shape and palette, mirroring, and the routine invariants: entrances begin in place and end on the loop's opening pose, the pet never moves more than a point between keyframes, turns happen on the spot, loops close seamlessly, roaming covers the flank and resting never leaves its place, sitting takes most of each loop, and the tracker's continuity across stage changes.
- `KerNotchUITests` — icons are placed exactly as without a pet, the pill keeps its width beside the pet, the hover target covers the pet's flank, the images match the art, the pet stands on the icons' baseline, the animation tracks and their key times, the frame-rate cap, arming only in a window, resuming mid-loop, stillness under Reduce Motion, and the Pet pane.
- `KerNotchTests` — the pet is drawn on the compact island only, and the composition root wires it through (`PetWiringTests`).

Real hardware is still the judge of how the pet looks on a notch and what the render server spends on it: see the idle measurement in `02-performance-contract.md`, taken with the pet off, and its pet row, taken with the pet on.
