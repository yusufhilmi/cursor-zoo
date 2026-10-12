# Cursor Zoo

A menu-bar Mac app that **replaces your system cursor** with a tiny mouse. Not a
pet that follows the pointer — the mouse *is* the pointer. Its nose is the tip.

It started as the **Cursor Playground** in the Polymet editor, where Cey built a
cursor that is literally a mouse. This is that idea escaping the browser and
taking over the whole desktop.

It has paws, and it uses them:

| | Tiny Mouse |
|---|---|
| left click | left paw slaps down — *squeak!* |
| right click | right paw slaps — *big backs!* |
| double click | both paws up, body pops — *thwack!* |
| scroll | tail whips, momentum decays |
| moving | leans into the direction of travel |

Three emoji characters (Lil Racer, Shadow Ninja, Pocket Dragon) ride along as
placeholders for the rest of the pack; only the mouse has real articulated art.

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
.build/release/CursorZoo --mousetest out.png   # the mouse in five poses
.build/release/CursorZoo --selftest  out.png   # every character mid-reaction
```

`--mousetest` draws a crosshair at the pointer position in each pose, so you can
confirm the nose stays welded to the hotspot through a slap, a hop and a lean.
`--selftest` exits non-zero if the result comes out blank.

## How it works

- **`CursorHider.swift`** takes the real pointer away. macOS has no public API for
  this: `CGDisplayHideCursor` alone only applies while your app is frontmost, so
  the app first sets the undocumented `SetsCursorInBackground` property on its
  window-server connection (`CGSSetConnectionProperty`, declared in the
  `CGSPrivate` shim target). This is the same family of private calls
  [Mousecape](https://github.com/alexzielenski/Mousecape) uses.
- **`TinyMouse.swift`** is the artwork — shape layers, not a bitmap, so each paw
  swings on its own pivot. Everything is laid out in body space with **the nose at
  the origin**, and the root layer's anchor point sits on that origin. Rotating,
  scaling or squashing the mouse therefore pivots around its nose, which is why no
  animation can ever drift the hotspot off the pointer. The double-click "hop" is a
  scale pulse and a wobble rather than a jump, for exactly that reason.
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
- If the process dies so hard that none of that runs, the hide is released when the
  window-server connection is torn down — the same mechanism that returns your
  pointer when a full-screen game crashes. **This last link is the one the app
  cannot itself guarantee, and it has not been verified on macOS 26**; deliberately
  crashing a machine with many dev servers running was not a test worth doing.
  `restore-cursor.sh` exists for that case.

## Known limits

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

## Roadmap

- [ ] Real sprite art exported from the Polymet cursor pack
- [ ] Articulated art for the other characters, not just the mouse
- [ ] Character packs as on-disk JSON + PNG so people can make their own
- [ ] Launch at login
- [ ] Sound on reactions (off by default)

## A note on characters

Everything here is original or a plain Unicode emoji. If the pack grows anime and
racing characters, they need to be **original designs in those styles** — not
Naruto, not Lightning McQueen. Recognisable studio characters in a public download
is a trademark problem, not a grey area.
