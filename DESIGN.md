---
name: Talky
description: Apple's own glass over one deep color field, on the download page and in the Mac app.
colors:
  navy: "#0B1A3A"
  indigo: "#141A4A"
  field-deep: "#0A1230"
  violet: "#6B4BFF"
  blue: "#1E5BFF"
  peach: "#FF9A6B"
  select: "#0A84FF"
  live: "#FF453A"
  ink: "#FFFFFF"
  ink-secondary: "rgba(255, 255, 255, 0.88)"
  ink-tertiary: "rgba(255, 255, 255, 0.84)"
  rim: "rgba(255, 255, 255, 0.26)"
  hairline: "rgba(255, 255, 255, 0.14)"
  glass-top: "rgba(255, 255, 255, 0.19)"
  glass-bottom: "rgba(255, 255, 255, 0.07)"
  deep-glass-top: "rgba(26, 32, 76, 0.46)"
  deep-glass-floor: "rgba(12, 18, 46, 0.42)"
  pill-tint: "rgba(8, 13, 36, 0.5)"
  pill-veil: "rgba(8, 13, 36, 0.55)"
  chip-selected: "rgba(255, 255, 255, 0.94)"
  badge: "rgba(255, 255, 255, 0.16)"
  frost: "#EEF1FF"
  window-close: "#FF5F57"
  window-minimize: "#FEBC2E"
  window-zoom: "#28C840"
typography:
  display:
    fontFamily: "-apple-system, BlinkMacSystemFont, 'SF Pro Display', 'SF Pro Text', 'Helvetica Neue', Arial, sans-serif"
    fontSize: "clamp(46px, 7vw, 88px)"
    fontWeight: 700
    lineHeight: 1
    letterSpacing: "-0.035em"
  headline:
    fontFamily: "-apple-system, BlinkMacSystemFont, 'SF Pro Display', 'SF Pro Text', 'Helvetica Neue', Arial, sans-serif"
    fontSize: "clamp(34px, 4.4vw, 56px)"
    fontWeight: 700
    lineHeight: 1.04
    letterSpacing: "-0.03em"
  title:
    fontFamily: "-apple-system, BlinkMacSystemFont, 'SF Pro Display', 'SF Pro Text', 'Helvetica Neue', Arial, sans-serif"
    fontSize: "clamp(24px, 2.6vw, 32px)"
    fontWeight: 700
    lineHeight: 1.15
    letterSpacing: "-0.02em"
  lede:
    fontFamily: "-apple-system, BlinkMacSystemFont, 'SF Pro Display', 'SF Pro Text', 'Helvetica Neue', Arial, sans-serif"
    fontSize: "clamp(18px, 1.8vw, 22px)"
    fontWeight: 400
    lineHeight: 1.55
    letterSpacing: "-0.01em"
  document:
    fontFamily: "-apple-system, BlinkMacSystemFont, 'SF Pro Display', 'SF Pro Text', 'Helvetica Neue', Arial, sans-serif"
    fontSize: "clamp(19px, 2.2vw, 26px)"
    fontWeight: 400
    lineHeight: 1.45
    letterSpacing: "-0.01em"
  intro:
    fontFamily: "-apple-system, BlinkMacSystemFont, 'SF Pro Display', 'SF Pro Text', 'Helvetica Neue', Arial, sans-serif"
    fontSize: "20px"
    fontWeight: 400
    lineHeight: 1.55
  body:
    fontFamily: "-apple-system, BlinkMacSystemFont, 'SF Pro Display', 'SF Pro Text', 'Helvetica Neue', Arial, sans-serif"
    fontSize: "18px"
    fontWeight: 400
    lineHeight: 1.55
  button:
    fontFamily: "-apple-system, BlinkMacSystemFont, 'SF Pro Display', 'SF Pro Text', 'Helvetica Neue', Arial, sans-serif"
    fontSize: "17px"
    fontWeight: 600
    lineHeight: 1
  pill:
    fontFamily: "-apple-system, BlinkMacSystemFont, 'SF Pro Display', 'SF Pro Text', 'Helvetica Neue', Arial, sans-serif"
    fontSize: "16px"
    fontWeight: 600
  chip:
    fontFamily: "-apple-system, BlinkMacSystemFont, 'SF Pro Display', 'SF Pro Text', 'Helvetica Neue', Arial, sans-serif"
    fontSize: "15px"
    fontWeight: 500
    lineHeight: 1
  label:
    fontFamily: "-apple-system, BlinkMacSystemFont, 'SF Pro Display', 'SF Pro Text', 'Helvetica Neue', Arial, sans-serif"
    fontSize: "14px"
    fontWeight: 600
    letterSpacing: "0.01em"
  small:
    fontFamily: "-apple-system, BlinkMacSystemFont, 'SF Pro Display', 'SF Pro Text', 'Helvetica Neue', Arial, sans-serif"
    fontSize: "14px"
    fontWeight: 400
  mono:
    fontFamily: "ui-monospace, 'SF Mono', SFMono-Regular, Menlo, monospace"
    fontSize: "0.88em"
    fontWeight: 500
  native-display:
    fontFamily: "SF Pro (system font)"
    fontSize: "34px"
    fontWeight: 700
    letterSpacing: "-0.6px"
  native-title:
    fontFamily: "SF Pro (system font)"
    fontSize: "26px"
    fontWeight: 700
    letterSpacing: "-0.4px"
  native-body:
    fontFamily: "SF Pro (system font)"
    fontSize: "15px"
    fontWeight: 400
  native-pill:
    fontFamily: "SF Pro (system font)"
    fontSize: "13px"
    fontWeight: 500
