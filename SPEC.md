# Ttemp — Complete Reproduction Specification

**Version 1.0 — 2026-08-02**

Ttemp is a resident (always-running) scratchpad application: pressing the **left and
right Shift keys together** summons a small plain-text window from anywhere; closing a
window copies its contents to the clipboard; a window can alternatively hold exactly one
image; window contents and layout survive application restarts.

This document is a **self-contained, normative specification** for reproducing Ttemp as a
native application on the implementer's own operating system (macOS, Windows, or Linux).
It was derived from a full audit of the reference implementation (Ttemp v0.1.0, macOS,
Swift/AppKit) — every behavior, constant, and edge case below reflects shipped, verified
behavior, not aspiration.

---

## 0. How to Read This Document

### 0.1 Conformance language

The key words **MUST**, **MUST NOT**, **REQUIRED**, **SHALL**, **SHOULD**, **SHOULD
NOT**, **RECOMMENDED**, **MAY**, and **OPTIONAL** are to be interpreted as described in
RFC 2119.

- **MUST** requirements define conformance. An implementation that violates a MUST is
  not a reproduction of Ttemp, regardless of how it looks.
- **SHOULD** requirements may be waived only with a reason recorded in `DECISIONS.md`
  (§1.4) and, when user-visible, with the user's consent.
- Requirements marked **[macOS]**, **[Windows]**, **[Linux]**, **[Linux/X11]**,
  **[Linux/Wayland]** apply only on those platforms.

### 0.2 Precedence

If two statements appear to conflict:

1. Numeric constants in §16 and UI strings in §17 win over prose.
2. The more specific statement (edge-case table) wins over the general statement.
3. If a genuine contradiction remains, the implementing agent MUST ask the user rather
   than pick silently.

### 0.3 Terminology

| Term | Meaning |
|---|---|
| **note window** | One floating scratchpad window (text mode or image mode). |
| **empty** | A text-mode window whose text is zero-length after trimming leading/trailing whitespace and newlines. Image-mode windows are **never** empty. |
| **pinned** | The per-window "keep on top" (always-on-top) flag. |
| **PRIMARY modifier** | The platform's main shortcut modifier: `⌘ Command` on macOS; `Ctrl` on Windows and Linux. |
| **LOCAL modifier** | The user-configurable modifier for per-window font-size operations (§10.3). |
| **tray icon** | macOS menu-bar status item / Windows notification-area icon / Linux StatusNotifierItem–AppIndicator. |
| **visible frame** | The usable area of a display (excluding menu bar / taskbar / dock / panels). |
| **pt** | Logical points (device-independent pixels). All sizes in this spec are logical, not physical pixels. |

---

## 1. Agent Execution Protocol (NORMATIVE)

This section governs **how the implementing coding agent must work**, not just what it
must build. It is as binding as the functional sections.

### 1.1 Phase 0 — the mandatory "Grill-Me" phase

The agent **MUST NOT write any application code, scaffolding, or project files before
completing Phase 0.** Phase 0 exists to surface, as fast as possible, every gap between
this spec and the environment the agent is actually running in, and to force the user to
decide on those gaps up front instead of discovering them mid-build.

Phase 0 MUST be the **first action of the engagement**: the gap report and question
batch of Step 3 MUST reach the user as early as possible — in the agent's first
response whenever the environment probe allows it. Speed matters: the entire point is
that the user decides the gaps before any effort is sunk.

Phase 0 consists of four steps, executed in order:

**Step 1 — Environment fingerprint.** The agent MUST determine and record:

- OS and version; CPU architecture.
- [Linux] Display server (X11 or Wayland — check `$XDG_SESSION_TYPE` and
  `$WAYLAND_DISPLAY`), desktop environment, and whether a StatusNotifierItem host is
  present.
- Available toolchains, package managers, and GUI frameworks (e.g. Xcode + Swift;
  .NET / MSVC / Rust; GTK / Qt dev packages).
- Whether automated tests can be run headlessly in this environment.

**Step 2 — Capability probe.** For every row of the Capability Matrix (§3.2), the agent
MUST classify the environment as **available / degraded / unavailable**, citing evidence
(a command output, an API check, or a web-verified fact — see §1.2).

**Step 3 — Gap report + batched interrogation.** The agent MUST present the user with a
single, compact report containing:

1. The environment fingerprint.
2. A gap table: capability → status → the fallback this spec prescribes (§3.4).
3. **One batch of questions** — all questions at once, each with a recommended default,
   so the user can answer in a single pass. The following questions are REQUIRED
   whenever applicable (skip only those that the environment makes moot):

   | # | Question | When required |
   |---|---|---|
   | Q1 | Confirm target OS / display server detected in Step 1. | always |
   | Q2 | Technology stack (agent recommends one per §3.5; user confirms). | always |
   | Q3 | Global-trigger fallback choice (§3.4 ladder). | trigger capability ≠ available |
   | Q4 | LOCAL-modifier mapping on this platform (§3.3). | non-macOS |
   | Q5 | Export-format set if HEIC encoding is unavailable (§9.6). | HEIC probe failed |
   | Q6 | Autostart mechanism to use (§4.4). | more than one viable option |
   | Q7 | Packaging/distribution target (§21) — or defer to a later phase. | always |

   The agent MAY add further questions but MUST keep the batch minimal and decision-
   oriented — this phase is an interrogation, not a survey.

**Step 4 — Freeze decisions.** The agent MUST record every answer and every waived
SHOULD in a `DECISIONS.md` file at the repository root before writing code. Each entry:
date, decision, alternatives considered, and the spec section affected.

### 1.2 Web-search obligation

If the agent has any form of web access, it **MUST use it during Phase 0 and whenever a
platform behavior is in doubt** — API availability, permission flows, toolkit
capabilities, packaging requirements — rather than relying on training-data memory.
Volatile facts (e.g. "does this compositor implement the GlobalShortcuts portal?",
"current notarization requirements") MUST be verified, and the verification noted in
`DECISIONS.md`. If the agent has no web access, it MUST say so in the Phase 0 report and
flag which decisions are riskier as a result.

### 1.3 Silent degradation is forbidden

If any MUST requirement cannot be satisfied in the target environment, the agent MUST
stop and present the options from the degradation ladder (§3.4) — it MUST NOT silently
ship a weaker behavior. SHOULD-level deviations require a `DECISIONS.md` entry.

### 1.4 Phased delivery with user checkpoints

The agent MUST implement in the following order and MUST pause for user verification at
the end of Phase 1 (the trigger's false-positive rate and the auto-dismiss feel can only
be judged by a human at a keyboard):

| Phase | Contents | Gate |
|---|---|---|
| 0 | Grill-Me (§1.1) | user answers received, `DECISIONS.md` written |
| 1 | Skeleton: tray icon, trigger, window create/type/close-to-clipboard, empty auto-dismiss, fades | **user MUST confirm**: no false fires while typing; placement comfortable; auto-dismiss not annoying; window reliably takes keyboard focus when summoned over another app |
| 2 | Persistence & restore, autostart, single-instance | automated tests pass |
| 3 | Image mode (paste, drop, sizing, GIF hover, save/copy/delete) | automated tests pass |
| 4 | Font-size model, pinning, find/replace, context menus, window list, settings, onboarding, permission monitoring | automated tests pass + manual checklist §19.3 |
| 5 | Packaging (per Q7) | user acceptance |

### 1.5 Code architecture requirement

All decision logic listed in §19.1 (trigger state machine, sanitizer, paste decision,
font model, placement, restore-clamp, image sizing, export naming, state store) **MUST
be implemented as pure, UI-framework-independent modules** so the acceptance tests in
§19 can run headlessly. UI classes MUST be thin shells over these modules. This mirrors
the reference implementation and is what makes the acceptance suite possible.

---

## 2. Product Overview (informative)

- Resident background app with a tray icon; **no Dock/taskbar presence**, no main window.
- **Left Shift + Right Shift, pressed together and released with nothing else touched**,
  spawns a plain-text note window centered slightly above the middle of the display
  under the mouse cursor, ready for immediate typing.
- Closing a window (close button / PRIMARY+W / Escape) copies its content to the
  clipboard and returns focus to the app the user was in.
- Losing focus while empty silently destroys the window; losing focus with content does
  nothing.
- An empty window accepts exactly one pasted/dropped image and becomes an image shelf.
- Everything open is persisted (debounced 1 s) and restored on next launch.
- Philosophy: zero friction, zero data mangling ("what you put in is what you get out"),
  zero notifications, no destructive surprises.

---

## 3. Platform Abstraction

### 3.1 Abstract capabilities

The functional sections are written against these capabilities:

