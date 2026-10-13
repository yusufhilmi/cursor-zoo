# Cursor Zoo

A menu-bar Mac app that **replaces your system cursor** with a character. Not a
pet that follows the pointer: the character *is* the pointer, and its tip (a nose,
a bumper, the point of a hood, a snout) is where you click.

It started as the **Cursor Playground** in the Polymet editor, where Cey built a
cursor that is literally a mouse. This is that idea escaping the browser and
taking over the whole desktop.

## The zoo

Every character speaks the same six-slot vocabulary and fills every slot. That
table is the design contract; a new character is not done until its row is full.

| | idle | move | left click | right click | double click | scroll |
|---|---|---|---|---|---|---|
| **Tiny Mouse** | breathes, blinks, wags | leans, feet patter, paw prints | **left** paw slaps the spot you clicked | **right** paw does | happy hop off its shadow, hearts | tail whip |
| **Lil Racer** | parks back in the arrow pose, idles, the odd puff | driven like a real car: the rear follows the front through smooth arcs, front wheels steer, tread marks darken where the tyres would slip | honk: headlights double-flash, sound waves | donut: a full spin in a ring of smoke and skid arcs | nitro: flames, speed lines, shake | revs: wheels spin, exhaust |
| **Shadow Ninja** | fighter's bounce, glowing eyes blink | headband streams, after-images on fast dashes | left jab to the spot, comic star | right punch, same | full spin, smoke ring, four shuriken | a twirl that springs back |
| **Pocket Dragon** | slow wingbeat, blinks, nostril smoke | wings beat faster, embers off the tail | chomp: two teeth meet on the spot | wing gust, wind curls behind | fire breath, a short cone from the snout | tail whip, flutter |

Every click also lands a small ring of ticks right on the click point, so you
always know exactly where it registered. Speech bubbles ("squeak!", "BEEP!") are
available from the menu but **off by default**: the animation carries the click.

All four are original designs drawn as vector shape layers. The options were
settled in a clickable playground before any of this was built.

## Build and run

```sh
./build.sh && open "Cursor Zoo.app"
```

No Xcode project, no dependencies. The app lives in the menu bar — no Dock icon,
no window. Use the menu bar item to switch character, change size, toggle
**Replace system cursor**, pause, or quit.

`./build.sh` deliberately uses the Command Line Tools toolchain
(`/Library/Developer/CommandLineTools`). `/usr/bin/make`, `xcodebuild` and the
default `swift` shim all refuse to run until someone has run
`sudo xcodebuild -license accept` on the machine; the CLT toolchain has no such
gate. A `Makefile` with the same targets is included for once the license *is*
accepted.

## If your pointer ever goes missing

```sh
./restore-cursor.sh
```

That asks Cursor Zoo — and only Cursor Zoo, by name — to quit, which hands the
pointer back. Failing that, log out and back in; the window server restores the
cursor when the session ends.

## Checking it works

Verifying a cursor overlay by eye needs a Screen Recording grant, and nobody
wants to debug this by hiding their own pointer. So the app renders itself:

```sh
.build/release/CursorZoo --selftest sheet.png
```

That plays a scripted timeline through the real `CharacterView` at a simulated
120 Hz — idle, left click, right click, double click, scroll, a fast drive — and
renders a contact sheet: one row per character, one column per interaction, a
crosshair on the hotspot in every cell. Because the clock is simulated the sheet
is reproducible, tracks and after-images included, and nothing touches the real
cursor. It exits non-zero if the render comes out blank.

```sh
.build/release/CursorZoo --trackstest tracks.png
```

One long drive with the racer — an S-bend, a hairpin, a fast run into a hard stop,
a donut — so the tyre marks can be judged as a whole.

### How the car drives

The pointer tows the front bumper and the rear axle trails behind at a fixed
distance, like a bicycle or a trailer. Heading is simply the line from rear axle
to bumper, so the car can only turn by driving through an arc: the rear follows
and cuts inside the curve, and the tracks come out as smooth curves with real
off-tracking. Front-wheel angle comes from the bicycle model,
`atan(wheelbase × turn rate ÷ speed)`. How dark the marks are comes from how hard
the tyres are working: sideways acceleration in a turn (speed × turn rate), hard
launches and stops along the car, nitro and the donut. Marks are laid from the
physics pose, not the drawn one, so the honk bounce and nitro shake never wiggle
the line.

## How it works