rounded:
  key: "0.42em"
  code: "6px"
  field: "10px"
  group: "14px"
  native-panel: "18px"
  window: "22px"
  panel: "24px"
  capsule: "9999px"
spacing:
  chip-gap: "4px"
  row-inset: "16px"
  settings-margin: "20px"
  gutter: "24px"
  panel-inset: "32px"
  block: "48px"
  stage: "64px"
  section: "140px"
components:
  button-primary:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.navy}"
    typography: "{typography.button}"
    rounded: "{rounded.capsule}"
    padding: "0 24px"
    height: "50px"
  button-primary-hover:
    backgroundColor: "{colors.frost}"
  button-primary-small:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.navy}"
    rounded: "{rounded.capsule}"
    padding: "0 16px"
    height: "38px"
  button-glass:
    backgroundColor: "{colors.glass-top}"
    textColor: "{colors.ink}"
    typography: "{typography.button}"
    rounded: "{rounded.capsule}"
    padding: "0 24px"
    height: "50px"
  nav:
    backgroundColor: "{colors.glass-top}"
    textColor: "{colors.ink-secondary}"
    typography: "{typography.small}"
    rounded: "{rounded.capsule}"
    padding: "0 7px 0 18px"
    height: "52px"
  pill:
    backgroundColor: "{colors.glass-top}"
    textColor: "{colors.ink}"
    typography: "{typography.pill}"
    rounded: "{rounded.capsule}"
    padding: "8px 22px 8px 18px"
    height: "56px"
  pipe-chip:
    textColor: "{colors.ink-secondary}"
    typography: "{typography.chip}"
    rounded: "{rounded.capsule}"
    padding: "0 16px 0 8px"
    height: "44px"
  pipe-chip-selected:
    backgroundColor: "{colors.chip-selected}"
    textColor: "{colors.navy}"
  key-badge:
    backgroundColor: "{colors.badge}"
    textColor: "{colors.ink}"
    rounded: "{rounded.capsule}"
    size: "26px"
  key-badge-selected:
    backgroundColor: "{colors.select}"
    textColor: "{colors.ink}"
  deep-panel:
    backgroundColor: "{colors.deep-glass-top}"
    textColor: "{colors.ink}"
    rounded: "{rounded.panel}"
    padding: "28px 30px"
  demo-window:
    backgroundColor: "{colors.deep-glass-top}"
    textColor: "{colors.ink}"
    typography: "{typography.document}"
    rounded: "{rounded.window}"
    padding: "26px 32px 30px"
  native-pill:
    backgroundColor: "{colors.pill-veil}"
    textColor: "{colors.ink}"
    typography: "{typography.native-pill}"
    rounded: "{rounded.capsule}"
    padding: "0 14px"
    height: "38px"
  native-pipe-chip:
    textColor: "rgba(255, 255, 255, 0.85)"
    typography: "{typography.native-pill}"
    rounded: "{rounded.capsule}"
    padding: "0 10px 0 4px"
    height: "30px"
  native-pipe-chip-selected:
    backgroundColor: "{colors.chip-selected}"
    textColor: "{colors.navy}"
  settings-header-band:
    backgroundColor: "{colors.navy}"
    textColor: "{colors.ink}"
    typography: "{typography.native-title}"
    rounded: "{rounded.native-panel}"
    padding: "22px 26px"
    height: "112px"
  settings-group:
    rounded: "{rounded.group}"
    padding: "4px 16px"