| ID | Capability |
|---|---|
| `CAP-TRIGGER` | Observe global key-down, left/right-Shift state, other-modifier keystrokes, and mouse-button-down events system-wide, read-only, while any app is frontmost (including full-screen apps). |
| `CAP-TRAY` | Tray icon with distinct left-click and right-click behaviors. |
| `CAP-CLIP` | Read/write clipboard with multiple representations (plain text; image bytes; file lists). |
| `CAP-AUTOSTART` | Register/unregister launch-at-login, queryable. |
| `CAP-DESKTOP` | Windows stay on the virtual desktop they were opened on. |
| `CAP-IME` | Query whether the focused text control has an active IME composition (marked text). |
| `CAP-WINDOW` | Borderless-look resizable windows, always-on-top toggle, activation control, per-display metrics, window-level Z-order inspection. |

### 3.2 Capability Matrix (normative mapping)

| Capability | macOS | Windows | Linux/X11 | Linux/Wayland |
|---|---|---|---|---|
| `CAP-TRIGGER` | `CGEventTap` (listen-only, session tap) — **requires Input Monitoring permission**; left Shift keycode 56, right 60; device-dependent flag bits L=`0x2` R=`0x4` | Low-level hooks `WH_KEYBOARD_LL` (distinguish `VK_LSHIFT`/`VK_RSHIFT`) + `WH_MOUSE_LL`; no permission needed (see §20 for elevated-window caveat) | XInput2 raw events or XRecord; no permission needed | **Not generally possible.** Use degradation ladder §3.4 |
| `CAP-TRAY` | `NSStatusItem`, left/right click split (§11.3) | `Shell_NotifyIcon`; left click = action, right click = menu | StatusNotifierItem/AppIndicator — many hosts only support a menu; use fallback §3.4-B | same as X11 |
| `CAP-CLIP` | `NSPasteboard` types (`public.utf8-plain-text`, `public.png`, `com.compuserve.gif`, …, `fileURL`) | `CF_UNICODETEXT`, `PNG`/`CF_DIB(V5)`, `CF_HDROP` | targets `text/plain;charset=utf-8`, `image/png` (+original MIME), `text/uri-list` | same, via compositor clipboard |
| `CAP-AUTOSTART` | `SMAppService.mainApp` | `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` value **or** Startup-folder shortcut | XDG autostart `.desktop` in `~/.config/autostart/` | same |
| `CAP-DESKTOP` | Do **not** set `.canJoinAllSpaces`; windows stay in their Space. Restart-restore lands on the current Space (OS has no public per-Space placement API — accepted limitation) | Default behavior (windows belong to one virtual desktop) | Default WM behavior; do not set sticky/all-desktops hints | same |
| `CAP-IME` | `NSTextView.hasMarkedText()` | TSF/IMM composition state, or the toolkit's preedit signal | toolkit preedit state (GTK `preedit-changed` / Qt `inputMethodQuery`) | same |
| `CAP-WINDOW` | `NSWindow` APIs; Z-order via `CGWindowListCopyWindowInfo` | Win32/toolkit APIs; Z-order via `EnumWindows`/`GetWindow` | EWMH (`_NET_CLIENT_LIST_STACKING`, `_NET_WM_STATE_ABOVE`) | compositor-dependent; see notes in §7.3 |

### 3.3 Modifier mapping

| Role | macOS | Windows / Linux |
|---|---|---|
| PRIMARY (global font ops, Close = PRIMARY+W, Find = PRIMARY+F, Replace = PRIMARY+Alt/⌥+F, undo/redo/cut/copy/paste/select-all) | `⌘` | `Ctrl` |
| LOCAL — user choice of two options; **default = first** | `Control (⌃)` (default) / `Option (⌥)` | `Alt` (default) / `Super` — confirm in Phase 0 (Q4); if `Super` is heavily bound by the DE, the agent MUST propose an alternative second option rather than shipping a dead setting |

The two LOCAL choices MUST be distinct from PRIMARY. All shortcut matching uses the
key's unmodified character (§10.2) and **ignores Shift** (JIS keyboards produce `+` as
Shift+`;`).

### 3.4 Degradation ladder (normative fallbacks)

**A. `CAP-TRIGGER` unavailable or degraded (Wayland; or macOS permission denied):**

1. The tray-icon "新規ウィンドウ" menu item (§11.3) is the permanent, always-working
   path and MUST exist on every platform regardless.
2. [Linux/Wayland] If the `org.freedesktop.portal.GlobalShortcuts` XDG portal is
   available, the app MUST offer registration of a conventional global shortcut
   (recommended default: `Ctrl+Alt+Space`) that triggers new-window creation. The
   left/right-Shift chord itself is **not reproducible** via the portal; this is a
   degraded conformance level and MUST be reported to the user in Phase 0 (Q3).
3. [Linux/Wayland] Reading `/dev/input` via the `input` group (evdev) MAY be offered as
   an opt-in advanced mode enabling the true chord; the agent MUST explain the security
   implications and MUST NOT enable it without explicit user consent.
4. [macOS] While Input Monitoring is not granted, the chord simply does not fire; the
   tray icon shows the warning state (§13.3) and everything else keeps working.

**B. `CAP-TRAY` cannot split left/right click (common on Linux):** a single menu MUST be
used for both buttons, with **「すべてのウィンドウを前面に」 as the first item**,
followed by the normal right-click menu contents (§11.3). The left-click-activates
behavior is then reachable in one extra click.

**C. `CAP-IME` composition state unqueryable:** Escape MUST be delivered to the input
method first whenever an input method is active; only if the toolkit reports the event
as unconsumed may it close the window. If even that is impossible, Escape-to-close MAY
be limited to "no composition possible" states — record in `DECISIONS.md`.

**D. HEIC encoding unavailable (typical on Windows/Linux):** omit HEIC from the export
menu (§9.6, Q5). Decoding support follows the platform image library; formats that
cannot be decoded are rejected like any unreadable image (§9.4).

### 3.5 Technology stack requirements

The implementation MUST be a **native desktop application for the target OS**, chosen
and confirmed in Phase 0 (Q2). Requirements the chosen stack must satisfy:

- Frameless-look resizable windows with custom drag regions and always-on-top control.
- A multiline plain-text editing control with undo/redo and either a built-in
  find/replace bar (macOS `NSTextView`) or the ability to build a minimal find/replace
  bar (§8.4).
- Tray icon support per §3.2.
- Reasonable idle footprint: this is a resident app. Electron-class runtimes SHOULD be
  avoided; if the user explicitly prefers one, record it in `DECISIONS.md`.
- CLI-only build (no IDE interaction required): one documented command MUST produce the
  app; one MUST run the tests. [macOS] The reference uses XcodeGen + `xcodebuild`; any
  equivalent is fine.

Recommended defaults the agent SHOULD propose in Q2: macOS → Swift + AppKit; Windows →
C# / WPF or WinUI (or Rust + native crates); Linux → GTK4 or Qt6 (C, Rust, or C++).

### 3.6 File locations

