# Island Pet

This document specifies the pet: the small pixel dog or penguin that can live on the island. It covers where the pet stands and how it shares the pill with activity icons, the art and the animation it is drawn with, the routine it performs, how it reacts to what happens on the island, and what it costs. It is a design specification — the code follows it, not the other way round.

## What it is

A Shiba Inu puppy, 32 × 24 pixels of pixel art drawn in 16 × 12 points, that lives on the leading (left) side of the island. It walks, sits, blinks, pants and wags its tail, and it answers what happens on the island: it cocks its head at an agent's question, celebrates a finished task, nods along to music, and naps once the island has been empty for a while. It is switched on in Settings › Pet and is **off by default**: the idle island draws nothing that moves (`02-performance-contract.md`), and a pet walking across it is a change the user opts into rather than one made for them. With the pet on, its reactions are always on: there is nothing further to configure.

The pet can instead be a penguin in the likeness of Tux, the Linux mascot, the same size and density as the Shiba. It waddles rather than walks, slides on its belly wherever the dog would run, and has reactions of its own: it waves a flipper at the island opening, preens when it closes, squawks and taps its foot at an agent's question, slips flat on its back when one fails, dances and catches a fish when one finishes, and while an agent works it types at a laptop of its own or fishes through a hole in the ice. Settings › Pet chooses between them (`pet.species`, the dog by default).

Which animal the pet is, is its species (`PetSpecies`): it decides the sprite sheet the pet is drawn from, how it moves in a hurry, and how it plays each reaction and spends each mood. `IslandPet(species:)` pairs a species with its sheet. Both pets answer the same moments with reactions of the same name — `celebrate` is a wag for the dog and a flap for the penguin — each from a list of its own (`PetSpecies.reactions(to:)`), so what the island notices never depends on which pet is on it. The effects drawn beside the pet (`PetEffectArt.standard`) are shared by both.

## Where the pet stands

On the compact island the pet has one place of its own — one icon's width, 22 points — at the outer end of the leading flank. The icons keep every rule from `05-activity-model.md` — the pet never takes a place an icon needs, and never moves an icon to the other side of the notch — and take their places beside it from the notch side.

| Leading icons | Stage | Leading flank | What the pet does |
|---|---|---|---|
| None | `roaming` | 1 place | Walks about its place — the 16-point pet has six points to walk — and sits at points along it |
| One | `resting` | 2 places | Steps to the middle of its place and keeps to it, the icon in the place beside it |
| Two | `away` | 2 places | Runs out past the island's outer edge and is no longer drawn |

The pet widens the pill by its one place and never more (`CompactSlotLayout.leadingPlaceCount`): an icon arriving beside it gets a place of its own and widens the pill by it, exactly as it would without a pet, and with the flank full of icons the pet has gone and the pill is as wide as without it. Without a pet the flank is exactly as wide as its icons, as before.

Everything the pet does on the compact island stays in its place: its walks, every reaction, and the effects beside it, which reach no further than the island's margin on one side and the gap after its place on the other — never over the icon beside it. Reactions written for room — zoomies, a dash out and back when the charger goes in — run the length of the place instead, in more and shorter laps. The open island's strip is much wider, and there the pet has all of it.

Everything that sizes the compact pill reads the same answer — the icons, the black surface behind them, the mask that clips them, the offset onto the notch, the attention glow, and the hover target in `PresentationController`. The island reaches all of them through `compactSlotLayout(for:hiding:housing:)`, which takes the pet without a default; the secondary islands pass `nil` for it explicitly.

When the island opens, the pet moves onto the open island's strip beside the notch, above the cards, where there is more room (`islandPetStageGeometry`): it is always `roaming` there, whatever the icons were doing, so a pet that had left a full flank walks back in to see the cards. When the island closes it returns to the flank's stage. The island's root view draws the pet's stage itself (`IslandPetStage`), laid against the island's outer edge in both states — positions on either stage are measured from that edge — so the pet rides the edge on the island's own spring as it opens and closes, and its routine carries on from wherever it was.

