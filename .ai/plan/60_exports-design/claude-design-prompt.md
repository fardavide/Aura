# Claude Design brief — Aura exports (issue #60)

Two prompts, sent separately. **Prompt 0** is the shared design-system preamble: paste it at the
top of *each* of the two, so each conversation is self-contained.

Deliverables come back as `Exports.dc.html` and `Timeline Detail — Export.dc.html`, matching the
existing `Cameras.dc.html` / `Timeline.dc.html` / `Timeline Detail.dc.html` concepts.

---

## Prompt 0 — shared preamble (paste above both prompts)

> You are designing a screen for **Aura**, a native iOS + macOS SwiftUI client for Frigate NVR
> (a self-hosted camera recorder). It is a personal, single-user app. Deliver a **single
> self-contained HTML file** — no external assets, no network fetches, inline `<style>` and any
> inline SVG — that renders every requested breakpoint and state as labelled frames laid out on a
> page, **light and dark side by side**, plus a written specification section at the end. Use CSS
> only for the mock; the implementation is SwiftUI, so keep effects to what SwiftUI can express
> (no CSS filters that have no SwiftUI equivalent beyond blur/shadow/gradient).
>
> ### The Aurora design system (already shipped — match it exactly, do not invent new colours)
>
> **Typeface:** Urbanist throughout (link it or fall back to a system sans in the mock; name it
> correctly in the spec). Numerals in clocks and rulers are the *system* font with `tnum`, not
> Urbanist.
>
> **Text styles** (pt / weight / tracking-em):
> `screenTitle` 32 ExtraBold −0.03 · `heroTitle` 19 ExtraBold −0.01 · `tileTitle` 13 ExtraBold ·
> `headline` 17 Bold · `body` 15 Medium · `bodyEmphasis` 15 SemiBold · `caption` 12 Medium ·
> `captionEmphasis` 12 SemiBold · `overline` 10.5 Bold +0.08 (uppercase) ·
> `sectionHeading` 10.5 Bold +0.08 (uppercase, quaternary ink) · `chip` 13 Bold ·
> `button` 15 Bold · `livePill` 10.5 ExtraBold +0.08.
> Numeral styles: `clockDetail` 31 heavy −0.03 with a `clockDetailSeconds` 14 bold suffix ·
> `rulerLabel` 10 semibold · `axisLabel` 9.5 semibold.
>
> **Colour tokens** — `light` / `dark`, `rgba` where alpha is given:
>
> | Token | Light | Dark |
> |---|---|---|
> | Base (screen) | `#FBFAFF` | `#0A0A14` |
> | NoFootage (letterbox) | `#EEEBF7` | `#15121F` |
> | SettingsSheet | `#FFFFFF` | `#12101E` |
> | TextPrimary | `#1A1630` | `#F4F1FF` |
> | TextSecondary | `#4E4870` | `#DDD8F0` |
> | TextTertiary | `#5F5A7C` | `#B9B4D2` |
> | TextQuaternary | `#7A7599` | `#8C87A8` |
> | TextMuted | `#8C87A8` | `#7C7896` |
> | GradientBlue | `#5B9DFF` | `#5B9DFF` |
> | GradientViolet | `#9B6BFF` | `#9B6BFF` |
> | GradientPink | `#FF6FB5` | `#FF6FB5` |
> | Live / AlertMarker | `#FF3B7A` | `#FF3B7A` |
> | Detection (amber) | `#F59E3B` | `#FFB86B` |
> | AlertTagText | `#C0368A` | `#FF8FC8` |
> | AlertTagFill | `#C0368A` @ .12 | `#FF6FB5` @ .14 |
> | AlertTagBorder | `#C0368A` @ .30 | `#FF6FB5` @ .35 |
> | SheetTint (glass fill) | `#FFFFFF` @ .52 | `#1C1630` @ .42 |
> | SheetBorder | `#FFFFFF` @ .88 | `#FFFFFF` @ .17 |
> | ChipFill | `#FFFFFF` @ .55 | `#FFFFFF` @ .10 |
> | ChipBorder | `#FFFFFF` @ .90 | `#FFFFFF` @ .19 |
> | VideoChipFill (over video) | `#0A0A14` @ .40 | `#0A0A14` @ .40 |
> | VideoChipBorder | `#FFFFFF` @ .20 | `#FFFFFF` @ .20 |
> | Well (recessed container) | `#000000` @ .06 | `#000000` @ .22 |
> | Grabber | `#1A1630` @ .25 | `#FFFFFF` @ .30 |
> | HatchFill | `#1A1630` @ .04 | `#FFFFFF` @ .045 |
> | HatchLine | `#1A1630` @ .12 | `#FFFFFF` @ .125 |
> | NowLine | `#1A1630` @ .30 | `#FFFFFF` @ .38 |
> | Midnight divider | `#1A1630` @ .20 | `#FFFFFF` @ .25 |
> | WashViolet | `#7C3AED` @ .16 | `#7C3AED` @ .50 |
> | WashPink | `#EC4899` @ .12 | `#EC4899` @ .36 |
> | WashBlue | `#3B82F6` @ .10 | `#3B82F6` @ .24 |
> | RimBlue | `#5B9DFF` @ .80 | `#5B9DFF` @ .90 |
> | RimViolet | `#9B6BFF` @ .15 | `#9B6BFF` @ .25 |
> | RimPink | `#FF6FB5` @ .80 | `#FF6FB5` @ .90 |
>
> **Gradients:** brand = blue→violet→pink. `diagonal` (135°) for titles, primary buttons, badges
> and selected segments. `vertical` (90°) for video frames. `badge` = violet .9 → pink .9.
> `rim` = RimBlue → RimViolet → RimPink at 135°, used as a 1.5pt stroke on glass sheets and video
> cards (bright at both corners, faint in the middle).
>
> **Surfaces.** The screen background is Base with soft violet/pink/blue washes bled in from the
> corners. Floating panels are a single frosted-glass layer: SheetTint fill + backdrop blur +
> SheetBorder hairline + the rim gradient + a soft violet glow behind. **One glass layer per
> surface — never nest glass inside glass.** A control that sits *inside* a glass panel uses the
> flat `Well` recess instead (that is how the segmented controls are built).
>
> **Existing components you should reuse rather than redesign:**
> - *Segmented control*: pill options in a `Well` container; the selected segment takes the full
>   `diagonal` brand gradient with white ink.
> - *Badge / chip*: capsule, `ChipFill` + `ChipBorder`, `chip` text. A "live"-variant badge is the
>   `Live` red with a red glow.
> - *Gradient action button*: full-width capsule or 12pt-radius rect, `diagonal` gradient, white
>   `button` text; disabled = 45 % opacity **and a stated reason rendered beside or under it**.
> - *Transport circle buttons*: 36–44pt circles, glass fill, SF Symbols.
> - *Timeline track vocabulary* (`AuroraTrack`): motion bars coloured by intensity
>   (blue < 35, violet < 65, pink above); a marker lane of red (alert) / amber (detection) pills;
>   diagonal-hatched fill for recording gaps and future time; a 1.3pt dashed `NowLine` at the live
>   edge; 1pt `Midnight` day dividers; a 2pt blue→pink gradient playhead line with a 12pt
>   violet→pink dot, 2pt white border and a pink glow; the whole track sits in a `Well` with a 12pt
>   radius.
> - Video cards: 22pt continuous corner radius, 1.5pt rim-gradient stroke, soft violet glow.
>
> ### Hard rules
>
> - **Never ship a dead control.** Every control is one of: working, absent, disabled *with the
>   reason on screen next to it*, or enabled and explaining that the thing behind it is not built
>   yet. "Disabled with no explanation" is a defect. Call this out per state in your spec.
> - Light and dark are equal citizens — design both, never a filter over one.
> - Dynamic Type must not break a layout: show at least one frame at an accessibility text size.
> - Specify touch targets; the minimum is 44×44pt on touch, 28×28pt for pointer-only macOS chrome.
> - iOS and macOS are peers, not scaled copies. Say where a macOS interaction genuinely differs.
> - Annotate for VoiceOver (label, value, hint, traits, and adjustable actions), keyboard focus
>   order and increments, and Reduce Motion fallbacks.
>
> ### Spec section required at the end of the HTML
>
> A written appendix covering, per component: spacing, typography token used, material, corner
> radii, animation (curve + duration), touch target, every state transition, the VoiceOver strings
> verbatim, keyboard behaviour, and pointer behaviour on macOS.