| Item | macOS | Windows | Linux |
|---|---|---|---|
| State dir (`state.json`, `Images/`) | `~/Library/Application Support/Ttemp/` | `%APPDATA%\Ttemp\` | `$XDG_DATA_HOME/Ttemp/` (default `~/.local/share/Ttemp/`) |
| Settings (§12.4) — MUST be stored separately from state | `UserDefaults` (`com.am921.ttemp`) | registry key `HKCU\Software\Ttemp` or `settings.json` beside state — but a **separate file** | `$XDG_CONFIG_HOME/Ttemp/settings.json` (default `~/.config/Ttemp/`) |

Separation rationale (normative intent): corruption of `state.json` MUST NOT take the
settings down with it, and vice versa.

App identifier: `com.am921.ttemp` (bundle ID / AppUserModelID / D-Bus-style name as the
platform requires). Product name: **Ttemp**.

---

## 4. Application Form & Lifecycle

| # | Requirement |
|---|---|
| 4.1 | The app MUST NOT appear in the Dock / taskbar / app-switcher as a regular app ([macOS] `LSUIElement=true` + accessory activation policy). Note windows SHOULD likewise be absent from the taskbar and app switcher ([Windows] tool-window style; [Linux] skip-taskbar hint) — the design intentionally provides exactly two recall paths, both via the tray (§6.4); if the platform makes switcher exclusion infeasible for focusable windows, record the deviation in `DECISIONS.md`. The tray icon MUST be shown at all times. |
| 4.2 | The process MUST stay alive with zero windows open. |
| 4.3 | Quit MUST be available **only** from the tray menu item 「Ttemp を終了」. There MUST be **no quit keyboard shortcut** (no ⌘Q / Ctrl+Q). Rationale: close-window (= copy to clipboard) and quit (= save, no copy) differ radically; adjacent-key accidents are unacceptable. Platform-standard *window*-close gestures on a note window ([Windows] Alt+F4) are the ordinary close path of §7 (copy) — they MUST close only that window, never the app. |
| 4.4 | Launch at login: default **ON**, surfaced explicitly as a pre-checked checkbox on the onboarding screen (§13.1), togglable in Settings at any time. The stored truth is the OS registration itself, not a settings key ([macOS] `SMAppService.mainApp.status`). If registration fails, the UI MUST snap back to the real state. |
| 4.5 | Single instance: a second instance MUST detect the first, signal it to perform "bring all windows to front" (§6.4), and exit immediately. [macOS] running-app scan by bundle ID + distributed notification `com.am921.ttemp.bringAllToFront`. [Windows] named mutex + named pipe / custom window message. [Linux] abstract socket or D-Bus name ownership. |
| 4.6 | On quit: stop input monitoring, **flush pending state saves first, then** close windows without copying (§7.2). Order matters — closing first would snapshot an empty state. |

---

## 5. Global Trigger — Left/Right Shift Chord

### 5.1 Firing rule (release-fire model)

A **sequence** begins when either Shift is pressed while no Shift was held. A new note
window is created **iff all** of the following hold:

1. During the sequence, left Shift and right Shift were **both in the pressed state**
   at some point (not necessarily pressed simultaneously — overlap suffices).
2. From the **start of the sequence** until all Shifts are released, **no ordinary key**
   was pressed.
3. In the same span, **no non-Shift modifier was keystroked** — every modifier key
   observable on the platform counts (⌘/Ctrl, Alt/⌥, Control, Win/Super, CapsLock,
   Fn, …).
4. In the same span, **no mouse button was pressed** (left, right, or other).
5. **All Shifts were released.** Firing happens at the final release.

### 5.2 Fine rules

- Violating 2–4 **invalidates** the sequence; no re-evaluation happens until **all**
  Shifts are released (then the next press starts a fresh sequence).
- The invalidation window starting at the *first* Shift press (not at both-held) is
  deliberate: it kills the "type with left Shift held → brush right Shift → release
  both" false-fire path. Side effect (accepted): typing Shift+A and then chording
  without fully releasing does not fire.
- Condition 3 is judged by **keystroke events (state transitions)**, never by the
  modifier *state* mask: CapsLock-lock being active must not permanently block firing.
- The trigger MUST work regardless of the frontmost app, including over full-screen
  apps.
- Monitoring MUST be read-only (never consume or alter events).
- Inputs arriving while no Shift is held (idle) have no effect on later sequences.

### 5.3 Reference state machine (normative pseudocode)

```
phase ∈ {idle, tracking, invalidated};  sawLeft, sawRight: Bool
inputs: shiftStateChanged(left,right) | keyPressed | otherModifierPressed | mousePressed
reset(): phase=idle; sawLeft=sawRight=false

handle(keyPressed | otherModifierPressed | mousePressed):
    if phase == tracking: phase = invalidated
    return NO_FIRE

handle(shiftStateChanged(l, r)):
    any = l or r
    idle:        if any { phase=tracking; sawLeft=l; sawRight=r }; return NO_FIRE
    tracking:    sawLeft |= l; sawRight |= r
                 if any: return NO_FIRE
                 fired = sawLeft and sawRight; reset(); return fired
    invalidated: if !any: reset(); return NO_FIRE