The island is filled in before its panel is first ordered in, so with the pet on it appears at its resting width rather than growing to it on a spring at every launch.

The pet is drawn behind the icons and the cards, so an icon growing into the spot the pet is leaving is drawn over it. The view that draws the pet reaches from the island's outer edge to the notch — the margin the pet walks out through, the stage, and the gap to the notch its effects may reach into — and the island's mask clips it: leaving, the pet walks out through the margin and disappears at the island's side.

The pet lives on the primary island only. With "All displays", the other islands draw the activities but no pet: a second pet on another screen would be a copy, not company.

## The art

`PetSpriteSheet.shiba` holds every frame as rows of palette keys, drawn facing right; facing left is the same art mirrored. The art is drawn two image pixels to a point (`pixelsPerPoint`), which on a Retina panel is one image pixel per device pixel: as dense as the screen allows, and shown at exactly its own size, so it is never resampled. On a 1x display it is halved, and averaged rather than thinned out. Ten colours give it volume — a highlight where the light falls on the head, back and tail, shade on the belly, the far legs and the haunch, the deepest shade inside the ears — and a face: cream cheeks and eyebrow, an eye with a catchlight, a black nose. Two greys draw the headset it wears on a call. The coat is orange rather than white because the island's icons are white, and a white dog beside them read as one more glyph.

`ShibaArt` builds the frames from shared blocks. The head is the same in every standing and sitting frame; only the body moves under it. A blink, a bark and a yawn are the sitting pose with the eye or the mouth painted over, a bone or a headset is stamped onto the pose that carries it, and a nod lowers the head a row — so a frame never changes more than it needs to. The poses the pet lowers itself into, lying and bowing, are drawn whole.

| Frames | Posture | Used for |
|---|---|---|
| `stand`, `standBlink`, `strideA`, `strideB`, `shakeLeft`, `shakeRight` | Standing | Standing, blinking, the walk (cycling `strideA`, `stand`, `strideB`, `stand`), shaking itself off |
| `crouch` | Crouching | Half-way between standing and sitting or lying, in both directions, and the landing of a hop |
| `hop` | In the air | Every hop, drawn raised by the pose's lift |
| `sit`, `sitBlink`, `sitPant`, `sitWag`, `sitNod`, `bark`, `yawn`, `curious`, `curiousLow`, `earsBack`, `pawUp`, `dazed`, `holdBone`, `holdBoneWag`, `headset`, `headsetBlink`, `headsetNod` | Sitting | The sitting loops and every gesture made sitting: nodding to music, barking, yawning, a flopped ear for a question, ears back, a raised paw, a crossed-out eye, a bone in the mouth, a headset on a call |
| `lie`, `lieBlink`, `sleep`, `lieSad`, `lieDazed` | Lying | Watching the open island, napping, sulking, keeled over |
| `playBow`, `digA`, `digB` | Bowing | The stretch on waking, and digging |

Every frame on the ground stands on the same bottom row, and the pet's paws are level with the bottom of the icons' band, so switching frames never makes it hop and it stands on the same line as the glyphs beside it. The posture decides how the pet gets from one frame to any other: sitting and lying pass through the crouch, a bowed pet straightens up, and a pet caught in the air lands first.

### The penguin

`PetSpriteSheet.penguin` is Tux in a three-quarter view: a dark coat, a white front and eye patches, a yellow beak and feet, with the beak and the eyes turned the way it faces so its walk has a direction and mirroring it turns it round. The coat is slate rather than black and its outline is lit (`H`): on the island's black a black penguin would be a white belly floating on nothing. `PenguinArt` and `PenguinBodyArt` build its frames the way `ShibaArt` builds the dog's (`PetArtComposer`): the head is one block in every standing and sitting frame — a blink, a smile, lidded or crossed-out eyes are the head in another look — the body moves under it, the flippers are laid over a body drawn without them, and what it holds or works with — a fish, a headset, a laptop with a prompt on its screen, a rod over a hole in the ice — is stamped onto the pose that carries it.