---

# Design System: Talky

## Overview

**Creative North Star: "Apple's Own Glass"**

Talky looks like a part of the Mac. Every Talky surface is one material, glass, floating over one ground: a deep navy-to-indigo color field lit by three soft lights. The download page, the onboarding window, the Settings header band and the floating pill all use this same field and this same glass, so the product reads as one object wherever it appears. The world refuses the category default of a flat white page with a screenshot; retro and physical-object styles were also rejected.

The mood is calm, dark and lit from within. Density is low: large bold headlines with tight tracking, plain body text at a generous size, and capsules of glass for everything that can be pressed. Depth comes from blur, a thin white rim and a top specular line, not from heavy shadows or ruled boxes. Violet, blue and peach exist as light in the field, not as paint. The solid accents are few and each has one job: the white primary button, the selection blue, the live red.

One world, two platforms. The web draws glass with CSS backdrop blur and saturation. The app draws it with native Liquid Glass on macOS 26 and later, and with the ultra-thin material plus a light rim on macOS 14 and 15. In the app, system controls (pickers, toggles, secure fields, the Settings sidebar) keep their native styles; the world lends type, palette, glass and the pill.

**Key Characteristics:**
- One color field behind every Talky-world surface; glass is the only material on top of it.
- White ink on dark glass. Secondary text is white at reduced opacity, never a gray.
- Capsules for anything pressed or floating alone; rounded rectangles for containers.
- SF Pro only, bold and tightly tracked at display sizes.
- The pill, with its numbered pipe chips, appears on every surface.
- Red means one thing: the microphone is live.

## Colors

A night sky with three lamps in it: dark field colors, three lights that only glow, two signal colors, and a ladder of translucent whites.