```

This state machine MUST exist as a pure module fed by a thin platform event source, and
MUST pass the §19.2-A cases verbatim.

### 5.4 Platform event source rules

- [macOS] `CGEventTap`, `.listenOnly`, session tap, mask = keyDown | flagsChanged |
  left/right/otherMouseDown. On `tapDisabledByTimeout` / `tapDisabledByUserInput` the
  tap MUST be re-enabled immediately and the detector reset ("hotkey suddenly dies one
  day" prevention). Left/right discrimination: prefer the device-dependent flag bits
  (L=`0x00000002`, R=`0x00000004`) read on every `flagsChanged`; keycodes 56/60 identify
  which physical key moved. `flagsChanged` events for non-Shift keycodes feed
  `otherModifierPressed`.
- [Windows] `WH_KEYBOARD_LL` + `WH_MOUSE_LL`. Track `VK_LSHIFT`/`VK_RSHIFT` down/up into
  a (left,right) state; other modifier VKs feed `otherModifierPressed`; other keys feed
  `keyPressed`; any `WM_*BUTTONDOWN` feeds `mousePressed`. Hook callbacks MUST return
  fast and MUST NOT block (see also §5.5).
- [Linux/X11] XInput2 raw key/button events (`XIRawKeyPress`, `XIRawButtonPress`);
  distinguish `Shift_L`/`Shift_R` keysyms.
- Equivalent-generality rule: whatever the mechanism, ordinary keys, modifier
  keystrokes, and mouse-downs MUST all be observable, or the trigger is "degraded"
  (§3.4-A).

### 5.5 Dispatch

Window creation MUST NOT run inside the event callback/hook itself; post to the main
loop (the reference defers with an async dispatch specifically so the tap is never
flagged slow). Firing latency from final Shift release to visible window SHOULD be
under 200 ms.

---

## 6. Note Windows

### 6.1 Creation & activation

- On chord fire or tray "新規ウィンドウ": the app MUST activate itself and make the new
  window the key/focused window so typing works instantly — even when another app was
  frontmost. [macOS] cooperative activation (`NSApp.activate()`) is **not sufficient**
  on macOS 14+; the reference uses `NSApp.activate(ignoringOtherApps: true)` plus
  `orderFrontRegardless()` before `makeKeyAndOrderFront`. The implementation MUST
  achieve reliable focus steal here; this is explicitly checked at the Phase 1 gate.
- Focus lands in the text view; no click required.
- This activation applies **only to user-initiated creation**. Restore at launch MUST
  NOT activate the app or steal focus (§14.5).
- The new window's pinned state comes from the 「新規ウィンドウの最前面固定」 setting
  (§12.2); restored windows use their saved flag instead.

### 6.2 Focus-out behavior (auto-dismiss)

Evaluated the moment a note window **ceases to be the key/focused window** — including
focus moving to *another Ttemp window*, not just to other apps:

| Window state at focus-out | Behavior |
|---|---|
| empty (§0.3), not pinned | destroy silently: fade out 0.12 s, **no clipboard change, no focus yielding** |
| empty, pinned, pin-mode = 「固定する（空になったら消す）」 | destroy silently (the one exception where pinned+empty dies) — the mode is read from the **current** setting at evaluation time, so it also governs hand-pinned windows |
| empty, pinned, any other mode | keep |
| has text | keep; nothing happens (no copy — copying is exclusively a close-time behavior) |
| image mode | keep (never empty) |

A window already executing its close path MUST NOT be double-processed by this rule
(guard with an `isClosing` flag).

### 6.3 Window level, pinning, virtual desktops

- Default: normal window level (other apps can cover it).
- 「最前面に固定」 toggles always-on-top per window, from the context menu (§11.1,
  §11.2) or by clicking the pin indicator. The flag is persisted.
- While pinned, a small **pin icon** MUST be shown at the right end of the (transparent)
  title-bar area at all times; clicking it unpins. Reference: system "pin" glyph in a
  28×22 pt button; tooltip 「最前面に固定中（クリックで解除）」.
- Windows stay on the virtual desktop where they were opened (§3.2 `CAP-DESKTOP`);
  restart-restore lands on the current desktop (accepted platform limitation).

### 6.4 Recalling hidden windows

Because there is no Dock/taskbar presence:

- **Tray left click** → activate app and bring **all** note windows to front (even
  unpinned ones temporarily rise); the most recently created one becomes key.
- **Tray right click** → menu with the per-window list (§11.3); clicking an entry
  focuses that window.
- The single-instance signal (§4.5) triggers the same bring-all-to-front.

### 6.5 Appearance & chrome

| Item | Requirement |
|---|---|
| Title bar | Visually absent: transparent title-bar / hidden title text; content extends full-size. No window title string is ever shown. |
| Window buttons | Close only. Minimize and zoom/maximize MUST be disabled or absent (a minimized window would be unrecoverable without a Dock icon). |
| Close paths | close button / **PRIMARY+W** / **Escape** (Escape exceptions §6.6) / the platform's standard close gesture ([Windows] Alt+F4 → same copy path, §4.3). |
| Resize | yes, by edges/corners; minimum content size **200×150 pt** at all times. |
| Move | by the title-bar region **and by dragging the window background**. |
| Background | opaque; follows the system light/dark theme automatically (standard text-background color). Never translucent. |
| Content padding | 12 pt inset on all sides of the text (reference: text container inset 12×12, zero line-fragment padding). |
| Corner rounding | platform standard. |
| Inactive look | unchanged — do NOT dim unfocused windows (they must stay readable). |
| Shadows | platform standard. |
| Native tabbing | disabled. |

### 6.6 Escape semantics

In order:

1. If an IME composition (marked text) is active → Escape goes to the IME; the window
   MUST NOT close.
2. Else if the find bar is visible → hide the find bar only, refocus the text view; the
   window stays (a second Escape then closes it).
3. Else → close the window (normal close path, §7).

Image-mode windows: Escape closes (no IME/find bar exists there).

### 6.7 Placement & size of new windows

- **Display**: the one containing the mouse cursor (fallback: primary).
- **Base position**: horizontally centered in that display's visible frame; vertically
  centered then shifted **upward by 8% of the visible-frame height** ("center, slightly
  above").
- **Default size**: always **480×320 pt**. A user's manual resize is NOT inherited by
  later new windows.
- **Cascade**: if the candidate origin collides with an existing note window's origin
  (both axes within < 1 pt), step **+24 pt right and +24 pt down**, repeatedly. If the
  candidate would overflow the right or bottom edge, wrap to the top-left corner inset
  by `24 + 8×wrapCount` pt on both axes, where `wrapCount` is 1 on the first wrap and
  increments per wrap (the growing inset prevents cycling over the same spots). Hard
  iteration cap: 200. The final origin is clamped into the visible frame.
- The placement function MUST be pure ((size, visibleFrame, occupiedOrigins) → frame)
  and pass §19.2-E.

### 6.8 Animations

| Event | Animation |
|---|---|
| new window appears (created or restored) | fade-in **0.12 s** (opacity only — no scaling) |
| empty auto-dismiss | fade-out 0.12 s |
| close (button / PRIMARY+W / Escape) | fade-out 0.12 s |
| reject feedback ("shake") | horizontal shake: x-offsets `0 → −8 → +8 → −4.8 → +4.8 → 0` pt over **0.24 s**, ease-out |

Rationale: instant disappearance reads as a bug; > 0.2 s feels sluggish.

### 6.9 Window count

No upper limit. (Empty ones self-destruct; only deliberate content accumulates.)

---

## 7. Close → Clipboard

### 7.1 Core rule

Closing a note window (any close path in §6.5) copies its content to the system
clipboard: plain text for text mode (the exact buffer contents, LF newlines), image data
for image mode (§9.5's copy behavior).

### 7.2 Edge cases (normative table)

| Case | Behavior |
|---|---|
| closing an **empty** window | clipboard MUST NOT be touched at all (overwriting with "" would destroy the user's previous copy) |
| quitting the app | **no copy** for any window; quit = save-and-restore-later, not close |
| focus-out (window survives) | no copy — copying happens **only** on close |
| several windows closed in sequence | last close wins; no merging or concatenation |
| feedback | **none** — no sound, no notification, no toast; the fade-out is the only cue (this fires dozens of times a day) |

### 7.3 Focus hand-off after close

**Before the fade-out even begins** (and therefore well before the platform close call
runs), the app MUST identify the application owning the next frontmost normal window in
global Z-order below Ttemp's and activate it. Requirements distilled from the reference:

- Determined **at close time** from the actual current Z-order — NOT from a remembered
  "previous app" (memory goes stale when the user has been switching around).
- Activating **before** destroying avoids the OS handing focus to an arbitrary window
  for a frame (flicker) after the key window dies.
- Do not hide the whole app (pinned windows must stay visible), and note windows of
  Ttemp itself are skipped — otherwise a leftover pinned note would receive focus and a
  subsequent PRIMARY+V would paste into the wrong note.
- Skip non-normal layers (menus/docks/overlays), zero-alpha windows, and non-regular
  apps. If no target exists, do nothing.
- Empty-window auto-dismiss (§6.2) performs **no** focus hand-off.
- [macOS] reference: walk `CGWindowListCopyWindowInfo(.optionOnScreenOnly,
  .excludeDesktopElements)` front-to-back; first window with `layer == 0`, `alpha > 0`,
  owner ≠ self, owner is a regular running app → `activate()`.
- [Windows] walk the top-level window Z-order (`GetTopWindow`/`GetWindow(GW_HWNDNEXT)`),
  skip own process, invisible/cloaked/tool windows → `SetForegroundWindow` (subject to
  foreground rights; the app being foreground at close time satisfies them).
- [Linux] EWMH `_NET_CLIENT_LIST_STACKING` where available; on Wayland this is
  compositor-controlled — if unimplementable, rely on the compositor's own focus return
  and record the limitation (SHOULD-level on Wayland only; MUST elsewhere).

---

## 8. Text Mode

### 8.1 Input & display

| Item | Requirement |
|---|---|
| Font | system UI font; effective size per font model §10 (base default 14 pt) |
| Wrapping | soft-wrap at window width; **no horizontal scrolling**; vertical scrollbar only when needed |
| Scrollbar layout | the scrollbar gutter MUST be reserved permanently in classic-scrollbar environments so text never re-wraps when the bar appears (overlay-scrollbar environments unaffected) |
| Length limit | none |
| Enter | always inserts a newline |
| Tab | inserts a literal TAB character (never focus traversal — there is nothing to traverse to) |
| Undo/Redo | PRIMARY+Z / PRIMARY+Shift+Z; history is discarded when the window closes |
| Find / Replace | PRIMARY+F opens find; PRIMARY+Alt+F opens replace (§8.4) |
| Colors | standard text color / caret color, theme-following |

### 8.2 Automatic text mangling — ALL OFF

Every OS/toolkit auto-correction MUST be disabled: smart quotes, smart dashes,
auto-capitalization, spell auto-correction, OS text replacement, spell-check underlines,
grammar check, **automatic link detection** (typing a URL must NOT create a link
attribute), data detectors (dates/addresses). The buffer MUST be strictly plain text
(rich text off, no image attachments importable into the text).

Rationale (normative intent): "what you put in is what you get out" — a smart quote can
break pasted code. Note the link-detection case: §8.3 strips link attributes on paste;
leaving input-side auto-linking on would violate the same rule from the other direction.

### 8.3 Paste sanitization (text)

All pasted text is flattened to plain text:

- **Strip**: every text attribute (font/size/color/bold/italic/underline/background),
  paragraph styles, link attributes (**keep the URL string itself**), embedded
  images/attachments inside rich content (keep only the text).
- **Keep**: TAB characters, full-width spaces, emoji, all Unicode, consecutive blank
  lines.
- **Normalize**: line endings to **LF** (`CRLF → LF`, then lone `CR → LF`).
- If the clipboard has only rich representations (RTF/HTML) and no plain-text type, the
  plain string MUST still be extracted from the rich representation.
- Insertion replaces the current selection, keeps the caret after the inserted text,
  and re-applies the window's uniform font/color attributes to the whole buffer.

The sanitizer (`sanitize`, `isEffectivelyEmpty`) MUST be a pure module passing §19.2-B.

### 8.4 Find & replace

A find bar with incremental search and a replace mode MUST be available (the reference
uses the toolkit's built-in bar). Escape interaction per §6.6. Closing a window with
the find bar open just closes everything together — no special casing. On toolkits
without a built-in bar, implement a minimal inline bar: find field, next/previous,
replace field, replace / replace-all. Case-insensitive default matching SHOULD follow
the toolkit's convention.

### 8.5 Paste-content decision order

When the clipboard/drop contains multiple representations, decide in this exact order:

1. **File URLs present** → if the list contains an image file (by extension/UTI,
   case-insensitive), take the **first image file** (→ image path, §9); otherwise
   **reject** (§9.4). When file URLs are present, any raster image data on the
   clipboard MUST be ignored (file managers put icon images there; a copied PDF must
   not paste as its icon).
2. **Image data present AND no plain-text type present** → image path. The plain-text
   check is strictly "a plain-text representation exists", NOT "HTML exists" — a
   browser's "copy image" (image + HTML, no plain text) must land here.
3. Otherwise, if text is retrievable → **insert as sanitized plain text**.
4. Nothing usable → do nothing (no feedback).

"Image + plain text" mixtures therefore always favor text (mixed pastes almost always
mean prose; silently entering image mode and losing typability is the worse accident).

Reading image data off the clipboard MUST preserve the **original bytes and format**
(never round-trip through a decoded bitmap). [macOS] probe types in the order GIF, PNG,
JPEG, HEIC, TIFF (TIFF last — macOS synthesizes it). Other platforms: prefer the
original/most-specific format (e.g. `PNG` clipboard format / `image/png` or the source
MIME) over synthesized bitmaps (`CF_DIB`).

The decision (`decide`) and the mode-transition resolution (`resolve`, §9.1) MUST be
pure modules passing §19.2-C.

---

## 9. Image Mode

A note window holds **either** text **or** exactly one image.

### 9.1 Mode transitions

| Situation | Behavior |
|---|---|
| image pasted/dropped into an **empty** window | window becomes image mode; text input disabled |
| image pasted/dropped into a window **with text** | **reject** — shake (§6.8), text untouched |
| image pasted/dropped in image mode | **replace** the image (the only way to keep 1 window = 1 image) |
| text pasted in image mode | **reject** — shake; delete the image first if text is wanted |
| context-menu 「画像を削除」 | back to **empty text mode**; window survives, typing works immediately; window size is NOT restored (§9.3); font-size offset preserved (§10.4); it is now empty, so focus-out will dismiss it |

No confirmation dialogs anywhere — the "images only enter empty windows" one-liner rule
plus visible shake feedback replaces them.

### 9.2 Accepted inputs & formats

- Paste (PRIMARY+V) and drag & drop (image files, browser images) — same acceptance
  rules.
- File-manager copy of an image file → resolved via the file URL and loaded **from the
  file's bytes** (never treated as a path string, never decoded-re-encoded).
- Multiple files dropped at once → only the **first image file**; everything else
  ignored.
- Non-image files (PDF, .txt, .zip, …) → reject with shake. Scope is deliberately
  "plain text + one image", nothing else.
- Formats: everything the platform image stack decodes (PNG/JPEG/GIF/TIFF/WebP; HEIC
  where supported). A file whose bytes fail to decode MUST be rejected with shake (and
  any partially-stored file cleaned up).
- Unknown extension on incoming data: sniff the real format from the bytes; if
  undeterminable, store with extension `dat` (which suppresses the 「元の形式のまま」
  export entry, §9.6).

### 9.3 Display & window sizing

- On accepting an image, the window resizes to fit it:
  - Size math uses the image's **logical point size** (DPI metadata respected), never
    raw pixels — a 2× screenshot must not open a double-size window.
  - `scale = min(1, 0.6·W_vis / w_img, 0.6·H_vis / h_img)` where (W_vis, H_vis) is the
    current display's visible frame — i.e. cap at **60% of the visible frame**, never
    upscale.
  - Per-axis floor: content size at least **200×150 pt** (window must stay grabbable);
    a small or extreme-aspect image sits centered (letterboxed) in that box.
  - The resized window keeps its center, clamped into the visible frame.
- After manual resize: the image scales down proportionally to fit, letterboxed, never
  cropped, and **never scaled above 100%** (enlarging the window beyond the image shows
  it at natural size, centered).
- Deleting the image does NOT restore the pre-image window size.
- The sizing function MUST be pure and pass §19.2-F.

### 9.4 Large images & memory

- Display rendering uses a **downsampled** bitmap when the original's longest side
  exceeds **4096 px** — except animated images (GIF/APNG/animated WebP), which are
  never downsampled (frames must survive). The downsample affects display resolution
  only; the logical point size presented to layout stays the original's.
- The **original bytes are always kept** on disk (§14.4) and re-read for copy/export;
  originals SHOULD NOT be held in process memory while idle (the reference re-reads
  from disk on demand; display images are file-backed so the OS can evict them).

### 9.5 GIF / animation behavior; image-mode keys

- Animated images show **frame 1, static**, by default; they animate **only while the
  mouse cursor hovers** over the image view, and stop on exit.
- PRIMARY+C in image mode = 「画像をコピー」: write the **original bytes** under their
  native format type, plus a broadly-consumable fallback representation ([macOS] TIFF;
  [Windows] PNG + DIB; [Linux] `image/png`).
- PRIMARY+A in image mode does nothing (no selection concept).
- Font-size shortcuts in image mode: LOCAL (per-window) operations are consumed but do
  nothing; GLOBAL operations still apply app-wide (§10.4).

### 9.6 Saving ("画像を保存")

- Submenu formats, in order: 「元の形式のまま (EXT)」 (only when the original format is
  known, i.e. extension ≠ `dat`; EXT is the uppercased extension) — separator — PNG /
  JPEG / HEIC / TIFF (HEIC omitted when the platform cannot encode it, per Q5).
- 「元の形式のまま」 writes the **exact original bytes** (zero re-encode — GIF
  animation and metadata survive). Other formats re-encode from the original.
- JPEG (and HEIC) quality: **0.9, fixed** — no quality UI.
- A native save dialog asks for location/name. Default file name:
  `Ttemp yyyy-MM-dd HH.mm.ss.ext` (local time, e.g. `Ttemp 2026-07-25 21.34.12.png`) —
  screenshot-style naming. Extension is locked to the chosen format (`jpg` for JPEG).
- The dialog's initial directory is the **last-used save directory** (persisted
  setting); after a successful save, update it to the file's parent. Write atomically.
  On failure: log and shake.

---

## 10. Font Size

### 10.1 Model

Each window carries a **relative offset (± pt)** from a single **global size**:

```
effective(window) = clamp(globalSize + offset(window), 9, 48)
```

- Clamping applies **at display time only**; the raw offset is preserved un-clamped
  (push a window's offset to +100, lower the global — the relative gap is intact and
  effective size stays pinned at 48 until the numbers come back into range).
- The **global value itself** IS stored clamped to 9…48 (repeated shortcut presses or
  direct entry cannot take it out of range; unlike offsets, an out-of-range global has
  no purpose). Non-finite input for the global resets it to 14.
- Step: 1 pt. Default global: 14 pt.
- Changing the global re-renders **all windows**, preserving relative differences
  (windows at 11/14/20 become 15/18/24 when the global goes 14 → 18).

### 10.2 Key bindings

| Operation | GLOBAL (all windows + future ones) | LOCAL (this window only) |
|---|---|---|
| increase | PRIMARY + `;` / `+` / `=` / `:` (Shift variants included) | LOCAL + same keys |
| decrease | PRIMARY + `-` / `_` | LOCAL + same keys |
| reset | PRIMARY + `0` → global back to 14 (offsets untouched) | LOCAL + `0` → this window's offset to 0 |
| mouse wheel | PRIMARY + scroll | LOCAL + scroll |

Matching rules (normative, from the reference):

- Compare the character the key produces **ignoring all modifiers except Shift**
  ([macOS] `charactersIgnoringModifiers`), lower-cased, against the sets
  `{";", "+", "=", ":"}` / `{"-", "_"}` / `{"0"}`. The increase set contains four
  entries precisely because Shift is *not* ignored: JIS layouts produce `+` on
  Shift+`;`, US layouts produce `:` there, and `=`/`+` share a key — nothing conflicts,
  so all are accepted.
- "PRIMARY pressed" means PRIMARY is down and **neither** LOCAL candidate modifier is
  down (Shift is ignored). "LOCAL pressed" means the configured LOCAL modifier is down
  and PRIMARY and the other candidate are not (Shift ignored). PRIMARY+Control+`;` etc.
  MUST do nothing.
- Wheel: accumulate the vertical scroll delta while the qualifying modifier combination
  is held; every **3 units** of accumulated delta = one 1-pt step, **scroll-up
  (positive vertical delta) = increase, scroll-down = decrease** (consume repeatedly
  while |acc| ≥ 3); reset the accumulator when a non-qualifying scroll arrives. Scroll
  events without a qualifying modifier pass through to normal scrolling untouched.

Shortcut interpretation MUST be a pure module passing §19.2-D.

### 10.3 LOCAL-modifier setting

Settings offer the two platform choices from §3.3 (macOS: Control default / Option).
The choice applies to **both** the keyboard shortcuts and the wheel. GLOBAL is
permanently PRIMARY.

Known macOS constraint (document in-app help not required, but keep behavior): with
System Settings' "scroll to zoom" accessibility option bound to Control, ⌃+scroll never
reaches the app; the user can switch LOCAL to Option or use the keyboard. Analogous DE
conflicts on Linux are surfaced during Phase 0 (Q4).

### 10.4 Image-mode interaction

Image-mode windows ignore LOCAL font operations (consumed, no-op — window-edge dragging
already covers "make it bigger") but their **offset value is preserved**, so deleting
the image returns to the pre-image text size. GLOBAL operations issued from an
image-mode window still apply to the app.

---

## 11. Menus (exact contents; strings normative per §17)

### 11.1 Text-mode context menu (right-click in the text view)

```
取り消す
やり直す
──────────────
カット / コピー / ペースト / すべてを選択
──────────────
検索…
置換…
──────────────
画像を選択…        ← present ONLY when the window is in empty text mode
──────────────
✓ 最前面に固定      ← checkmark reflects pinned state
```

Every toolkit-default extra (spelling, substitutions, speech, services, …) MUST be
absent — build the menu explicitly.

「画像を選択…」opens a native image-file picker (single selection, image types); the
chosen file enters the standard image path (§9.2 file route, §9.3 sizing). It is hidden
for windows containing text (mode table §9.1 protects text).

### 11.2 Image-mode context menu

```
画像をコピー
画像を保存 ▸        ← submenu per §9.6
──────────────
画像を削除
──────────────
✓ 最前面に固定
```

### 11.3 Tray icon

- Icon: template/monochrome "T-in-a-square" style glyph ([macOS] SF Symbol `t.square`,
  template image for light/dark auto-inversion). Warning state (§13.3): exclamation-
  triangle glyph instead; tooltip switches from `Ttemp` to the §17 warning string.
- **Left click** → activate + all windows to front (§6.4).
- **Right click** → menu:

```
新規ウィンドウ
入力監視を許可…                ← [macOS] ONLY while permission is missing
──────────────
[window list — one item per open note window, in creation order:
  text windows: first 30 characters (newlines→spaces, trimmed);
                if longer, append "…"; empty windows show 「（空のウィンドウ）」
  image windows: title 「画像」 + thumbnail scaled to 16 pt height, aspect preserved]