| Frames | Posture | Used for |
|---|---|---|
| `stand`, `standBlink`, `strideA`, `strideB`, `shakeLeft`, `shakeRight`, `flippersOut`, `flippersUp`, `cheerOut`, `cheerUp`, `beam`, `waveLow`, `waveHigh`, `flipperRaised`, `footTapUp`, `footTapDown`, `squawk`, `standYawn`, `stretch`, `fanUp`, `fanDown`, `preenA`, `preenB`, `lookUp`, `holdFish`, `gulp`, `danceLeft`, `danceRight`, `swayLeft`, `swayRight`, `slip` | Standing | The waddle, flapping, beaming, waving, a raised flipper, an impatient foot, squawking, stretching and yawning, fanning itself, preening, catching and swallowing a fish, dancing, swaying to music, and losing its footing |
| `crouch` | Crouching | As for the dog, and the drop onto its belly for a slide |
| `hop` | In the air | Every hop, flippers out |
| `sit`, `sitBlink`, `sitNod`, `sitBeam`, `dazed`, `headset`, `headsetBlink`, `headsetNod`, `typing`, `typingLift`, `typingBlink`, `fishing`, `fishingBite`, `fishingBlink` | Sitting | Sat on its tail like the Linux logo, feet out in front: nodding to music, seeing stars, on a call, at the laptop, and fishing |
| `lie`, `lieBlink`, `sleep`, `slide`, `onBack` | Lying | Watching the open island, napping, sliding on its belly, flat on its back after a fall |

Both sheets draw the poses the machinery itself moves the pet through — standing, the walk, the crouch, the hop, sitting, lying, asleep, the shake, a headset and a crossed-out eye — under the same names, so getting from any pose to any other works the same for both. Beyond those, each sheet draws only its own poses.

### Effects

The effects drawn beside the pet (`PetEffect`) are pixel art at the same density: an exclamation mark, a question mark, hearts, the Zs of a nap, stars and sparkles, a rain cloud and its drops, a note, a bolt, a bell, a bone, a fish, a snowflake, dust, water, sweat, earth, and the lines a bark or a squawk leaves in the air. They are glyphs of the pet's own, not SF Symbols, so they belong to the pet rather than to the island's icons.

## The routine

`PetRoutine` is what the pet does: an **entrance** from wherever the pet was when something changed, then a **loop** repeated until the next change. The entrance holds everything that happens once — walking on, reacting to news, waking up, dozing off — and the loop is what the pet does in the meantime. Both are `PetTimeline`s — keyframes of position, lift, facing and frame, and a track for each effect beside the pet — written by `PetChoreographer` as a script (walk here, hop, bark twice, lie down) rather than as a table.

| Motion | Pace |
|---|---|
| Walk | 15 points a second, one point per step; legs change every 2/15 s |
| Run — out of an icon's way, off the island, or for joy | 30 points a second; legs change every 1/15 s. The penguin drops through the crouch onto its belly and slides instead, at the same pace, and gets up at the end |
| Hop | A crouch, a third of a second in the air along a sine arc a few points high, a crouch to land |
| Turn | On the spot, standing square — a sitting pet stands up first, a leg mid-stride comes back under it — then held 0.15 s. A sitting pet looking the other way for a moment glances instead: the sitting frame, mirrored in place |
| Sit down, stand up, lie down | Through `crouch`, held 0.12 s |

The loop follows the pet's **mood** (`PetMood`), read from the island at every refresh (`PetCueReader`), strongest first:

