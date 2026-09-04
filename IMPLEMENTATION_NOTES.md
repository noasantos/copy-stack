# Onboarding — implementation notes

Every place the shipped code departs from `SPEC.md` / the `reference-html` artboards, and why.
Anything not listed here follows the spec.

## Deviations forced by the macOS 13 deployment target

ClipStack ships to macOS 13 (`MACOSX_DEPLOYMENT_TARGET = 13.0`), so three APIs named in the
spec are unavailable and were replaced with equivalents that behave identically:

| Spec | Shipped | Why |
|---|---|---|
| `@Observable final class OnboardingModel` | `ObservableObject` + `@Published`, observed with `@ObservedObject` | The Observation framework is macOS 14+. Same property set, same semantics. |
| `UnevenRoundedRectangle` | `UnevenRoundedRect` (`ClipStack/Onboarding/OnboardingTheme.swift`) | `UnevenRoundedRectangle` is macOS 14+. The local shape takes the same four corner radii and also conforms to `InsettableShape`, so `strokeBorder` and `inset(by:)` work. |
| `.buttonBorderShape(.capsule)` | Applied behind `#available(macOS 14, *)` via `View.capsuleBorderIfAvailable()` | `ButtonBorderShape.capsule` is macOS 14+. On macOS 13 the Continue and Allow buttons keep their exact 220×36 / 32 pt metrics but render with the system rounded-rectangle border. |

`NSColor.quaternarySystemFill` is likewise macOS 14+; the quaternary fills are built from the
label color at the artboard's own alphas (0.045 light / 0.06 dark, 0.09 / 0.12 for the stronger one).

`onChange(of:initial:_:)` is macOS 14+ and the one-argument form is deprecated there, so the module
uses `View.onValueChange(of:perform:)`, which picks the right overload behind `#available`.

## Colour

The onboarding window's own chrome uses semantic colours only (`.labelColor`,
`.secondaryLabelColor`, `.tertiaryLabelColor`, `.separatorColor`, `.windowBackgroundColor`,
`.controlBackgroundColor`, `Color.accentColor`), as required.

Two deliberate exceptions, both in `OnboardingTheme.swift`:

- **`SceneTheme`** — everything drawn *inside* the laptop screen is a picture of other software
  (the menu bar, Notes, System Settings). Those tokens carry the artboard's literal values rather
  than this app's semantic colours, because they are simulating another app's chrome, not ours.
  They are still appearance-aware: each is an `NSColor(name:dynamicProvider:)` with a light and a
  dark value, so the scene follows the window's appearance.
- **`OnboardingChrome.keyCapFill`** — `.controlBackgroundColor` in light as the spec says, but
  `#454547` in dark (the value the spec itself quotes). The system control background is near-black
  in dark aqua and a key cap drawn in it reads as a hole rather than a key.

## Glass

`GlassPanelBackground` draws the Quick Paste panel and the popover. On macOS 26 it uses
`.glassEffect(.regular, in:)` with a light tint on top; below that it uses `.ultraThinMaterial`
with the artboard's 90 % glass tint over it, which is the direct translation of the artboard's
`backdrop-filter: blur(30px)` + `rgba(244,244,246,.9)`. The tint also guarantees the panel is
legible in contexts that do not composite materials (SwiftUI previews, `ImageRenderer`).

## Welcome step has no 112 pt app icon

`PROMPT.md` mentions rendering the app icon at 112 pt / 26 pt radius on the Welcome step. That is
from the v1 design (`reference-html/Window.dc.html`); the approved v2 design and `SPEC.md` §1–2 put
the MacBook frame in that space and give Welcome the popover scene plus the privacy line. The
v2 layout is implemented as specified. The icon gradient (`#3D9CFF → #0A6FE6`) is still used
in-app, for the ClipStack row in the System Settings scene, and ships as the app icon itself.

## App icon format