──────────────
すべてのウィンドウを前面に      ← only when at least one window exists
──────────────
設定…
Ttemp を終了
```

The separators around the window list appear only when the list is non-empty. Clicking
a list item activates the app and focuses that window. 「新規ウィンドウ」 exists
precisely so the app remains usable when the global trigger is unavailable (§3.4-A).

[macOS] Implementation caveat: assigning a permanent menu to the status item kills the
left-click split; attach the menu transiently on right-click only. Platforms with
menu-only tray support use fallback §3.4-B.

### 11.4 Application main menu [macOS]

Even without a visible menu bar, an app main menu MUST be installed, or PRIMARY+V/Z/…
never reach the text view: App menu (「Ttemp について」, no action, **no Quit item**);
Edit menu (取り消す ⌘Z, やり直す ⇧⌘Z, カット ⌘X, コピー ⌘C, ペースト ⌘V,
すべてを選択 ⌘A, 検索… ⌘F, 置換… ⌥⌘F); Window menu (閉じる ⌘W). Other platforms
route these shortcuts through their normal accelerator mechanisms — the requirement is
that all listed shortcuts work in note windows.

---

## 12. Settings Window

Opened from the tray menu 「設定…」. Title: 「Ttemp 設定」. A single fixed-size window
(reference: 460×300 pt, label column right-aligned at 180 pt; closable only), centered
on screen and brought to front with app activation when opened. Contents exactly:

| # | Row | Control | Behavior |
|---|---|---|---|
| 12.1 | ローカル操作の修飾キー | popup: the two §3.3 LOCAL choices | applies immediately |
| 12.2 | デフォルト文字サイズ | numeric field (right-aligned, ~56 pt wide) + stepper 9–48 step 1 + suffix label 「pt」 | edits the **global** size; clamped; live-updates all windows; conversely, PRIMARY+`;` etc. elsewhere live-update this display |
| 12.3 | 新規ウィンドウの最前面固定 | popup, 3 options (§17): 固定しない / 固定する（空になったら消す）**(default)** / 固定する（空でも残す）; tooltip per §17 | applies to newly created windows only (restored windows keep their saved flag); the empty-dismiss variant is consulted live at focus-out (§6.2) |
| 12.4 | ログイン時に起動 | checkbox | §4.4; reverts on registration failure |
| 12.5 | 入力監視 [macOS] | status label 「許可済み ✓」/「未許可 ⚠️」 + button 「システム設定を開く」(hidden when granted) | status re-polled every 2 s while the window is open; button deep-links to Privacy → Input Monitoring. Platforms without a permission concept omit the row entirely |

Persisted settings (separate store, §3.6): global font size, LOCAL modifier, new-window
pin mode, last image-save directory, onboarding-completed flag. (Launch-at-login lives
in the OS, §4.4.)

**Deliberately absent** (MUST NOT add): hotkey customization; a "delete all saved
windows" button (§18).

---

## 13. Onboarding & Permissions

### 13.1 First-launch onboarding

Shown once (flag in settings) at first launch, before any permission prompt — explain
first, then ask. Window title 「Ttemp へようこそ」 (reference 520×300 pt), containing:

- Heading: 「左右の Shift を同時に押すと、どこからでもメモが開きます。」
- Body (§17 full text): why input monitoring is needed [macOS], that keystrokes are
  read only and never recorded or transmitted, that the tray menu works without the
  permission, and that granting later requires no restart.
- Checkbox 「ログイン時に Ttemp を起動する」 — **checked by default**; applied on
  finish (§4.4).
- Buttons: 「システム設定を開く」 (opens the permission pane [macOS]; on platforms with
  no permission this button is omitted) and 「はじめる」 (default button).
- Closing the window by any means marks onboarding complete (it must not reappear every
  launch); finishing via 「はじめる」 additionally triggers the OS permission request
  [macOS].

On platforms where the trigger needs no permission, the onboarding still appears with
the trigger explanation (or the degraded-mode explanation per §3.4-A / Q3) minus the
permission talk.

### 13.2 Permission lifecycle [macOS]

- Detect with `CGPreflightListenEventAccess()`; request with
  `CGRequestListenEventAccess()`.
- First launch: no request until the onboarding's 「はじめる」 (§13.1 — explain first).
  On **subsequent** launches with onboarding completed and permission still missing,
  the app requests it once at startup.
- Poll the status: every **2 s while not granted**, dropping to every **10 s once
  granted** (revocation is rare); give the timer generous tolerance (~half the
  interval) for power efficiency.
- On grant: start the event tap immediately — **no app restart**. On revocation: stop
  the tap, show the warning state.

### 13.3 Un-granted / revoked state (all platforms with a gap)

Tray icon switches to the warning glyph + warning tooltip; the chord does not fire; the
tray 「新規ウィンドウ」/「入力監視を許可…」 items keep the app fully usable. The app
MUST NOT nag with dialogs.

---

## 14. Persistence & Restore

### 14.1 When to save

- **Continuous**: any content change (typing, image set/replace/delete), window move,
  window resize, pin toggle, or per-window font-offset change schedules a save,
  **debounced ~1 s** (a burst of edits coalesces into one write; a scheduled save is
  superseded by the next schedule).
- **On window close/dismiss**: a save is scheduled so the state file drops the window
  promptly (the snapshot is taken at write time from the live window set; empty and
  closed windows simply aren't in it).
- **On quit**: flush pending save synchronously **before** windows close (§4.6).
- Rationale: quit-only saving loses everything on crash/kill/power loss, and this app
  holds exactly the notes that exist nowhere else.

### 14.2 What is saved — `state.json`

Location per §3.6. Schema (normative):

```jsonc
{
  "version": 1,                    // integer schema version; current = 1
  "notes": [                       // array order = restore order (and list order §11.3)
    {
      "id": "8F14E45F-…",          // UUID string, stable across sessions
      "content": {                 // exactly one of the two shapes:
        "kind": "text",
        "text": "…full text, LF newlines…"
      },
      // or: { "kind": "image", "image": { "id": "UUID", "fileExtension": "png" } },
      "frame": { "x": 10.0, "y": 20.0, "width": 480.0, "height": 320.0 },  // pt
      "isPinned": false,
      "fontSizeOffset": 3.0        // raw, UN-clamped (may be any finite number)
    }
  ]
}
```

- **Empty windows are not saved.**
- The frame's coordinate space is the platform's native global desktop space; it only
  needs to round-trip on the same machine class. (The reference stores Cocoa
  bottom-left-origin coordinates; a Windows/Linux port stores its own convention.)
- Pretty-printing and sorted keys are RECOMMENDED (human-inspectable), not required.
- The serializer/deserializer MUST pass §19.2-H round-trip cases.

### 14.3 Robustness

- Every write of `state.json` MUST be **atomic** (write temp file, then rename).
- Unreadable file (parse error) at load → do NOT crash, do NOT overwrite: rename it to
  `state.json.corrupt-<yyyyMMdd-HHmmss>` (append `-2`, `-3`, … rather than overwrite an
  existing quarantine file), log the event, start with an empty state. The wreckage
  MUST survive for manual recovery — silently starting fresh with no residue is the
  worst possible failure mode here.
- Unknown `version` at load → same quarantine flow with name
  `state.json.version-<n>-<stamp>`; do not attempt to parse.

### 14.4 Image files

- Image originals live as individual files `Images/<UUID>.<ext>` under the state dir;
  `state.json` holds only references (keeps the JSON small enough for 1 s-debounced
  writes). Writes are atomic.
- **Orphan pruning**: after each **successful** `state.json` write (never before — a
  failed write must not orphan referenced images), delete files in `Images/` not
  referenced by the just-saved state, with two exceptions:
  - Skip the scan when the referenced-filename set is unchanged since the last prune
    (typing must not cause directory scans every second; the first save of a session
    always scans).
  - Pruning is **disabled for the whole session** when the state file failed to load
    (§14.3) — the quarantined JSON may still reference those images and the user may
    recover them by hand.

### 14.5 Restore at launch

- Recreate windows in array order; each fades in 0.12 s; **the app stays inactive** and
  MUST NOT steal focus (login-time launches must not interrupt the user).
- Restored windows use their saved pin flag and offset; global font size comes from
  settings.
- **Frame clamping** (pure function, §19.2-G): pick the display whose visible frame has
  the **largest overlap area** with the saved frame; shrink the size to fit that frame
  if necessary; clamp the origin so the window is fully inside. If **no** display
  overlaps (monitor was unplugged), center the (possibly shrunken) window in the
  primary display's visible frame. A saved frame must never restore off-screen /
  un-grabbable.
- Image note whose `Images/` file is missing → restore as an **empty text window** and
  log a warning (do not drop the window silently mid-array, do not crash).
- Restore lands on the current virtual desktop (§6.3).
- Any OS-level window/session restoration mechanism MUST be disabled for note windows
  ([macOS] `isRestorable = false`) — `state.json` is the **sole** restoration source;
  a second, OS-driven source would produce duplicate or stale windows.

---

## 15. Logging

Failures that swallow user data intent (state save failure, image save/export failure,
missing image at restore, quarantine events, trigger-hook creation failure) MUST be
logged to the platform's standard app-log facility with a recognizable prefix
(reference: `[Ttemp]`). No log may ever contain note text or keystroke contents.

---

## 16. Consolidated Numeric Constants (normative)

| Constant | Value |
|---|---|
| default window size | 480 × 320 pt |
| minimum window content size | 200 × 150 pt |
| placement upward bias | 8% of visible-frame height |
| cascade step | 24 pt right + 24 pt down |
| cascade collision tolerance | < 1 pt on both axes (origin comparison) |
| cascade wrap inset | (24 + 8 × wrapCount) pt from top-left |
| cascade iteration cap | 200 |
| content (text) inset | 12 pt |
| fade in/out duration | 0.12 s |
| shake | offsets 0, −8, +8, −4.8, +4.8, 0 pt; 0.24 s; ease-out |
| font size range | 9 … 48 pt |
| font size default / step | 14 pt / 1 pt |
| wheel-zoom accumulator threshold | 3 delta-units per 1-pt step |
| image window cap | 60% of visible frame, no upscaling |
| display downsample threshold | longest side > 4096 px (skip animated) |
| JPEG / HEIC export quality | 0.9 |
| export filename pattern | `Ttemp yyyy-MM-dd HH.mm.ss.ext` (local time) |
| menu list text truncation | 30 characters + `…` |
| menu list thumbnail height | 16 pt |
| pin button hit area | ~28 × 22 pt |
| save debounce | 1.0 s |
| permission poll interval [macOS] | 2 s un-granted / 10 s granted (tolerance ≈ ½) |
| settings permission-row poll | 2 s while open |
| state schema version | 1 |
| left/right Shift keycodes [macOS] | 56 / 60; flag bits 0x2 / 0x4 |
| settings window / onboarding window | 460×300 pt / 520×300 pt (reference values; SHOULD) |
| app identifier / name | `com.am921.ttemp` / `Ttemp` |

---

## 17. UI String Table (normative — the product UI is Japanese)

All user-visible strings MUST be exactly these (placeholders in `<>`):

| Context | String |
|---|---|
| tray tooltip (normal / warning) | `Ttemp` / `Ttemp — 入力監視が未許可のため左右 Shift が反応しません` |
| tray menu | `新規ウィンドウ` / `入力監視を許可…` / `すべてのウィンドウを前面に` / `設定…` / `Ttemp を終了` |
| window-list entries | text = first 30 chars + `…`; empty = `（空のウィンドウ）`; image = `画像` |
| text context menu | `取り消す` `やり直す` `カット` `コピー` `ペースト` `すべてを選択` `検索…` `置換…` `画像を選択…` `最前面に固定` |
| image context menu | `画像をコピー` `画像を保存` `元の形式のまま (<EXT>)` `PNG` `JPEG` `HEIC` `TIFF` `画像を削除` `最前面に固定` |
| pin indicator tooltip / accessibility | `最前面に固定中（クリックで解除）` / `最前面に固定中` |
| settings window title | `Ttemp 設定` |
| settings labels | `ローカル操作の修飾キー` / `デフォルト文字サイズ` (+`pt`) / `新規ウィンドウの最前面固定` / `ログイン時に起動` / `入力監視` |
| LOCAL modifier options [macOS] | `Control (⌃)` / `Option (⌥)` (other platforms: analogous native names, e.g. `Alt` / `Super`) |
| pin-mode options | `固定しない` / `固定する（空になったら消す）` / `固定する（空でも残す）` |
| pin-mode tooltip | `「空でも残す」を選ぶと、何も書いていないウィンドウもフォーカスを外しただけでは消えなくなります` |
| permission status | `許可済み ✓` / `未許可 ⚠️` ; button `システム設定を開く` |
| onboarding title | `Ttemp へようこそ` |
| onboarding heading | `左右の Shift を同時に押すと、どこからでもメモが開きます。` |
| onboarding body [macOS] — two paragraphs separated by a blank line | ¶1 `この操作を検知するために、Ttemp は macOS の「入力監視」の許可を必要とします。Ttemp はキーの押下を読み取るだけで、内容の記録や送信は一切行いません。` ¶2 `許可しない場合でも、メニューバーのアイコンから「新規ウィンドウ」で使えます。許可はあとから与えても、再起動なしでそのまま有効になります。` (non-macOS: adapt only the OS-specific clauses; keep tone and promises) |
| onboarding checkbox / buttons | `ログイン時に Ttemp を起動する` / `システム設定を開く` / `はじめる` |
| app menu [macOS] | `Ttemp について`; Edit `編集`; Window `ウィンドウ`; `閉じる` |

Log-only strings may be any language. No other user-visible text may be introduced
without user approval.

---

## 18. Non-Goals — MUST NOT Implement

- Quit keyboard shortcut (§4.3).
- Hotkey customization UI (modifier-only chords and normal hotkeys need different
  detection engines; out of scope by decision).
- "Discard all saved windows" bulk action (max-damage accident; individual windows are
  closable from the list).
- Rich text, markdown rendering, multiple images per window, PDF/other file support.
- Notifications/sounds on copy.
- Any window count limit.
- Any telemetry, network access, or keystroke recording. The trigger monitor reads key
  events solely to run the §5.3 state machine and MUST retain nothing.
- [macOS] App Sandbox / Mac App Store distribution (Input Monitoring is unavailable in
  the sandbox; direct distribution only).

---

## 19. Testing & Acceptance

### 19.1 Mandatory automated test categories

Automated unit tests are REQUIRED for every category below, runnable headlessly by one
CLI command, each testing the pure module (§1.5), each including **at least** the
representative cases of §19.2 with identical expected values (translated to the
implementation's API):

A. trigger state machine · B. sanitizer & emptiness · C. paste decision + mode
resolution · D. font model + shortcut/scroll interpretation · E. placement/cascade ·
F. image window sizing + export naming/format list · G. restore-frame clamping ·
H. state store (round-trip, corruption, debounce, pruning).

UI-level automation is NOT required (resident app + global hooks make it poor value);
§19.3 covers UI manually.

### 19.2 Representative normative cases

Notation for **A**: each token is one event. `K` = ordinary key down, `M` = non-Shift
modifier keystroke, `B` = mouse button down. Every other token is a Shift-state event
naming the set of Shift keys **held after the event**: `L` (left only), `R` (right
only), `LR` (both), `0` (none).

**A — trigger** (event sequence → fires?; a fire can only occur on a `0` event):

| # | Sequence | Result |
|---|---|---|
| 1 | `L, LR, R, 0` | fires at the final `0` |
| 2 | `R, LR, 0` | fires |
| 3 | `LR, L, 0` | fires at `0` only (staggered release — never earlier) |
| 4 | `LR, 0, LR, 0` | fires twice, once per `0` |
| 5 | `L, 0` | no fire (one side only) |
| 6 | `L, K, LR, 0` | no fire (key during sequence) |
| 7 | `LR, K, 0` | no fire (key while both held) |
| 8 | `LR, M, 0` | no fire |
| 9 | `LR, B, 0` | no fire |
| 10 | `L, K, LR, L, 0` | no fire (invalidation starts at the *first* press) |
| 11 | `L, K, 0, LR, 0` | fires at the final `0` only (full release resets) |
| 12 | `L, K, LR, R, LR, 0` | no fire (re-press while invalidated) |
| 13 | `K, B, M, LR, 0` | fires (idle-time inputs are irrelevant) |
| 14 | `LR`, then `reset()`, then `0` | no fire |

**B — sanitizer**: `"a\r\nb"→"a\nb"` · `"a\rb"→"a\nb"` · `"a\tb"` unchanged ·
`"a\r\n\r\n\r\nb"→"a\n\n\nb"` · `"あ　い🍣"` unchanged. Emptiness: `""`, `"   "`,
`"\n\n"`, `"　"` (U+3000) → empty; `"  a  "` → not empty.

**C — paste decision**: plain text only → text · image data only → image · image data +
plain text → **text** · image data + HTML, no plain text → **image** · fileURL
`document.pdf` + image data → **reject** (icon-image trap) · fileURL `photo.HEIC` →
imageFile · files `[a.zip, b.png, c.jpg]` → imageFile(b.png) · each of `a.pdf a.txt
a.zip a a.swift` → reject · empty → none · extension matching case-insensitive
(`A.PNG`, `a.webp`, `a.gif` accepted; `a.pdf` not).
**Mode resolution**: (emptyText, image)→set · (filledText, image)→reject ·
(image, image)→replace · (image, text)→reject · (emptyText|filledText, text)→insert ·
(any, unsupported)→reject · (any, none)→ignore.

**D — font model**: eff(14,+3)=17 · eff(14,−4)=10 · eff(14,−100)=9 · eff(14,+100)=48 ·
offset bumped +1 ×100 → offset=100 (un-clamped), eff(14,100)=48, eff(9,100)=48 ·
clampGlobal: 100→48, 0→9, 20→20, NaN→14 · bumpGlobal stops at 9/48 · offsets
[−3,0,+6] at global 14 → [11,14,20]; at 18 → [15,18,24].
**Shortcuts** (LOCAL default): PRIMARY+`;`/`=`/Shift+`;`/Shift+`+` → increaseGlobal;
PRIMARY+`-`→decreaseGlobal; PRIMARY+`0`→resetGlobal; LOCAL+`;`/`-`/`0` → local ops;
switching LOCAL to the second option swaps which modifier works and disables the other;
no modifiers → nothing; PRIMARY+`a`, PRIMARY+`1` → nothing; PRIMARY+LOCAL combined →
nothing. **Scroll scope**: PRIMARY→global, LOCAL→local, none/Shift-only→pass-through.

**E — placement** (1920×1080 visible frame, 480×320): no occupants → horizontally
centered, vertical center above the middle by 8% of frame height · one occupant exactly
at base → result is base shifted 24 pt right and 24 pt down · three occupants along the
cascade diagonal → base shifted 3×24 pt right/down · when the cascade would overflow,
the result still lies fully inside the visible frame (wrap) · clamp: an origin far
outside (e.g. beyond the right edge and below the bottom) lands exactly on the nearest
allowed corner position · window larger than a tiny visible frame pins to the frame
origin.

**F — image sizing** (1920×1080 visible frame; cap = 1152×648): 40×30 → 200×150
(floor) · 800×600 → 800×600 (unscaled) · 4000×3000 → 864×648 (scale 0.216, aspect 4:3
preserved, both axes ≤ cap) · 400×3000 → 200×648 (height hits the cap, scaled width
86.4 floors to 200 → letterbox) · zero/negative/non-finite input → 200×150.
**Export**: name for 2026-07-25 21:34:12 + `png` → `Ttemp 2026-07-25 21.34.12.png` ·
format list with ext `gif` → [original(gif), PNG, JPEG, HEIC, TIFF] · with unknown/nil
or `dat` → [PNG, JPEG, HEIC, TIFF] · original passthrough = byte-identical · extensions:
png/jpg/heic/tiff, original keeps its own.

**G — restore clamp** (main 1920×1055 at 0,0; ext 2560×1415 beside it): frame fully
on-screen, same displays → unchanged · frame on unplugged display → centered in
fallback · partially off one display → clamped inside, **size unchanged** · overlapping
both displays → lands fully inside the display with larger overlap · 1200×800 frame vs
400×300 display → shrunk to 400×300 and inside · zero displays → inside fallback.

**H — state store**: round-trip of two text notes (tabs, emoji, pinned, offsets −2/+3,
negative x) is loss-less and order-preserving · image-reference note round-trips with
offset 5 · offset 999 survives un-clamped · missing file → "empty" result · corrupt file
`{ this is not json` → quarantined as `state.json.corrupt-*`, original bytes intact,
state path vacated · `{"version":999,"notes":[]}` → quarantined as
`*.version-999-*` · two consecutive quarantines get distinct names, neither
overwritten · 10 rapid schedules → exactly 1 write after the debounce window · flush
writes immediately and cancels the pending write (no double write) · unreferenced image
file deleted after a referencing save; referenced one kept · orphan appearing between
saves with an **unchanged** reference set survives; the next reference-set-changing save
removes it · after a corrupt-load session, saves never prune.

### 19.3 Manual acceptance checklist (Phase 4 gate)

Trigger: chord fires from another app and over a full-screen app; typing with one Shift
held never fires; chord+click never fires; CapsLock ON does not block firing. Windows:
new window is immediately typeable; empty auto-dismiss on focus loss (including
clicking another Ttemp window); text window survives focus loss without copying;
close copies text (paste elsewhere to verify LF endings); closing empty window leaves
clipboard untouched; focus returns to the app underneath, never to a leftover pinned
note; quit copies nothing and restores everything on relaunch (positions, pins,
offsets, image). Text: URL typing creates no link; smart quotes off (`"` stays
straight); CRLF paste yields LF; tab key inserts TAB; find bar + Escape two-step; IME
composition + Escape does not close the window. Images: paste into text window shakes;
browser image-copy pastes as image; copied PDF file does NOT become its icon image;
multi-file drop takes first image; GIF animates only on hover; 「元の形式のまま」
saves byte-identical files; window resize letterboxes without upscaling. Fonts: global
follows relative offsets; offset survives image mode; wheel zoom in both scopes.
Restore: unplug an external display, relaunch — every window is on-screen and
grabbable. Corruption: garbage in `state.json` → app starts empty, quarantine file
present. Permission [macOS]: revoke Input Monitoring → warning icon + tray still
usable; re-grant → chord works without restart.