| Mood | When | Loop |
|---|---|---|
| Hiding | The screen is being recorded | None: the pet runs off the island and stays off it until the recording ends |
| Asking | An agent is waiting on the user | A question mark over its head the whole time, and every few seconds the gesture it chose when the question came |
| Napping | An agent is out of quota | Asleep where it lay down, Zs drifting up, until the quota is back |
| On a call | A Discord call is going on | Sitting with a headset on, nodding now and then |
| Digging | An agent is working | Sitting a while, then digging in for a moment, earth flying back between its hind legs. The penguin types at a laptop, a prompt on its screen, or fishes through a hole in the ice until something bites and a fish leaps out and back |
| Listening | Music is playing | Sitting, and every few seconds nodding along with notes rising. The penguin nods along too, or stands and sways from foot to foot |
| Idle | Nothing is on the island | The stage's own loop, and after five minutes a nap |
| Calm | Anything else | The stage's own loop |

| Stage loop | Length | What happens |
|---|---|---|
| Roaming | About 21 s | Sits, strolls to the far end of its stage, sits, strolls back part-way, sits, walks to the near end, turns, sits, walks home — a few steps each way in its place on the pill, the length of the strip on the open island. A blink, a wag or a pant in every sit |
| Resting | About 16 s | Sits with a blink and a wag, stands to look back towards the island's edge, turns back, sits and pants |

The penguin's stage loops follow the same plan: it waddles where the dog strolls, and between sits it stands for a flap of its flippers or to preen. On an empty island it now and then spends a loop out in the snow — flakes drifting down around it until it looks up and catches one in its beak — about once a minute (`PenguinLoops.idleLoop`).

Where the penguin knows more than one way of spending a mood — music heard nodding or swaying, an agent kept company at the laptop or over the ice — the tracker picks one at random when the mood begins and keeps it while the mood lasts (`PetPastime`). A mood spent only one way rolls no die, so the dog's choices are exactly what they were before the penguin came.

Every loop sits for most of its length. A pet that never stopped moving would be a distraction on the edge of the screen, and sitting is when the pet asks nothing of the display. Beside a single icon every loop and every reaction keeps to the middle of the pet's place; with the flank to itself the pet sits at a home a little in from the edge.

**The nap.** When the island empties, the routine planned at that moment plays the stage's loop for five minutes (`PetRoutineTracker.napDelay`) — counted from the island emptying, or from the pet last being petted, and rounded up to the end of the loop it is in, so up to twenty seconds more, or a little over a minute for the penguin's snowy loop — then lies the pet down and loops it asleep. The five minutes are part of the entrance Core Animation plays, so no timer puts the pet to sleep. Anything arriving on the island wakes it: it blinks, gets up, stretches — into a bow, or with its flippers swept back — and yawns before its new routine; news wakes it straight into its reaction instead.

## Reactions

Something happening on the island (`PetMoment`) is answered with a reaction (`PetReaction`): a few seconds played where the pet is, which ends on the floor and hands over to the loop without a jump. Each moment has its reactions for each pet, and the pet picks one at random each time (`PetDice`, a seeded generator the tracker holds as a plain value).

| Moment | The dog's reactions |
|---|---|
| The island opens | A startled hop under an exclamation mark · running with the island's edge to its new corner · lying down to watch for as long as the island stays open |
| The island closes | Shaking itself off like a wet dog · a long stretch and a yawn · panting with relief |
| An agent asks something | A flopped ear and a tilted head · barking for the user · a raised paw · looking one way, then the other — each with a question mark |
| An agent fails | Ears back, then lying down under a rain cloud · seeing stars · keeling over, then shaking it off |
| An agent runs out of quota | Ears back, a yawn, and off to sleep until the quota is back |
| An agent finishes (not a sub-agent) | Two hops for joy among sparkles · zoomies end to end of its stage — three short laps in its place on the pill · catching a bone that drops from above |
| A countdown runs out | Barking at a bell ringing over its head |
| The charger goes in | A bolt, a hop and a dash out and back |
| The CPU watchdog's notice | Panting with a bead of sweat |
| The pointer moves onto the pet | Wagging, with hearts floating up |