### Primary
- **Midnight Navy** (#0B1A3A): The base of the field and the page background. Also the ink on white: the solid button label, the selected chip label, the bars inside the Talky mark.
- **Night Indigo** (#141A4A): The middle stop of the field gradient.
- **Deep Field** (#0A1230): The last stop of the field gradient, where the field is darkest.

### Secondary
- **Lamp Violet** (#6B4BFF): Soft radial light at the top right of the field (95% at its center). In the native Settings sidebar it is also the Pipes icon tile, following the system's colored-tile convention.
- **Lamp Blue** (#1E5BFF): Soft radial light rising from below the field (75-80% at its center). In the native Settings sidebar it is also the Saved dictations icon tile, the same colored-tile convention. These two tiles are the only painted uses of the lamps.
- **Lamp Peach** (#FF9A6B): Soft radial light at the lower left (80-85% at its center). It is the brightest area under any glass, so it sets the contrast floor for deep glass.

### Tertiary
- **Selection Blue** (#0A84FF): Marks what is chosen or what moves forward: the selected pipe's number badge, the default pipe's ring and "Default" tag in Settings, native primary buttons (Continue, Finish, Run all pipes), and the web text selection and caret.
- **Live Red** (#FF453A): The pill's dot while the microphone records. Nothing else.

### Neutral
- **Ink** (#FFFFFF): Text and icons on the field and on glass; the fill of the solid button, the Talky mark and the waveform bars.
- **Secondary Ink** (white 88%): Body copy on the field, nav links, the lede and intros, the pill timer, unselected chip labels. Native body copy uses 78-80%.
- **Window dots** (#FF5F57, #FEBC2E, #28C840): only on the depicted macOS window in the web demo. They are the system's own chrome, never a brand color.
- **Tertiary Ink** (white 84%): Fine print, panel labels, placeholders, struck filler words, the footer. Native captions use 72%.
- **Rim** (white 26%): The 1px rim on every web glass shape. Native fallback glass uses a 22% rim.
- **Hairline** (white 14%): Dividers inside glass: the demo window title bar, key rows, privacy facts, native glass panels, the transform picker.
- **Glass Fill** (white 19% at the top to 7% at the bottom): The light glass gradient.
- **Deep Glass** (navy-indigo 46% at the top, 42% floor): The fill for glass that carries reading text.
- **Pill Tint and Veil** (dark navy at 50% and 55%): Native only. The tint goes into the Liquid Glass; the veil lies over it so white text stays readable on white documents.
- **Chip White** (white 94%): The selected pipe chip, on both platforms.
- **Badge Glass** (white 16%): Unselected number badges on glass, on both platforms.
- **Frost** (#EEF1FF): The solid button's hover fill.

Native Settings content uses system colors: control and text backgrounds, primary and secondary labels, system green for "Allowed", system orange and yellow for warnings, and system red for errors and the destructive Uninstall action. The instruction-mode recording dot is system orange.

### Named Rules
**The One Field Rule.** Every Talky-world surface sits on the same field: a navy, indigo, deep-field gradient (160° on the web, top-leading to bottom-trailing in the app) lit by violet at the top right, peach at the lower left and blue from below. The radial light is the ground of the world, not an accent glow. On the web the field is fixed behind the page and its three lights drift slowly (38 s, 46 s and 52 s, alternating); with reduced motion they stand still. The lights burn at full strength only behind the first screen: within the first 160px of scroll they fade to 55% (`--glow`), so text set directly on the field keeps at least 4.5:1 over their brightest point. On phones the peach light sits lower (top 60vh), behind the Notes window, not behind the small print. Both values were measured, not guessed; re-measure before raising either.

**The Light, Not Paint Rule.** Violet, blue and peach are light inside the field. On glass surfaces they never become text, button fills, borders or card tints.

**The Live Wire Rule.** Live Red appears only while the microphone is live: the pill's recording dot, which pulses. Still previews, buttons, badges and errors never use it.

**The Blue Means Chosen Rule.** Selection Blue marks the selected pipe and the action that moves forward. It is never decoration.

## Typography

**Display Font:** SF Pro Display (web stack: -apple-system, BlinkMacSystemFont, then Helvetica Neue and Arial)
**Body Font:** SF Pro Text (same stack)
**Label/Mono Font:** SF Mono through ui-monospace, for file paths and code only

**Character:** The platform's own voice. Display sizes are bold and tightly tracked so a short sentence reads as one shape; body text is regular, roomy and plain.

### Hierarchy
- **Display** (700, clamp(46px, 7vw, 88px), 1): The hero headline only, with balanced wrapping.
- **Headline** (700, clamp(34px, 4.4vw, 56px), 1.04): Web section headings.
- **Title** (700, clamp(24px, 2.6vw, 32px), 1.15): Privacy fact headings.
- **Lede** (400, clamp(18px, 1.8vw, 22px)): The hero subhead in Secondary Ink, max 34em. Section intros use 20px, max 36em.
- **Document** (400, clamp(19px, 2.2vw, 26px), 1.45): Text arriving in the demo window. The pipes example uses 22px.
- **Body** (400, 18px, 1.55; 17px below 760px): Running text.
- **Button / Pill / Chip** (600 17px; 600 16px; 500 15px): Control labels. Small buttons use 14px.
- **Label** (600, 14px, +0.01em, sentence case): Names the content of a panel ("You said", "Talky typed"). Never a kicker above a headline.
- **Small** (400, 14px): Nav links, fine print, the demo note, the footer.
- **Native** (SF Pro, the system font): onboarding titles 34pt bold; the Settings header and onboarding step titles 26-28pt bold; onboarding body 15pt; the pill and its previews 13pt medium; Settings group titles at the headline style; notes at the caption style.

### Named Rules
**The Platform Voice Rule.** SF Pro is the only family, on both platforms. No second display face, no webfont.

**The Tight Top Rule.** Bold display type tracks tighter as it grows: -0.02em to -0.035em on the web, -0.4pt to -0.6pt in the app. Body text never tracks below -0.01em.

**The Steady Numbers Rule.** Numbers that change or line up use tabular figures: the pill timer and every key badge.

## Layout

**Web.** One centered column, `min(1120px, 100% - 48px)` wide. The hero centers everything: 132px of top padding under the fixed nav (112px below 760px), the lede 20px under the headline, buttons 32px lower, fine print 16px lower, then the demo stage (max 820px) 64px lower (44px below 760px). Sections start 140px apart (96px below 760px); the closing call to action 160px (112px). A glass panel follows its intro by 48px; the privacy facts by 56px. Definition rows use a label column (min 220px, 34%) and a text column with 24px gaps and hairline separators; privacy facts use a 40% heading column. Both collapse to one column below 760px. The three modes (Dictate, Dictate through a pipe, Rewrite selected text) sit in three equal deep panels, 24px apart, that stack below 760px. Each opens with a capsule tag naming what it needs: "No key needed" in Chip White with a navy label, "Anthropic key" on Badge Glass. The pipes example is a 1 : 1.25 grid that stacks below 760px. The rewrite example reuses that grid, with the selected words on a Selection Blue highlight. The Saved dictations section, after the rewrite example, uses that same grid: what you said, and the pipe result. Below 440px the pipe chips become a two-column grid.

**The Fixed Slot Rule.** On the web the pill sits in a 272px slot, right-aligned against the chips and as wide as its Listening state, so the chips never move when the pill changes state. Below 760px the slot spans the row and centers the pill.

**Native.** The pill sits at the bottom center of the screen that has the mouse, 24pt above the Dock; the panel adds 14pt of padding for the fallback shadow. The pill and its chips sit side by side, 8pt apart, in one glass group so they morph together on macOS 26. Onboarding is one fixed 600 × 680 window on the field with 40pt side padding, the step dots 18pt from the top, and the footer 28pt from the bottom (Back on the left, an optional plain "Skip for Now" and the primary action on the right). Settings is a sidebar (190-260pt, ideally 210pt) with the mark and version at its top, and a detail page. The sidebar lists General, Pipes and Saved dictations.

**The One Column Rule.** Each Settings page pads its content 20pt on every side. The header band, the groups, the pipe rows and the saved-dictation cards share those column edges, so changing pages never shifts the layout. General stacks its groups 26pt apart; Pipes and Saved dictations stack their parts 16pt apart and their rows 12pt apart. In the header band the title sits left and the preview right; when the window is narrow the preview moves under the title. The Saved dictations preview is two glass capsules ("What you said", "Pipe result"), not the recording pill, because this page is a list.

## Elevation & Depth

Glass is the depth system. A surface rises by blurring and saturating what is behind it (28px blur, 170% saturation on the web), catching a 1px white rim and a 1px top specular line, and casting one long, soft drop shadow. There are no tonal card stacks and no ruled boxes on the field. Inside glass, hierarchy is flat: hairline dividers separate rows. On macOS 26 the app uses the system's regular Liquid Glass with a tint, and glass that sits together is grouped so it renders and morphs as one.

### Shadow Vocabulary
- **Glass lift** (`box-shadow: inset 0 1px 0 rgba(255,255,255,.42), inset 0 -1px 0 rgba(255,255,255,.06), 0 24px 60px -24px rgba(0,0,0,.55)`): Every web glass shape. The inset lines are the specular top and a faint lower edge; the drop is long and soft.
- **Keycap** (`box-shadow: inset 0 1px 0 rgba(255,255,255,.4), 0 2px 6px -2px rgba(0,0,0,.35)`): Inline key caps in running text.
- **Native fallback** (black 25%, radius 10pt, y 5pt): Glass on macOS 14 and 15 only. Liquid Glass on macOS 26 draws its own depth.
- **Mark lift** (black 30%, radius 16pt, y 8pt): The large Talky mark on the onboarding welcome step.

### Named Rules
**The Soft Shadow Rule.** Drop shadows are long and blurred. No hard, zero-blur offset shadows. The 1px inset specular line at the top of glass is part of the material, not a shadow to remove.

**The Deep Glass Rule.** Reading text in a panel sits on deep glass, never on light glass: a navy-indigo fill from 46% at the top to a 42% floor behind the text. The floor keeps white text at 4.5:1 over the peach light. The demo window may fade its fill to 14% only below the text, so the field shows through the empty part. Light glass is for chrome and controls: the nav, buttons, the pill, chips and key caps.

**The Veil Rule.** Native glass that floats over other apps (the pill, its chips, the processing and message capsules, the transform picker) carries the navy tint inside the glass and the navy veil over it. Liquid Glass turns light over white documents even when tinted; the veil keeps white text readable. Glass inside Talky's own windows, which always sit on the field, uses a black 15-18% tint and no veil.

## Shapes

Two shapes carry the world. Anything that can be pressed or floats alone is a capsule: the nav, buttons, the pill, pipe chips, number badges, step dots, the "Default" tag. Containers are rounded rectangles; in the app they use the continuous corner. Radius grows with size: web panels 24px and the demo window 22px; native glass panels and the Settings header band 18pt, the transform picker 20pt, message capsules 19pt, Settings groups and pipe rows 14pt, text editors 10pt, picker rows 8pt, permission tiles 7pt, sidebar tiles 6pt, inline code 6px.

Borders exist in two forms only: the 1px glass rim and hairline dividers. The Talky mark is a white rounded square (corner 30% of its size) with three navy bars at 24%, 46% and 14% of its height, drawn in SVG on the web and in SwiftUI in the app.

## Components

### Buttons
One bright white action and one glass companion.
- **Shape:** capsule (50px tall; small 38px).
- **Primary (web):** white fill, Midnight Navy 600 label, 24px side padding, an optional 18px download arrow drawn in SVG. Used for Download.
- **Hover / Focus / Active:** hover moves to Frost; a press scales to 0.97 over 0.2s on the ease-out curve (cubic-bezier(.16, 1, .3, 1)); keyboard focus shows a 2px white outline 3px out.
- **Glass (web):** the light glass recipe with a white label. Hover brightens the fill (white 26% to 10%); pressed fills to white 30%. "Hold to try" uses it.
- **Native:** primary actions use the glass prominent style on macOS 26 (bordered prominent before), tinted Selection Blue, at the large control size. Secondary actions use the glass style (bordered before). Settings rows keep the default system button.

### Chips (Pipe Chips)
A numbered radio row inside one glass capsule.
- **Style:** a light glass capsule (56px tall on the web with 6px inner padding and 4px gaps; 4pt padding and 2pt gaps in the app) holding chips 44px tall (30pt in the app): the number badge first, then the name. Unselected chips are clear with Secondary Ink labels (85% in the app); hover adds white 8%.
- **Selected:** a Chip White fill with a Midnight Navy label, and the number badge turns Selection Blue. The change takes 0.25s ease-out on the web. In the app the white fill glides to the new chip on a spring (0.4s response, 0.82 damping).
- **Clickable chips (app):** where the chips are buttons, hover adds white 14% and the pointer becomes the link hand.
- **Number badge:** a 26px circle on the web (18pt in the app, 20-24pt in the picker and Settings) with bold tabular numerals on Badge Glass. Order is 1-9, then 0 for Raw. On plain native backgrounds (Settings pipe rows) the unselected badge uses the primary label color at 10%.
- **Keyboard:** a radio group; arrow keys move the selection; in the web demo, 1-3 and 0 pick a pipe while the user holds.

### Cards / Containers
- **Deep panels (web):** deep glass, 24px radius, 28px × 30px padding. Key lists use 8px × 32px padding with 22px rows and hairline dividers.
- **Demo window (web):** deep glass with the fade below the text, 22px radius, a 44px title bar with three 12px window dots and a centered 13px semibold title, a hairline under it, and the document below (minimum 196px tall).
- **Glass panels (onboarding):** glass in an 18pt rounded rectangle with a black 15% tint and 16-18pt padding.
- **Settings group:** a headline title, then a 14pt rounded panel on the system control background with a primary-color 8% stroke, 16pt side padding and system dividers between rows, and an optional caption under it. A row is a label on the left and its control on the right, at least 30pt tall with 8pt vertical padding.
- **Pipe row (Settings):** the same 14pt panel with 16pt padding: the editor on the left, its output on the right, 18pt apart. The default pipe swaps its stroke for a 1.5pt Selection Blue ring at 60%.

### Inputs / Fields
- **Native only.** The Anthropic key uses the system rounded-border secure field with a Test Key button beside it (max 420pt in Settings) and one caption line under it: a "Get a key in the Anthropic Console ↗" link when empty, then the test result (green when the key works, red when Anthropic refuses it, orange when Talky can't reach Anthropic). Prompt editors and the test text use the system text editor on the text background, 10pt radius, a primary-color 10% stroke and 8pt padding. Focus is the system focus ring.
- **Hotkey field (Settings):** a 28pt field on the text background, 7pt radius, with a primary-color 12% stroke (20% on hover). The left part (at least 150pt, wider for a long chord) holds the hotkey as plain key caps; a hairline separates a chevron menu of suggestions, the default marked "(Default)". A click records: the stroke turns to the accent color with a 3pt accent ring at 35% outside it, the field says "Press keys…" or shows the modifiers held, and a caption under it says what works. A refused key shows its reason in system orange. Esc, a click outside the field or a closed window cancels.
- The web page has no form fields.

### Navigation
- **Web:** a fixed light-glass capsule, 52px tall, centered 20px from the top: the mark and the name at 600 16px, three section links in Secondary Ink (hover to Ink), and a small solid Download button. Below 760px it spans the width less 32px and drops the links.
- **Native Settings:** the system sidebar with two rows, each with a 22pt colored icon tile (General gray, Pipes Lamp Violet), under the mark and version.

### App Icon
The field with the mark's three bars on it, in Liquid Glass. `Resources/AppIcon.icon` is an Icon Composer document with two groups. The back group is the field as an SVG: the navy-indigo gradient, violet light at the top right, blue rising from below, and a dim peach light (55%) in the lower-left corner. The front group is the three white bars of the mark as glass (specular on, 20% translucency, a neutral shadow at 50%), 12.6% of the canvas wide with 10.4% gaps, so they stay clear at small sizes. The system draws the dark, tinted and clear modes from these layers. Build with `actool`; it also writes an `.icns` for macOS 14 and 15.

### Keycaps
Inline keys in running text (fn, ⌥, esc, 1-9): a small light-glass cap at 0.78em semibold, 0.42em radius, with the rim and the keycap shadow.

### The Pill (signature)
The product's face, the same on every surface.
- **Idle:** a glass capsule with a white 50% dot and a label ("Ready" on the web, "Hold fn" in previews), and nothing else.
- **Listening:** the dot turns Live Red and pulses (1.4s on the web, 0.7s in the app). A waveform of white bars follows (the middle bars move most), then a tabular timer in Secondary Ink. Hands-free adds a 22pt stop button. Instruction mode uses a system orange dot. With 30 seconds or less left, a yellow "stops in Ns" note shows.
- **Processing (app): the Reading Light.** The recording's nine bars stay, with no dot, followed by the label ("Transcribing…", then the pipe name). A soft white band, 84pt wide, reads through them: it eases out of the bars, which rise to 15.5-18pt under it, speeds across the label and slows on the last letters, over 1.2s with a 0.25s rest. Between reads the bars ripple at 4.5-7pt. The text rests at white 70% (4.5:1 over white documents) and the bars at about 42%; the band lifts both to full white. With Reduce Motion nothing travels: the bars hold an arch and the pill brightens and dims over 1.8s.
- **Processing (web):** a small white spinner and the pipe name. **Done (web):** a white check and "Pasted", then idle again after 1.6s.
- **Sizes:** 56px tall on the web (50px below 760px); 38pt tall in the app with 14pt side padding. Native messages wrap inside a 19pt rounded rectangle up to 420pt wide.
- **Previews:** the Settings header band shows a still pill built from the real settings (hotkey label, pipe list, default pipe). The onboarding pipes example shows the chips alone, as buttons, so the user can click through what each pipe does to one sentence. Until the user picks a chip, the example moves to the next one every 3.6s, so the chips show that they change the result; it waits while the pointer is over the panel.

**The Two Layers Rule.** Dictation and pipes are separate layers, and every surface shows them in that order. Dictation is free, on the Mac and needs no key. Pipes need an Anthropic key. Pipe chips appear only where pipes are explained or turned on.

**The Way Forward Rule.** Every onboarding state has a visible way forward, and the primary button names what it does with what the user entered. A button never says "Skip" for something the user just typed.

**The Nothing Fake Rule.** In onboarding, anything that looks like a control works. A still pill looks pressable, so onboarding shows none: the welcome explains the hotkey with a key cap and icons, and the first real use is the Try it step.

**The Idle Preview Rule.** Every still picture of the pill shows the idle state: a white 50% dot, "Hold fn" (or the user's hotkey), no waveform, no red. The red dot belongs only to a pill that is actually recording, or to the web demo while it runs.

### Rewrite Reveal (app)
When the pipes example changes, the old text blurs away (8pt blur and fade, 0.2s ease-out). After 0.12s the new text writes in word by word, 45ms apart: each word fades in, comes into focus from a 7pt blur and settles 4pt up over 0.5s on an ease-out cubic. It needs macOS 15; before that, and with Reduce Motion, the text cross-fades.

### Filler Strike (web demo)
The demo types the raw words, marks the fillers "um", "so" and "like", strikes them in Tertiary Ink with a white 60% line for 900 ms, fades them out over 320 ms, then settles the clean text in from a 6px blur over 0.5s. The Raw pipe skips the strike. With reduced motion the result shows at once and the caret does not blink.

### Settings Header Band
The top of each Settings page: the field inside an 18pt rounded rectangle at least 112pt tall, with 26pt × 22pt padding, a 26pt bold title, a subtitle at white 80%, and the idle pill preview. It always uses the dark appearance, whatever the system appearance.

### Transform Picker
A 330pt card of veiled glass with a 20pt radius and 14pt padding: a semibold title and a close button, the selection preview, numbered rows with one highlight (white 16%) that the pointer and the ↑ ↓ keys share, as in a menu; Return runs the highlighted row, a hairline, and the "Speak an instruction" row.

### Onboarding Progress
One capsule dot per step (five, or six with an Anthropic key), 6pt tall: the current step is 18pt wide at white 95%; the others are 6pt wide at white 30%. Steps cross-fade over 0.25s.

### Onboarding Steps
Welcome, Speech model, Permissions, Pipes, Try dictation, then Try a pipe on your text when there is a key: the dictation layer first, then pipes as an option, then a real try of each layer.
- **Welcome:** centered between the dots and the caption: the mark, the title, one sentence on what Talky does, then three beats on the field (no panel): a large fn key cap, a waveform symbol and a text cursor symbol, 36pt tall, with 13pt labels (Hold fn, Speak, Let go. Talky types.) in 140pt columns and white 40% arrows between them. A caption says the try comes at the end of setup.
- **Speech model:** a glass panel with one row (an indigo tile, the model name, its size or download progress, and "Ready" in system green). The footer button starts the download and moves on; the download continues in the background.
- **Pipes:** the title with an "Optional" glass capsule beside it (never a label above the title), a subtitle that names both uses (what you say, and text you select), the example panel (You say, the clickable chips, Talky types with the Rewrite Reveal), then two fact tiles side by side, 12pt apart and of equal height: "Selected text too" (a Selection Blue icon tile, and the user's transform key in semibold) and "Your own pipes" (an indigo plus tile, the names of the built-in pipes and "Write more in Settings"). Each tile is glass with a 14pt radius and 12pt padding: a 20pt icon tile and a 13pt semibold title, then 12pt text at white 78%. Then the key: the headline "To turn on pipes, add your Anthropic API key", a caption on what pipes send and who bills, the field with Test Key, and the test result. The primary button follows the key: "Skip for Now" when the field is empty; "Continue" when there is a key (it tests an untested key first and goes on when Anthropic accepts it); a disabled "Continue" with a plain "Skip for Now" when Anthropic refuses the key.
- **Try dictation:** a 132pt glass text box the user dictates into, a status block under it (what blocks Talky; or key caps for fn, fn fn and esc, and with a key also 1–9; or a green "That's Talky."), and the fn emoji-picker tip at the bottom. With a key its button is Continue; without one it is the last step.
- **Try a pipe on your text:** only with a key. A 160pt glass text box that starts with a hurried draft message, focused and all selected, so the first tap of the transform key opens the picker. Under it: key caps for the transform key, 1–9 and esc; or a green "Claude rewrote it." with a small "Restore the Text" button to try another pipe. A warning with a button replaces them when Accessibility is off.
- **After setup:** Finish opens Settings on Pipes. If Talky can't dictate yet (a permission is off, or the model is missing), it opens on General. Closing the window early opens nothing.
- **Key caps (native):** 11pt semibold on white 16% with a white 26% rim, 5pt radius, at least 22 × 20pt. The large welcome cap is 15pt, 8pt radius, at least 44 × 36pt. On plain Settings panels the caps use the primary label color: an 8% fill and a 16% rim.

## Do's and Don'ts

### Do:
- **Do** put every Talky-world surface (the web page, the onboarding window, the Settings header band, pill previews) on the one color field.
- **Do** put reading text in panels on deep glass with its 42% navy floor; keep light glass for the nav, buttons, the pill, chips and key caps.
- **Do** draw native glass through the shared glass modifier: Liquid Glass with a tint on macOS 26 and later, the ultra-thin material with a 22% white rim and a soft shadow before that.
- **Do** add the navy veil to any native glass that floats over other apps.
- **Do** show the idle pill in every still preview.
- **Do** keep the web pill in its fixed 272px slot so the chips never move.
- **Do** keep the filler strike: mark "um", "so" and "like", strike them for 900 ms, then fade and settle.
- **Do** keep both Settings pages on the shared 20pt column, with the header band on top and Settings groups below.
- **Do** leave native controls in their system styles; in Settings the field stays inside the header band.
- **Do** stop the field drift, the caret blink and the settle animation under reduced motion.

### Don't:
- **Don't** use Live Red for anything except the dot of a live microphone.
- **Don't** use hard, zero-blur offset shadows.
- **Don't** put reading text on light glass or on a fill below the 42% deep-glass floor.
- **Don't** use violet, blue or peach as text, fills, borders or card tints on glass surfaces; they are light in the field.
- **Don't** use the field's radial lights as glows on cards or buttons.
- **Don't** add a second typeface or a display font; SF Pro is the voice.