---

## 20. Implementation Pitfalls (distilled from the reference; treat as review checklist)

1. [macOS] No `mainMenu` installed → PRIMARY+V/Z/W dead (§11.4).
2. [macOS] Not handling `tapDisabledByTimeout` → hotkey silently dies (§5.4).
3. Auto link detection left on → typed URLs get linkified, violating §8.2/§8.3.
4. Loading clipboard images via a decoded image object → original bytes/format lost,
   「元の形式のまま」 impossible (§8.5).
5. [macOS] Permanent status-item menu → left/right split broken (§11.3).
6. Closing the window on Escape during IME composition (§6.6).
7. Overwriting the clipboard with "" when closing an empty window (§7.2).
8. Copying on quit or focus-out (§7.2).
9. Clamping the stored offset instead of only the displayed size (§10.1).
10. Restoring the pre-image window size on image delete (§9.1 — don't).
11. Activating the app during launch-restore (§14.5) or failing to activate on
    user-initiated creation (§6.1 — cooperative-activation trap on macOS 14+).
12. Auto-dismissing pinned or image windows (§6.2) — except the §12.3 empty-dismiss
    pin mode.
13. Restoring windows off-screen after a display-configuration change (§14.5).
14. Judging modifier invalidation by state mask instead of keystrokes → CapsLock users
    can never fire the chord (§5.2).
15. File-URL-before-image-data ordering in paste decision (§8.5 — Finder icon trap).
16. Pruning images before/despite a failed state write, or after a corrupt load
    (§14.4).
17. Heavy work inside the event tap/hook callback (§5.5).
18. Forgetting `isReleasedWhenClosed = false`-class object-lifetime traps when the
    window object is owned by a controller [macOS].
19. Scrollbar appearance re-wrapping text (§8.1 gutter rule).
20. [Windows] Low-level hooks don't observe elevated processes' input; the chord won't
    fire while an elevated window is focused. Accept and document; do not run the app
    elevated to "fix" it.
21. [macOS] The default TextKit 2 text view is unstable during live window resize of
    long soft-wrapped text (wrap/scroll position jumps); the reference pins the view to
    TextKit 1 (touch `layoutManager` once at setup). Plain text loses nothing.
22. [macOS] Overriding `scrollWheel` on the text view silently disables responsive
    scrolling (scrolling feels sticky); re-opt-in via
    `isCompatibleWithResponsiveScrolling` and always forward unhandled events to
    `super`.

---

## 21. Packaging & Distribution (Phase 5; SHOULD-level, per Q7)

- One-command build from a clean checkout; document exact commands in the README.
- [macOS] Hardened Runtime ON from day one; no sandbox (§18); unsigned/ad-hoc builds
  are for local use (TCC permission resets on every re-sign — warn the user); the
  Developer-ID + notarization + `.dmg` path SHOULD be scripted even if not yet used.
  Release builds SHOULD optimize for size (reference: `-Osize`, LTO, dead-strip,
  symbols stripped).
- [Windows] Per-user installer (MSIX or Inno Setup) or portable exe; unsigned binaries
  trip SmartScreen — inform the user.
- [Linux] Native package, AppImage, or plain binary + `.desktop` file. Flatpak's
  sandbox conflicts with `CAP-TRIGGER` on X11 (and evdev); if Flatpak is requested,
  surface the conflict in Phase 0.
- An application icon is required by OS surfaces (permission lists, tray fallbacks); a
  placeholder (monochrome rounded square + "T") is acceptable initially.

---

## 22. Conformance Checklist (final self-audit before hand-off)

The agent MUST verify and report each item:

- [ ] Phase 0 executed; `DECISIONS.md` complete; every degraded capability was
      user-approved.
- [ ] All §19.1 categories implemented; all §19.2 cases pass; command documented.
- [ ] §19.3 checklist walked through and reported (item-by-item).
- [ ] Every §16 constant matches; every §17 string matches byte-for-byte.
- [ ] All §18 non-goals absent.
- [ ] §20 pitfalls reviewed against the code, one line each.
- [ ] Build + run instructions verified from a clean clone.

---

*End of specification. Total normative authority: this file. When in doubt — ask the
user, never guess silently.*