---

## Prompt A — `Exports.dc.html`

> Design **Exports**, a new fourth main tab in Aura, sitting beside Cameras, Timeline and Events.
>
> ### What an export is
>
> Frigate can cut a clip out of a camera's continuous recording and keep it as a file on the
> server. Aura's Exports tab browses that server-side library. An export record carries: an id, a
> camera name, a friendly name (Frigate generates a timestamp-based one, e.g.
> `driveway_20260918_143012`), a creation date, a video path, an optional thumbnail path, and an
> `in_progress` flag. Newest first.
>
> The files stay owned by the server. "Download" makes a *copy* onto the user's device through the
> platform's own destination UI — the iOS share/save sheet, the macOS save panel. Aura does **not**
> keep a second persistent local library, so there is no "Downloaded" filter, no offline section,
> and no local-vs-server distinction to show. Rename and delete are out of scope for this release:
> do not draw controls for them.
>
> ### Breakpoints (design all four, light and dark)
>
> 1. **iPhone portrait** — 393 × 852.
> 2. **iPhone landscape** — 852 × 393. The vertical size class is compact; the app hides the nav
>    bar here and uses side-by-side layouts on its other screens.
> 3. **iPad** — 1024 × 1366 (and note what changes in landscape).
> 4. **macOS** — a 1280 × 800 window. Native chrome, pointer-first, no tab bar at the bottom.
>
> Existing tab screens open with a large `screenTitle` header that collapses on scroll, and put
> filter/summary chips in a row under it. Follow that. **An export list has nothing worth filtering
> by in this release — do not invent chips to fill the space** unless a camera filter genuinely
> earns its place, in which case argue for it in the spec.
>
> ### States to design
>
> - **Loading** — first paint, nothing cached.
> - **Empty** — server reachable, zero exports. This is the state a new user meets, so it must
>   teach: exports are created from a camera's timeline, not from here. Say where to go.
> - **Unreachable server** — with a retry affordance.
> - **Retrying** — what the retry control looks like mid-attempt.
> - **Populated** — a realistic list: several ready exports across different cameras, mixed
>   thumbnail / no-thumbnail, one processing.
> - **Refreshing with last-good content** — the list is on screen and a background refresh is in
>   flight; and the variant where that refresh *failed* but the last good content is kept. The
>   screen must never blank.
>
> ### The export card
>
> Design it as a component with these variants:
>
> - **Ready, with thumbnail** — thumbnail, friendly name, camera, creation time, duration if known.
> - **Ready, no thumbnail** — the server may have none. Design the placeholder; it must not look
>   like a failure.
> - **Processing** — Frigate is still cutting the clip. Play and Download are **disabled and
>   labelled with why** ("Still processing on the server"), and the card carries a visibly
>   indeterminate treatment. There is no server-side percentage, so do not draw a determinate bar.
> - **Downloading** — a *determinate* progress treatment (bytes are known) with a cancel control.
> - **Download failed** — the error on the card, retry offered, the card otherwise intact.
>
> Make the processing and downloading progress treatments **visually distinct** — they mean
> different things (server work vs. transfer) and can be true at once on different cards.
>
> ### Playback
>
> Tapping a ready card opens the export's MP4. Design that surface: it should read as a sibling of
> the app's existing player screens — video in a 22pt rim-gradient card with a violet glow, title
> and camera above or below, a floating glass control pill. Decide and justify whether it is a
> push, a sheet, or (on macOS) a separate window. Include the Download action there too.
>
> ### Download / save
>
> Design the whole flow, not just the button: press → determinate progress with cancel →
> completion hands off to the platform destination UI. Sketch what the system sheet/panel looks
> like in place so the handoff is visible, and design the failure and cancellation returns. Where
> does progress live if the user scrolls away or leaves the screen?
>
> ### Also required
>
> - The tab bar item: icon and label for Exports next to the existing four. Icon must not collide
>   with Timeline's or Events'.
> - A frame at an accessibility Dynamic Type size showing the card reflowing.
> - VoiceOver reading order and strings for a ready card, a processing card, and a downloading card.
> - Keyboard focus order on macOS, and what Return / Space / ⌘S do on a focused card.