`AppIcon.appiconset` ships the full 16–1024 px PNG set from the handoff package. No `.icon`
(Icon Composer) bundle was generated: the PNG set is what the handoff provides, it is valid on
every supported OS including macOS 26, and hand-authoring an Icon Composer document from a flat
PNG would not produce the layered result that format exists for.

## Demo timeline

`SPEC.md` §5 gives cue times but no key-cap release times, while the artboard releases each key
200 ms after the press. The motion table's "250 ms hold" for the key-badge press wins (SPEC over
HTML), so `DemoTimeline` schedules a release 250 ms after every press: 900→1150, 2100→2350,
2900→3150, 3800→4050, 4800→5050. Loop totals (7400 ms / 6600 ms) and every scene cue are the
spec's values.

The timeline is owned by `OnboardingWindowController` and injected into both `OnboardingView`
(which drives the key badges in the subtitle and the legend) and `DesktopScene`. The scaffolding
kept it private to `DesktopScene`, which the aux-row badges could not reach.

## Quick Paste panel anchor

The panel points at the caret via `CaretAnchorProbe`, a zero-width probe placed immediately before
the inserted run in `NotesWindowMock` — not the caret rectangle itself. The probe reports the same
position but does not move when the demo pastes text into the line, so the panel never slides
sideways at the paste cue. `panelAnchor` is `caret.midX − 32`, `caret.maxY + 8` as specified.

## Screen Recording is requested without opening System Settings

SPEC §6 says the Screen Recording "Allow" action should call `CGRequestScreenCaptureAccess()` *and*
open `…?Privacy_ScreenCapture`. Opening that pane is what makes macOS demand a restart: flipping
the toggle behind a running app raises the system's "will not be able to record … Quit & Reopen"
alert. `CGRequestScreenCaptureAccess()` on its own does not — its prompt grants the running process.

So the button asks first and only falls back to System Settings when `CGRequestScreenCaptureAccess()`
returns false, which means macOS declined to prompt because the answer is already on record. In that
one case `OnboardingModel.screenRecordingNeedsRelaunch` flips and the waiting row swaps its Allow
button for **Relaunch ClipStack** (`Permissions.relaunch()`), so the restart macOS demands is one
click instead of a dead end. Accessibility is unchanged: it grants live, so it still prompts and
opens its pane exactly as specified.

This adds two keys the copy deck does not have, since the deck predates the affordance:
`screen.relaunch` and `screen.relaunchNote`. Every other string is verbatim from the deck.

The step itself stays where the spec puts it — six steps, six indicators — and stays optional:
Continue is never blocked, and area capture also triggers the system prompt on its own the first
time `⇧⌘S` runs `/usr/sbin/screencapture`, so a user who skips here is not stranded.

## Launch ordering

`AppDelegate` presents the first-run window from `DispatchQueue.main.async`, immediately after the
status item is configured and before `ScreenshotWatcher` / `DownloadsWatcher` start. Two reasons:

- SwiftUI delivers `applicationDidFinishLaunching` from inside `applicationWillFinishLaunching`;
  a window ordered front there is not reliably shown.
- The watchers' first filesystem access can block on a system folder-access prompt, so the
  first-run window has to be queued ahead of them.

## Existing installs

`hasCompletedOnboarding` has never been written before this change, so the first launch after
updating to this version shows onboarding to existing users as well as new ones. That follows
SPEC §6 (`hasCompletedOnboarding == false` ⇒ present); there is no install marker that could
distinguish the two cases retroactively.

## Strings

All user-facing copy comes verbatim from `Resources/Onboarding.strings`, shipped at
`ClipStack/en.lproj/Onboarding.strings` and read through the `Onboarding` table
(`Text(onboarding:)`). Labels the copy deck does not cover because they belong to the simulated
software inside the laptop — the menu titles, "Search…", "Select", "Clear All", "Quit", the System
Settings pane titles and descriptions — are drawn verbatim from the artboard and are not
localizable strings of this app.