- **`CursorHider.swift`** takes the real pointer away. macOS has no public API for
  this: `CGDisplayHideCursor` alone only applies while your app is frontmost, so
  the app first sets the undocumented `SetsCursorInBackground` property on its
  window-server connection (`CGSSetConnectionProperty`, declared in the
  `CGSPrivate` shim target). This is the same family of private calls
  [Mousecape](https://github.com/alexzielenski/Mousecape) uses.
- **`Rig.swift`** is the contract every character implements, plus the shared
  drawing kit. Each character (`MouseRig`, `RacerRig`, `NinjaRig`, `DragonRig`)
  is shape layers, not bitmaps, so paws, wheels, fists and wings move on their own
  pivots. Everything is laid out in body space with **the hotspot at the origin**,
  and the root layer's anchor point sits on that origin. A rig may rotate and scale
  its root (both pivot on the hotspot) but never translate it, which is why no
  animation can drift the tip off the pointer: the mouse's hop is a scale-up off a
  shrinking shadow, the car's donut is a spin about its bumper.
- **`Effects.swift`** holds everything left behind in screen space. Tyre marks
  are one continuous stroke per tyre that follows exactly where the wheel went,
  cut into short chunks that fade oldest-first, so curves and donut arcs never
  break up. Everything else — paw prints, smoke, fire, shuriken, after-images — is
  a pooled particle system in two lanes, under and over the character, recycled
  oldest-first so a burst of activity can never grow the layer tree without bound.
- **`Overlay.swift`** puts one borderless, click-through `NSWindow` over each
  display, a level above the screen saver and joining all Spaces. Rebuilt on
  `didChangeScreenParametersNotification`.
- **`MouseTracker.swift`** follows the pointer on a `CADisplayLink` at the display's
  native refresh rate. Buttons are **polled** from `NSEvent.pressedMouseButtons`
  rather than read through a global event monitor: polling needs no Accessibility
  grant and at 60–120 Hz it catches every human click. Only scroll uses a monitor
  (mouse-only monitors do not prompt either). **The app asks for no permissions.**
- **`Character.swift`** is pure data — a new character is a struct literal.

## Not stranding you without a pointer

Hiding the system cursor is the one genuinely dangerous thing this app does, so:

- `hide`/`show` are reference counted per connection and always balanced.
- `atexit` plus handlers for every catchable fatal signal (`SIGTERM`, `SIGSEGV`,
  `SIGABRT`, …) restore the cursor on the way out, crashes included.
- The pointer is handed back whenever the app cannot be sure it is still drawing:
  **screen locked**, screen saver, display asleep, machine asleep, fast user
  switch, or paused. The lock screen matters most — the overlay cannot draw there,
  so without it you would reach a login window with no pointer.
- A watchdog on a background queue covers the one case none of that can: the
  main thread **hanging**. A hang fires no signal, but it stops the overlay
  drawing, which would leave you with neither pointer. Every frame bumps a
  heartbeat; if it goes stale for two seconds the watchdog shows the real cursor,
  and the next healthy frame hides it again.
- If the process dies so hard that none of that runs, the hide is released when the
  window-server connection is torn down — the same mechanism that returns your
  pointer when a full-screen game crashes. **This last link is the one the app
  cannot itself guarantee, and it has not been verified on macOS 26**; deliberately
  crashing a machine with many dev servers running was not a test worth doing.
  `restore-cursor.sh` exists for that case.

## Known limits

- **Replace mode hides every system cursor, not just the arrow.** The I-beam over
  text, the hand over links, the resize arrows at window edges — all gone while
  the mouse is in charge. Two possible fixes, on the roadmap: poll
  `NSCursor.currentSystem` each tick and swap the mouse's pose (a tiny I-beam
  held in its paws), or briefly give the real pointer back for those states.
- The overlay is driven by a display link polling `mouseLocation`, so the drawn
  mouse trails the real hardware pointer by about one frame (~8 ms at 120 Hz).
  Noticeable only on a fast flick. The zero-latency alternative is registering the
  art as the actual system cursor via `CGSRegisterCursorWithImages`, but that
  trades away live paws — the window server would draw a static image.
- Nothing can draw over the login window, the screen saver, or games that capture
  the cursor. The real pointer comes back in those.
- Unsigned and un-notarised: there is no Developer ID on this machine, so the
  bundle is ad-hoc signed. Opening it on another Mac needs System Settings →
  Privacy & Security → "Open Anyway", or `xattr -cr "Cursor Zoo.app"`.

## Releases

Tag a version and push the tag:

```sh
git tag v0.1.0 && git push origin v0.1.0
```

`.github/workflows/release.yml` builds the app on a macOS runner, runs the render
self-test, zips the bundle with `ditto` (plain `zip` drops the resource forks),
writes a SHA-256 next to it, and publishes a GitHub Release with notes generated
from the commits since the previous tag. It authenticates with the run's own
`GITHUB_TOKEN` — no personal credentials are involved.

`.github/workflows/ci.yml` builds every push and PR and uploads the self-test
PNGs as artifacts, so a change to the artwork can be reviewed by eye from the PR.

### Signing and notarisation

Out of the box the release is **ad-hoc signed**: it runs, but the first launch on
another Mac needs System Settings → Privacy & Security → *Open Anyway*. To ship
something that just opens, add these repository secrets and the workflow switches
the extra steps on by itself:

| secret | what |
|---|---|
| `MACOS_CERTIFICATE_P12` | base64 of a *Developer ID Application* certificate exported as `.p12` |
| `MACOS_CERTIFICATE_PASSWORD` | its export password |
| `MACOS_SIGNING_IDENTITY` | e.g. `Developer ID Application: Yusuf Hilmi (TEAMID)` |
| `NOTARY_APPLE_ID` | the Apple ID email |
| `NOTARY_TEAM_ID` | the 10-character team id |
| `NOTARY_APP_PASSWORD` | an app-specific password from appleid.apple.com |

All six need an Apple Developer Program membership. With the first three the
bundle is signed with hardened runtime; with all six it is also notarised and
stapled, and Gatekeeper opens it without a word. Auto-update (Sparkle) and a
Homebrew cask are the natural next steps once a signed release exists.

## Roadmap

- [ ] Real sprite art exported from the Polymet cursor pack
- [ ] Character packs as on-disk JSON + PNG so people can make their own
- [ ] Contextual cursors in replace mode (I-beam, hand, resize)
- [ ] Launch at login
- [ ] Sound on reactions (off by default)

## A note on characters

Every character here is an original design. If the pack grows anime and
racing characters, they need to be **original designs in those styles** — not
Naruto, not Lightning McQueen. Recognisable studio characters in a public download
is a trademark problem, not a grey area.

## License

MIT — see [LICENSE](LICENSE). Use it, fork it, ship your own zoo.