| Moment | The penguin's reactions |
|---|---|
| The island opens | A startled hop under an exclamation mark · sliding on its belly to the island's new corner · lying down to watch · waving a flipper hello |
| The island closes | Shaking the water off · a stretch with the flippers swept back, and a yawn · fanning itself with a flipper · preening its chest feathers |
| An agent asks something | Squawking for the user · a flipper raised like a hand · tapping its foot, a flipper on its hip — each with a question mark |
| An agent fails | Seeing stars · slipping flat on its back, stars round its head, then up and shaking it off |
| An agent runs out of quota | A yawn, then down on its belly and asleep until the quota is back |
| An agent finishes (not a sub-agent) | Two hops for joy among sparkles · catching a fish that drops into its beak and swallowing it whole · a dance, flippers up |
| A countdown runs out | Squawking at a bell ringing over its head |
| The charger goes in | A bolt, a hop and a slide out and back |
| The CPU watchdog's notice | Fanning itself with a bead of sweat |
| The pointer moves onto the pet | Flapping for joy, with hearts floating up |

News is an arrival — a state entered, a notice appearing, the island opening — never a state held: agents repeat their state freely, and a pet that reacted to every repetition would never stop. The island opening and closing happen whenever the pointer passes over it, so they are answered only now and then: about one time in four, never twice within a minute, and never the same way twice running. The pointer passing over the pet wags it once, not continuously (eight seconds between). Reactions that need room to run — zoomies, running or sliding with the edge — are left out beside an icon.

`PetRoutineTracker`, held for the presenter by `IslandPetKeeper`, decides what cuts in on what:

- **Having to move always wins.** An icon arriving on the pet's spot, the flank filling, a screen recording starting: whatever the pet was doing is dropped, and it goes where it has to be.
- **The island opening or closing lets a reaction carry on** on the new stage, as long as it fits there — anywhere on a flank the pet has to itself, or the one place beside an icon: a celebration the user opened the island to look at is not cut off by the opening.
- **News cuts in only if it matters as much** (`PetMoment.urgency`: an agent asking, failing or out of quota first; then a finished task or a countdown; then the charger and the watchdog; then the island and the pointer). Anything less is let go rather than queued — news that waited would no longer be news — and uses up nothing: no die is rolled and no cooldown starts for it. A reaction the same change drops anyway holds nothing back.
- **A change of mood lets the reaction finish.** Music starting half-way through a celebration: the rest of the celebration plays (`PetTimeline.cut`), then the pet nods along.
- **Off the island, nothing is heard.** A pet that has left a full flank, or the screen while it is recorded, reacts to nothing.

Every change starts the new routine from the pose the old one had reached at that instant — mid-hop, mid-stride or asleep — so the pet never jumps: every entrance begins where the pet was and ends in exactly the pose its loop opens with, and no two consecutive keyframes are more than one point apart. A pet caught high in a hop comes down two points a frame, as a hop does, before it does anything else.

## Drawing and cost

The pet is a `CALayer` in `PetLayerHostView`, with a layer for each effect of its routine beside it. Each timeline becomes a `CAAnimationGroup` of discrete keyframe tracks — for the pet `contents` (the frame image), `position.x` and `position.y` (its lift), and for each effect its `position` and whether it is `hidden` — so each value holds until the next replaces it. The entrance plays once and is removed; the loop repeats indefinitely and stays attached, as the equaliser's strokes do, so Core Animation cannot quietly drop it while the view stays in its window. The layers' model values always hold where the routine leaves them — the pet where it settles, every effect out of sight — so nothing is left hanging whenever nothing is animating.

