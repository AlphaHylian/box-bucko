# BoxBucko

A little Minecraft-skinned friend that lives in your menu bar. Upload any
Minecraft skin PNG and BoxBucko renders it as a real, blocky 3D model that
sits on your desktop — draggable, animated, and always on top. No app
windows, no Dock icon: just the menu bar icon and your little guy.

Named by whoever wrote this task: "it's a bucko on your screen made of boxes."

## Features

- **Menu bar only.** Lives as a status-bar icon (where the clock/battery
  live). No Dock icon, no app windows, no title bars.
- **Real 3D Minecraft model.** Built from actual box geometry (head, body,
  arms, legs, plus the hat/jacket/sleeve/pants overlay layer), UV-mapped
  straight from your skin texture using Minecraft's own skin layout.
- **Auto-detects Classic vs. Slim (Steve vs. Alex) arms** by inspecting the
  skin's arm-texture pixels — no need to tell it which one you have.
- **Legacy skin support.** Old 64x32 skins get upgraded to the modern 64x64
  layout automatically (mirroring the right arm/leg onto the left, like
  Minecraft itself does).
- **Draggable**, with a bit of throw/fling inertia when you let go.
- **Animated**: idle breathing, random head-looks, walking, jumping, waving,
  dancing, sitting/standing, all built from procedural SceneKit actions.
- **Wanders your screen** on its own when you leave it alone (toggle-able),
  walking to a random spot, then pausing, forever.
- **Follows your cursor** with its head/eyes (optional).
- **Speech bubbles** with idle chatter and reactions to clicks.
- **A skin library** — import multiple skins and switch between them from the
  menu; skins persist across launches.
- **Resizable** (Small/Medium/Large/Huge, right from the menu).
- **Launch at Login** support (via `SMAppService`, once packaged as a real
  `.app` — see below).
- Runs on **all Spaces**, including over full-screen apps.

## Building & running

This is a Swift Package (no Xcode project file needed, though you can open
the folder directly in Xcode too — File → Open → select this directory).

```sh
swift run
```

That builds and launches BoxBucko directly. It'll show up in your menu bar
immediately. (Quit it from the menu — "Quit BoxBucko" — or Ctrl-C the
process.)

### Building a real `.app`

`swift run` launches a bare executable, which is fine for development, but a
couple of features (custom name in Activity Monitor, "Launch at Login") need
BoxBucko to actually be an installed `.app` bundle. To build one:

```sh
make bundle
```

This produces `dist/BoxBucko.app` — drag it into `/Applications` and double
click it like any other app. `Info.plist` sets `LSUIElement`, so it never
shows a Dock icon or appears in Cmd-Tab, matching the `swift run` experience.

## Using it

- **Click** BoxBucko to make it wave and say hi.
- **Double-click** to make it jump.
- **Drag** it anywhere on screen.
- **Right-click** for a quick actions menu.
- Everything else — choosing a skin, size, wandering, cursor-follow, speech
  bubbles, launch at login — lives in the menu bar dropdown.

### Skins

Any standard Minecraft skin PNG works: 64x64 (modern) or 64x32 (legacy, both
get upgraded automatically). Classic (Steve, 4px arms) and Slim (Alex, 3px
arms) are both auto-detected from the texture — you don't need to specify
which.

If a freshly-loaded skin ever looks visibly wrong (like the texture reads
top-to-bottom flipped), there's a **"Flip Texture"** toggle in the menu as an
escape hatch — SceneKit's exact texture-orientation behavior can vary subtly
across GPU/driver combinations, and this flips the V axis without needing a
rebuild.

## How the model is built

Everything lives in `Sources/BoxBucko/`:

- `SkinUVMap.swift` — the math for Minecraft's "box unwrap" UV layout (the
  same formula reproduces the head, body, arms, legs, and their overlay
  layers just by varying origin/dimensions).
- `SkinTextureLoader.swift` — loads a skin PNG, upgrades legacy 64x32 skins,
  and auto-detects Classic vs. Slim arms.
- `SkinModelBuilder.swift` — builds the actual `SCNNode` rig: six
  `SCNBox`es (one per body part) with per-face materials whose
  `contentsTransform` slices out the right sub-rectangle of the skin texture.
- `AnimationController.swift` — idle/walk/wander/gesture animations, built
  from `SCNAction`s.
- `PetWindowController.swift` / `PetView.swift` — the borderless, transparent,
  always-on-top `NSPanel` that hosts the SceneKit view, plus drag handling.
- `StatusBarController.swift` / `AppController.swift` — the menu bar UI and
  the app's central coordinator.
- `SkinLibrary.swift` / `Preferences.swift` — persistence (imported skins
  live under `~/Library/Application Support/BoxBucko/`, settings in
  `UserDefaults`).

No physics engine, no external dependencies — just AppKit + SceneKit.