---

## Prompt B — `Timeline Detail — Export.dc.html`

> Design the **export range editor** that lives on Aura's existing **Timeline Detail** screen —
> one camera, one continuous time axis — so a user can cut a clip by dragging on the timeline
> instead of typing dates and times.
>
> ### The screen it must fit inside (already shipped — do not redesign it)
>
> Timeline Detail shows one camera's footage above/beside a floating frosted-glass panel that
> carries the whole time axis. The panel holds, top to bottom:
>
> - a **day stepper** `‹ SUN, JAN 11 ›` and a big **clock** readout (`14:30` with a small `:12`
>   seconds suffix),
> - an **Hour / Day / Week** segmented zoom control,
> - a **24-hour day-overview bar** — hourly motion rollup, alert ticks, hatched gaps and future
>   time, and an outlined slice marking the stretch the scrub track below is showing; dragging it
>   jumps,
> - the **scrub track** — 72pt tall (50pt on the rail): motion bars from the baseline, a marker
>   lane of alert/detection pills, hatched gaps, day dividers, a dashed live edge, a fixed centre
>   playhead, a ruler of times below, and at Hour zoom a filmstrip of preview stills behind it.
>   The track scrolls under the fixed playhead; dragging it scrubs,
> - a **transport**: previous activity · −10s · play/pause · +10s · next activity, plus a speed
>   ladder (1× 2× 4× 8×) and a **Live** chip that glows red while parked at the live edge.
>
> It renders in **three arrangements** and the editor must work in all three:
>
> - **`stacked`** — iPhone upright. Panel floats as a card across the bottom; the video sits
>   centred in the gap above it. Panel padding 16, internal spacing 12.
> - **`rail`** — iPhone on its side. A **168pt-wide vertical rail** down the trailing edge, the
>   track running top→bottom (now at the top, past below). **The nav bar is hidden in this
>   arrangement** — every control must live inside the rail. Panel padding 12, spacing 10. The
>   transport is already two short rows plus a full-width Live pill here; space is the binding
>   constraint.
> - **`split`** — iPad and macOS. A 16:9 hero above a wide card (max 1100pt): the time axis on the
>   left, a 300pt control column on the right. Panel padding 16, spacing 20.
>
> **Hard constraint:** the resting video slot is laid out so the panel can never cover it. The
> export editor must keep that true in all three arrangements — it may grow the panel, it may not
> overlay the video.
>
> ### Decisions already settled — design to these, do not re-open them
>
> 1. **The editor is inline on the existing panel.** Entering export mode transforms the scrub
>    track already on screen: handles appear on it, and the transport row is replaced by the
>    export actions. It is not a sheet and not a pushed screen. One timeline, not two.
> 2. **The initial selection is fixed relative to the playhead: 30 seconds before it to 60 seconds
>    after it** (1:30 total), clamped to available history and to the live edge. Not the visible
>    interval — at Week zoom that would propose a seven-day export.
> 3. **Whole-second precision, honestly.** The server truncates export bounds to integer seconds,
>    so every readout, every step and every handle snap is whole seconds. Nothing in the UI may
>    imply frame or sub-second trimming.
> 4. Minimum selection is one second; handles cannot cross.
> 5. Export type is real-time recording footage only. No timelapse, no custom name, no chapters.
>
> ### What you must settle
>
> - **The entry point.** Where does "Export" live on each of the three arrangements? Remember the
>   rail has no nav bar. It must be discoverable without crowding the transport.
> - **Whether long selections need a warning or guard** before submission (a multi-hour export is
>   a large server job) — and if so, at what threshold and in what form.
> - **Where creation progress remains visible** after the user submits: on this panel, as a
>   transient banner, on the Exports tab badge, or some combination — and how the user reaches the
>   finished export from here.
> - Exact touch targets, the drag movement threshold, long-press timing, haptic, keyboard
>   increments, pointer behaviour and VoiceOver wording (see "release two" below).
>
> ### Range-editor states to design (all three arrangements, light and dark)
>
> - **Entry** — the moment export mode turns on. What animates, and from what.
> - **Resting selection** — leading and trailing handles on the track; the selected region
>   emphasised; everything outside it dimmed; a readout of exact start, end and duration. The
>   playhead still exists and still means "what the video is showing" — make the two legible
>   together rather than letting handles and playhead read as the same thing.
> - **Dragging a handle** — the active handle's treatment, the live readout, what the other
>   handle does.
> - **Dragging the whole region** — the range moves without changing duration. Show the
>   affordance that says this is possible *before* the user tries it.
> - **Clamped** — at the start of available history, at the live edge, and at the one-second
>   minimum. Each needs a distinct, non-alarming signal.
> - **Over a recording gap** — a selection spanning hatched no-footage.
> - **Invalid / no footage** — Create Export disabled **with the reason rendered on screen**.
> - **Play Selection active** — playback constrained to the range, looping back to the selected
>   start at the end. Show how "playing the selection" differs from ordinary playback.
> - **Creating** — request in flight.
> - **Processing** — accepted, server still cutting; indeterminate (there is no percentage).
> - **Failed** — creation or processing failed, the chosen range preserved, retry offered.
>   Distinguish a retryable transport failure from a non-retryable rejection (a range with no
>   recordings), because the second must stay non-retryable until the selection changes.
> - **Completed** — the export is ready. How does the user play it or reach it in the Exports tab
>   from here, and how does the panel return to ordinary playback?
> - **Cancel** — leaving export mode with nothing created.
>
> ### Release two: press-and-hold precision
>
> A second release adds Apple-style precise adjustment, and it must be designed now so the first
> release does not paint itself into a corner:
>
> - Pressing and holding a handle **without meaningful movement** enters precision mode after the
>   platform long-press delay. An ordinary immediate drag must *not* trigger it — specify the
>   movement threshold in points and the delay in milliseconds.
> - Precision mode smoothly **expands the timeline scale around the active boundary**, keeping that
>   boundary under the finger/pointer and preserving the other boundary. Design the expanded state
>   and the transition into and out of it, including what happens to the ruler, the filmstrip and
>   the marker lane at the expanded scale.
> - After activation, dragging adjusts in **one-second steps**.
> - Releasing commits and smoothly restores the prior scale with the same instant still selected.
> - Cancelling before release restores the pre-gesture boundary.
> - One subtle haptic on iOS when precision engages — name the exact feedback style. On macOS and
>   iPad with a pointer, specify the equivalent press-and-hold, and arrow-key one-second stepping.
> - Show normal drag and precision drag **side by side** so the difference is visibly obvious.
> - Design the Reduce Motion fallback for the scale expansion.
>
> ### Accessibility, required explicitly
>
> - Each boundary is a VoiceOver **adjustable** control. Give the verbatim label, value and hint
>   strings, and what an increment/decrement announces.
> - Keyboard: focus order through handles and actions, what arrow keys do, what modifiers change
>   the increment, and how a keyboard user leaves export mode.
> - A frame at an accessibility Dynamic Type size for the `stacked` arrangement, where the panel is
>   tightest.
> - Contrast: the dimmed-outside-region treatment must not push the ruler or the motion bars under
>   the contrast floor. Say what the dim actually is (opacity? overlay? desaturation?) and check it.