- **No work in KerNotch per frame.** The routine plays in the render server. There is no timer, no task, no display link, and no SwiftUI animation; the view's body is evaluated only when the routine, the placement or the motion setting changes. Source tests keep clocks out of every file that draws or plans the pet.
- **No wake-ups.** The pet's mood and news are read on refreshes the island already makes for its activities, the pointer moving onto the pet is noticed by a tracking area only while the pointer is over the island, and the nap is part of the routine: nothing wakes KerNotch to keep the pet going.
- **A low frame rate.** Every animation asks for 15 frames a second (`PetAnimation.frameRateRange`) — the walk's step rate — and allows at most 30, so on a ProMotion panel the pet never holds the display at 120 Hz, and the long sits cost the render server a fraction of a full-rate animation. A run is then drawn two points at a time, which pixel art carries well.
- **Tiny images.** Each frame the pet's sheet draws is drawn once into a 32 × 24 image, for both facings, and each effect once as drawn and mirrored: a few hundred kilobytes for the whole pet, kept for the app's lifetime. The other pet's poses are never drawn.
- **Never resampled.** Shown pixel for pixel on a Retina panel, and held at that size through the hover peek, which scales the rest of the island: the pet rides the peek's movement with the peek's scale undone (`islandHoverScale`, `islandPeekCounterScale(for:)`).
- **Nothing runs when there is nothing to see.** The island hidden or asleep, or the pet away once it has left: no animation is attached.

With motion reduced — by the system's Reduce Motion or by KerNotch's own Motion setting in General, whichever the user chose — and while the CPU watchdog holds the island still, the pet sits where its loop rests (awake, even with its nap due) and nothing animates or is drawn beside it; with the flank full it is not drawn at all. KerNotch's setting reaches the pet, as it reaches every island animation, through the `prefersReducedIslandMotion` environment value, because SwiftUI's own reduce-motion value is the system's alone.

## Settings

Settings › Pet has one switch, "Show the pet on the island" (`pet.enabled`, default off — see `08-settings-and-localization.md`), a choice of animal, Dog or Penguin (`pet.species`, default the dog), and a strip of island black with the chosen pet walking in and then its roaming routine, afresh whenever the choice changes, dimmed while the switch is off. Both apply live on the island: the pill widens and the pet walks in, or the pill narrows and the pet goes; picking the other pet swaps them, the new one walking in from the island's edge (`IslandPetKeeper` starts a new life for a new species rather than playing the old one's routine in the new one's poses). The reactions come with the pet and have no switches of their own.

## Tests

- `KerNotchCoreTests` — the stage rule, the stage geometry on the pill and the open island, every frame's shape, palette and posture, mirroring, the effects' art; the routine invariants: entrances begin in place and end on the loop's opening pose, the pet never moves more than a point between keyframes, turns happen on the spot, loops close seamlessly, roaming covers the flank and resting never leaves its place, sitting takes most of each loop; every reaction from every kind of pose on both stages — back on the floor, in the air only mid-hop, effects kept to the reaction, never off its stage; every mood's loop, the question mark held while an agent waits, the nap after five minutes, waking up, carrying a reaction into a new mood; the tracker's rules — news held or let go by urgency, the island answered about one time in four with its cooldown and variety, stage changes, a reaction carried across the island opening, the petting cooldown, the question's gesture kept; and the cues read from activities. Every invariant of the reactions runs for both pets; the penguin's own suites check its art (a blink touches only the eyes, one foot off the floor mid-waddle, a coat that shows on black), its belly slide, each of its reactions and pastimes, its snow and nap, that every pose it is ever shown in is on its sheet, and the tracker's pick of a pastime.
- `KerNotchUITests` — icons are placed exactly as without a pet, the pill keeps its width beside the pet, the hover target covers the pet's flank, the images match the art, the pet stands on the icons' baseline, the animation tracks and their key times, effect layers and their tracks, the frame-rate cap, arming only in a window, resuming mid-loop, stillness under Reduce Motion, noticing the pointer only over the pet, the open island's wider stage, the keeper — a swapped pet walking in afresh — and the Pet pane with its switch and its picker.
- `KerNotchTests` — the pet is drawn on the compact and the open island, and the composition root wires it through (`PetWiringTests`).

Real hardware is still the judge of how the pet looks on a notch and what the render server spends on it: see the idle measurement in `02-performance-contract.md`, taken with the pet off, and its pet row, taken with the pet on.
