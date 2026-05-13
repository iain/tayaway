---
name: Tayaway
description: A coordination layer for friend groups planning trips, parties, and hangouts together.
colors:
  crt-amber: '#d97706'
  crt-amber-bright: '#f59e0b'
  crt-amber-deep: '#b45309'
  crt-amber-tint: '#fffbeb'
  attention-red: '#e11d48'
  attention-red-bright: '#f43f5e'
  attention-red-tint: '#ffe4e6'
  navigator-cyan: '#0891b2'
  navigator-cyan-bright: '#22d3ee'
  navigator-cyan-deep: '#0e7490'
  surface: '#ffffff'
  surface-page: '#f3f4f6'
  surface-sunken: '#e5e7eb'
  surface-dark: '#292524'
  surface-page-dark: '#1c1917'
  surface-raised-dark: '#44403c'
  ink: '#111827'
  ink-muted: '#4b5563'
  ink-faint: '#4b5563'
  ink-dark: '#ffffff'
  ink-muted-dark: '#a8a29e'
  ink-faint-dark: '#a8a29e'
  state-danger: '#b91c1c'
  state-danger-outline: '#b91c1c'
  state-danger-tint: '#fef2f2'
  state-warning-tint: '#fffbeb'
  state-success: '#16a34a'
  state-success-tint: '#dcfce7'
typography:
  page-title:
    fontFamily: 'Inter Variable, ui-sans-serif, system-ui, sans-serif'
    fontSize: '1.875rem'
    fontWeight: 700
    lineHeight: '2.25rem'
    letterSpacing: '-0.025em'
  section-heading:
    fontFamily: 'Inter Variable, ui-sans-serif, system-ui, sans-serif'
    fontSize: '1.125rem'
    fontWeight: 600
    lineHeight: '1.75rem'
    letterSpacing: 'normal'
  body:
    fontFamily: 'Inter Variable, ui-sans-serif, system-ui, sans-serif'
    fontSize: '1rem'
    fontWeight: 400
    lineHeight: '1.5rem'
    letterSpacing: 'normal'
  label:
    fontFamily: 'Inter Variable, ui-sans-serif, system-ui, sans-serif'
    fontSize: '0.875rem'
    fontWeight: 500
    lineHeight: '1.5rem'
    letterSpacing: 'normal'
  meta:
    fontFamily: 'Inter Variable, ui-sans-serif, system-ui, sans-serif'
    fontSize: '0.875rem'
    fontWeight: 400
    lineHeight: '1.25rem'
    letterSpacing: 'normal'
rounded:
  sm: '4px'
  md: '6px'
  lg: '8px'
  full: '9999px'
spacing:
  card: '24px'
  section: '32px'
  heading: '16px'
components:
  button-primary:
    backgroundColor: '{colors.attention-red}'
    textColor: '{colors.ink-dark}'
    rounded: '{rounded.md}'
    padding: '8px 12px'
  button-primary-hover:
    backgroundColor: '{colors.attention-red-bright}'
  button-secondary:
    backgroundColor: '{colors.surface-page}'
    textColor: '{colors.ink}'
    rounded: '{rounded.md}'
    padding: '8px 12px'
  button-amber:
    backgroundColor: '{colors.crt-amber-deep}'
    textColor: '{colors.ink-dark}'
    rounded: '{rounded.md}'
    padding: '8px 12px'
  button-danger:
    backgroundColor: '{colors.state-danger}'
    textColor: '{colors.ink-dark}'
    rounded: '{rounded.md}'
    padding: '8px 12px'
  text-button:
    backgroundColor: 'transparent'
    textColor: '{colors.navigator-cyan}'
    rounded: '{rounded.sm}'
    padding: '0'
  card:
    backgroundColor: '{colors.surface}'
    textColor: '{colors.ink}'
    rounded: '{rounded.lg}'
    padding: '24px'
  card-action:
    backgroundColor: '{colors.state-warning-tint}'
    textColor: '{colors.ink}'
    rounded: '{rounded.lg}'
    padding: '24px'
  card-urgent:
    backgroundColor: '{colors.state-danger-tint}'
    textColor: '{colors.ink}'
    rounded: '{rounded.lg}'
    padding: '24px'
  input:
    backgroundColor: '{colors.surface-page}'
    textColor: '{colors.ink}'
    rounded: '{rounded.md}'
    padding: '6px 12px'
  badge:
    backgroundColor: '{colors.surface-page}'
    textColor: '{colors.ink-muted}'
    rounded: '{rounded.full}'
    padding: '2px 8px'
  nav-bar:
    backgroundColor: '{colors.crt-amber-bright}'
    textColor: '#000000'
    height: '64px'
---

# Design System: Tayaway

## 1. Overview

**Creative North Star: "The Coordinator's Hand-off"**

Tayaway is the friend who hands the group exactly what they need, exactly when they need it. The interface is not a place to hang out; it is a place to settle a question, file an expense, or check whose turn it is — then leave. Every screen is a hand-off. Most of the surface stays calm and quiet so the actionable thing reads loudly: a soft white field, a hairline ring, muted body text, and then a single warm-and-bright punctuation — the red button, the amber nav, the cyan link — that tells you what to do next.

The system is **Restrained** as a color strategy with a deliberate **bright-action exception**: 90%+ of any screen is hushed neutrals, and the remaining slice is intentionally vivid. Layout is flat at rest with thin rings and small ambient shadows; depth shows up only when something is acting (a hover, a modal, a pending pill). Typography is Inter Variable used at body size by default — small text is a deliberate choice, not a default. Light and dark mode are equal citizens, both designed for the same hand-off feel.

This system explicitly rejects engagement-driven social aesthetics (no likes, no comments, no activity feed visuals), enterprise/configuration-heavy chrome (no dense sidebars, no view-builder shells, no gradient-and-card SaaS templates), and the hero-metric / identical-card-grid clichés.

**Key Characteristics:**

- Restrained surface, bright-action punctuation
- Flat at rest, lifts only on interaction
- Inter Variable, body-size-by-default
- Light and dark mode equally first-class
- Mobile and desktop equally first-class

## 2. Colors: The CRT Amber Palette

A hushed neutral field with three saturated voices that earn their visibility — amber for orientation, red for attention, cyan for navigation. Color saturation is rare; when it appears, it means something.

### Primary

- **CRT Amber** (`#d97706`): The brand voice. The sticky top nav (`#f59e0b` light / `#b45309` dark), the section-heading icon, the PWA theme color, the staleness banner, the offline-pending pill. CRT Amber says "you are here, this app is real". The bright variant on the nav is intentionally CRT-glow loud — a screen you remember.

### Secondary

- **Attention Red** (`#e11d48`): Primary buttons, focus rings, the brand pulse on form inputs. Attention Red is the answer to "what should I click?". It hovers to a brighter `#f43f5e`. Used on ≤10% of any screen.

### Tertiary

- **Navigator Cyan** (`#0891b2`): Inline links and tertiary text-buttons. Old-school HTML link energy, but warmer and more confident. Underlined by default in `TextButton`. Hovers to `#0e7490` (light) / `#22d3ee` (dark).

### Neutral

- **Page surface** (`#f3f4f6` light / `#1c1917` dark): The background of the world. Light mode uses Tailwind's gray for cool restraint; dark mode uses stone for warmth — both intentional.
- **Card surface** (`#ffffff` light / `#292524` dark): Where content sits.
- **Sunken / raised** (`#e5e7eb` light / `#44403c` dark): Secondary buttons, dividers, raised input shells.
- **Ink** (`#111827` light / `#ffffff` dark): Primary text.
- **Ink muted** (`#4b5563` light / `#a8a29e` dark): Subtitles, secondary metadata. Tuned to clear WCAG AA on the page surface.
- **Ink faint** (`#4b5563` light / `#a8a29e` dark): Helper text, "last synced" labels. Visually identical to `ink-muted` today; the semantic tier is preserved in code so a future re-introduction of a distinct faint shade has a place to land.

### State Tints

- **Urgent tint** (`#fef2f2`): The `urgent` card variant. Pairs with a red ring; never used as raw text background.
- **Action tint** (`#fffbeb`): The `action` card variant — "this needs your attention but isn't on fire".
- **Success tint** (`#dcfce7`): The success badge background only; never a full-card surface.

### Named Rules

**The Bright-Action Rule.** Only buttons, focus rings, the nav bar, and pending-state indicators carry full saturation. Everything else — body, cards, headings, dividers — stays in neutrals. If two saturated elements appear in the same viewport, one of them is wrong.

**The Two-Hue Restraint.** A single screen uses CRT Amber _or_ Attention Red at full strength, not both — the nav already carries amber, so the page-level action layer leans on red. Cyan is permitted alongside either, because it reads as a link rather than as an action.

**The No-Decoration Rule.** Color never decorates. If a color is on screen, it carries meaning — orientation (amber), attention (red), link (cyan), or state (red/green/amber tint).

## 3. Typography

**Display / Body / Label / Mono Font:** Inter Variable (with `ui-sans-serif, system-ui, sans-serif` fallback).

**Character:** A single voice, sized for clarity, weighted for hierarchy. No display serif, no monospace numerics, no custom-fitted display face — Inter Variable carries everything because the system is about _information_, not _atmosphere_. The pairing is itself: Inter from page title to footnote, distinguished by weight and scale, not family.

### Hierarchy

Each tier ships as a single Tailwind utility (`text-{tier}`) that bundles size, line-height, weight, and letter-spacing. Components reach for the utility, not raw `text-lg font-semibold` combos.

- **Page title** (`text-page-title`, 700 / 30px / `tracking-tight`): The H1 in `PageHeader`. One per screen. A small variant (`text-page-title-sm`, 24px) exists for sub-pages.
- **Section heading** (`text-section-heading`, 600 / 18px): The `SectionHeading` H2 with a `size-5` CRT Amber icon to its left. Splits a page into named regions. Also the modal title.
- **Body** (`text-body`, 400 / 16px / line-height 1.5): The default. Anything a user needs to read at a glance is body size. Cap at 65–75ch where prose-like.
- **Label** (`text-label`, 500 / 14px / line-height 1.5): Form labels, button text, primary metadata. The 14px tier is for _deliberate_ uses, not "small text".
- **Meta** (`text-meta`, 400 / 14px / line-height 1.25): Captions, "last synced X ago", timestamps, helper text under inputs. The quietest tier; lives in `ink-faint` or `ink-muted`.

### Named Rules

**The Body-Size-By-Default Rule.** Primary content uses 16px. `text-sm` and `text-xs` are intentional choices for secondary metadata, never reflexive defaults. If the user has to squint to read it, it isn't body content; if it is body content, it isn't `text-sm`.

**The Single-Family Rule.** Inter Variable for everything. No display face for marketing flourishes. No monospace for data — Inter has tabular figures (`font-feature: tnum`) when alignment matters.

## 4. Elevation

Flat at rest, lifts on interaction. The system uses a thin-ring + light-shadow vocabulary so most surfaces sit calmly on the page; depth is reserved for _acting_ surfaces — modals lift hard, interactive cards add a hover ring, primary buttons carry a small shadow that makes them feel pressable, and active nav items push _down_ with an inset shadow rather than out. Dark mode uses an additional inset highlight on cards (`inset 0 1px 0 rgba(255,255,255,0.06)`) to keep edges legible against the stone-900 page.

### Shadow Vocabulary

- **Hairline ring** (`ring-1 ring-black/5` light / `ring-1 ring-white/[0.06]` dark): The default card edge. Almost invisible until you look for it.
- **Card shadow** (`shadow` — `0 1px 3px 0 rgb(0 0 0 / 0.1), 0 1px 2px -1px rgb(0 0 0 / 0.1)`): The default `BaseCard` lift. Just enough to separate from the page surface.
- **Dark card glow** (`0 2px 8px rgba(0,0,0,0.25), inset 0 1px 0 rgba(255,255,255,0.06)`): The dark-mode card. The inset highlight is a one-pixel light edge that simulates the top facet under ambient light.
- **Button shadow** (`shadow-sm` — `0 1px 2px 0 rgb(0 0 0 / 0.05)`): Primary/secondary/cyan/amber/danger buttons. Hairline lift; the button feels like a chip.
- **Inset active** (`inset 0 1px 2px rgba(0,0,0,0.15)` light / `0.35` dark): The active nav item. Pressed, not raised.
- **Modal shadow** (`shadow-xl` — `0 20px 25px -5px rgb(0 0 0 / 0.1), 0 8px 10px -6px rgb(0 0 0 / 0.1)`): The only place the system genuinely lifts. Modals are loud about being modal.
- **Hover ring on interactive cards** (`ring-2 ring-ring-hover`, a darkened hairline at ~18% opacity): A 2px hairline deepens around the card on hover. The ring _is_ the hover affordance — no scale, no shadow change. The colour is deliberately neutral rather than saturated rose so a hover-on-card and a focus-on-button never read as the same signal.

### Named Rules

**The Calm-Field Rule.** Static content is flat and ringed; saturated lift is reserved for things you can act on. If a card is glowing without being clickable, the glow is wrong.

**The Press-Don't-Lift Rule.** Active states press in (inset shadow, brightness-95), they don't pop out. The exception is hover — hover gets a ring, never a translation.

## 5. Components

### Buttons (`AppButton`)

- **Shape:** Rounded `6px` (`rounded-md`), `font-semibold`, `shadow-sm`, `transition-colors`. Three sizes: `sm` (`px-3 py-1.5 text-sm`), `md` (`px-3 py-2 text-sm`, default), `lg` (`px-6 py-4 text-lg`).
- **Primary** (Attention Red, `#e11d48`, white text): The single "do this" button on a screen — and the only saturated button variant inside the authenticated shell. Hovers to `#f43f5e`.
- **Secondary** (`#f3f4f6` light / `#44403c` dark, ink text): The neutral button. Cancel, Back, "Got it" dismissals, secondary actions.
- **Inflow** (`#cffafe` light / `#164e63`-tinted dark, cyan-800 text): A quiet chip-style button for "incoming / good news" row actions — most often "Mark as received" on settlement rows. Tinted background + saturated text mirrors the AppBadge pattern.
- **Outflow** (`#fde68a` light / amber-900-tinted dark, amber-900 text): The dual to inflow for "outgoing / needs attention" row actions — most often "Pay via QR" on settlement rows. Sits a step deeper than inflow because it lives on the amber-tinted `action` card variant; same visual role, different absolute weight.
- **Amber** (CRT Amber Deep, `#b45309`, white text): Pre-auth surfaces only (Login, Auth Verify, Invite Accept) — the amber voice carries the brand on screens with no nav present. Sits one step deeper than the nav's `#d97706` so white text clears WCAG AA. Don't use inside the authenticated shell, where the amber nav already carries that voice.
- **Danger** (`#b91c1c`, white text): Destructive actions. Sits a step darker than Attention Red so "irreversible" and "do this" never read as the same button. Pairs with `confirm` flows.
- **Loading state:** Replaces the slot with an animated spinner (`animate-spin` on a 16px SVG) plus the `loadingLabel` prop. The button width does not collapse — the action stays where the user clicked.
- **Focus:** `focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-focus`. Attention Red ring on every button regardless of variant, served through the `--color-focus` token so the ring is one place to change.

### Text buttons (`TextButton`)

- **Shape:** Inline, no padding, `text-sm`, underlined by default for the primary variant.
- **Primary** (Navigator Cyan): The HTML-link energy. `text-cyan-600 underline hover:text-cyan-700`.
- **Secondary** (`ink-muted`): Quiet inline action. No underline.
- **Danger** (`text-red-600`): Inline destructive. Pairs with confirmation.

### Cards (`BaseCard`)

- **Corner Style:** `rounded-lg` (8px).
- **Default:** White on light / stone-800 on dark, `shadow` (light) / `shadow + inset highlight` (dark), hairline `ring-1` in `black/5` light / `white/[0.06]` dark.
- **Action variant:** `bg-amber-50/60` with `ring-2 ring-amber-300/50`. Reads as "this is for you to look at" — used for staleness banners, action prompts.
- **Urgent variant:** `bg-red-50` with `ring-2 ring-red-300/60`. Reserved for genuine alarms (overdue, broken sync, conflicting actions).
- **Interactive:** Adds `hover:ring-2 hover:ring-rose-500`, `active:scale-[0.99]`, `active:brightness-95` (dark: `brightness-110`). Never wraps a non-actionable surface.
- **Internal Padding:** `p-card` (24px) when `padded` is true. Cards without `padded` are bare containers — typography and spacing come from inside.

### Inputs (`FormInput`)

- **Style:** `bg-gray-100` light / `bg-white/5` dark, `outline-1 -outline-offset-1 outline-gray-300` light / `outline-white/10` dark, `rounded-md` (6px), `px-3 py-1.5`. The field text stays at `text-base` (16px) on mobile so iOS Safari doesn't auto-zoom the page on focus, and tightens to `text-sm/6` on `sm:` and up — the one place the system uses a responsive font-size on purpose, which is why it doesn't ride a `text-*` token.
- **Label:** Above the field, `text-label`, ink color.
- **Focus:** `focus:outline-2 focus:-outline-offset-2 focus:outline-focus`. The Attention Red ring is the system-wide focus signal — same on buttons, cards, modals, inputs.
- **Prefix:** Optional inline prefix slot (currency, URL scheme) sits inside the same outlined shell, separated visually by a `select-none` ink-muted span.
- **Error:** Pass an `error` string; the field swaps to a 2px `outline-state-danger-outline` (one step deeper than the badge ink so it carries on its own), keeps that outline on focus rather than reverting to the rose ring, sets `aria-invalid` + `aria-describedby`, and renders the message below in `text-state-danger-ink`.
- **Disabled:** `disabled:opacity-50` plus `disabled:cursor-not-allowed`.

### Badges (`AppBadge`)

- **Shape:** `rounded-full`, `text-xs font-medium`, `px-2 py-0.5` (xs) or `px-2.5 py-0.5` (sm).
- **Variants:** Six state-named variants (`success`, `danger`, `warning`, `pending`, `info`, `neutral`). Each pairs a soft tinted fill with a saturated ink, drawn from `--color-state-*` tokens so dark mode swaps automatically.
- **Rule:** Badges carry state, not decoration. A badge without a meaning is a violation — the API enforces this by refusing color-name variants.

### Avatars (`AppAvatar`)

- **Shape:** `rounded-full`, `font-semibold`. Initials today; image upload isn't built yet and would slot into the same disk when it lands.
- **Variants:** `neutral` (default — soft rose tint with rose ink), `pending` (CRT-warm — amber tint with amber ink), `nav` (white-ink-on-amber-hover for the top nav).
- **Sizes:** `sm` (32px), `md` (40px), `lg` (48px).

### Modal (`BaseModal`)

- **Element:** Native `<dialog>` with `showModal()`. Backdrop is `bg-gray-500/85` (light) / `bg-stone-900/80` (dark).
- **Shape:** `rounded-lg`, `shadow-xl`, `ring-1 ring-black/10`, `p-4 sm:p-6`. Five widths (`sm` through `2xl`).
- **Motion:** 200ms `cubic-bezier(0.25, 1, 0.5, 1)` ease-out — fades + slides 8px up + scales from 0.98. Backdrop fades with the same curve. `@starting-style` and `allow-discrete` carry the entry transition under modern browsers; `prefers-reduced-motion` collapses to 0.01ms.
- **Close:** Top-right X button (`XMarkIcon`), keyboard `Escape`, backdrop click. Title uses `text-section-heading` with `mb-heading` underneath — same scale and spacing as a `SectionHeading`, so a modal opens "feeling like" a single page region.
- **Accessibility:** Native `<dialog>` + `showModal()` traps focus inside the modal, makes the page behind it inert, and routes `Escape` through a cancelable `cancel` event. `preventClose` blocks both the X button and the cancel route. The X button carries an `sr-only` "Close" label so screen readers announce its purpose.

### Top navigation (`AuthenticatedLayout`)

- **Style:** `sticky top-0 z-40`, `bg-nav` (CRT Amber Bright `#f59e0b` light / CRT Amber Deep `#b45309` dark), `h-16` (64px), max-width `7xl` (1280px) with `px-4 sm:px-6 lg:px-8` padding.
- **Brand:** Workspace name as `text-xl font-bold`. With multiple workspaces, a chevron opens a HeadlessUI Menu for switching.
- **Items:** Five primary nav items (Dashboard, Events, Tasks, Settle up, Members), `text-sm font-medium`. Active item carries `bg-nav-active` plus an inset shadow (`inset 0 1px 2px rgba(0,0,0,0.15)`).
- **Right rail:** Stale-cache hint, connection badge ("Offline" pill on `bg-gray-900/40`), dark-mode toggle, profile avatar.
- **Mobile:** HeadlessUI `Disclosure` collapses to a hamburger; expanded panel mirrors desktop nav.

### Section heading (`SectionHeading`)

- **Shape:** `text-section-heading` ink, `mb-heading` margin, with a `size-5` Heroicons icon in `text-amber-600 dark:text-amber-400` to the left of the title.
- **Right slot:** Optional action slot — typically a `TextButton` ("View all", "Edit") or a count.
- **Rule:** The amber-icon section header is the system's _only_ mandatory color use — every region of every page is announced this way.

### Time anchors (`TimeAnchor`)

- **Shape:** A native `<time datetime="…">` wrapped in a span that prepends an optional verb slot. The verb sets context ("Sent", "Last synced", "Daisy paid", "Expires"); the component appends the compact relative time.
- **Compact unit voice:** `m` (under an hour), `h` (under a day), `d` (under a week), `w` (under four weeks). Anything older falls back to a short absolute date. Past renders as `"3h ago"`, future as `"in 3h"`, anything within the last minute as `"just now"`. Long forms ("three hours ago") are a violation.
- **Live ticking:** Reads from the shared `useMinuteTicker`, so an "8m ago" row becomes "9m ago" without a refresh and every TimeAnchor on a page agrees on what "now" means.
- **Rule:** Pick the verb in the right tense — `<TimeAnchor>Expired</TimeAnchor>` for past, `<TimeAnchor>Expires</TimeAnchor>` for future. The primitive doesn't try to be clever; the consumer chose the verb.

### Empty states (`EmptyState`)

- **Shape:** Centered `py-12`, `mx-auto` Heroicons icon at 48px in `text-amber-500` (light) / `text-amber-400` (dark), `text-sm font-semibold` heading, `text-base text-gray-500` description, slot for an action button below.
- **Voice:** One sentence of context, one sentence of "what you can do next". No illustrations, no marketing copy, no fine print.

### Named Rules

**The Quiet-Surface Rule.** Cards, inputs, modals, and section bodies stay in neutrals. Saturation belongs to actions and states — buttons, focus rings, badges, the nav. A card that is "themed" with a brand color is a violation unless it is the `action` or `urgent` variant.

**The One-Action Rule.** Each card or modal carries at most one Primary button. Secondary actions are TextButtons or the secondary button variant. If you need two primaries, you are showing two screens.

**The List-Row Rule.** Repeated row actions in a list are _not_ Primary, even when they're the row's main button. A column of five Attention Red buttons stacked down the page breaks the principle that saturation is rare and meaningful. Row actions use `secondary`, `inflow`, or `outflow` instead. Reserve Primary for one page-level CTA at most.

**The Dual-Coding Rule.** Where rows convey directional meaning (incoming vs outgoing, gain vs spend), pair `inflow` with `outflow` so the button colors echo the row's other signals (card variant, amount text). The two soft variants exist as a dual; if you use one, you usually want the other on its counterpart row.

## 6. Do's and Don'ts

### Do:

- **Do** keep ≥90% of any screen in neutrals. The bright voices (CRT Amber `#d97706`, Attention Red `#e11d48`, Navigator Cyan `#0891b2`) earn their saturation by being rare.
- **Do** put `focus-visible:outline-focus` on every interactive element. The Attention Red ring is the system-wide focus signal — one token, one place to change.
- **Do** use Inter Variable at 16px for primary content. Reach for `text-sm` / `text-xs` only for secondary metadata that the user does not need to read first.
- **Do** lead each screen region with a `SectionHeading` — `text-section-heading` plus a `text-amber-600` icon. This is the only mandatory color use in the body of a page.
- **Do** design dark mode at the same time as light mode. Both are first-class. Light uses cool gray neutrals; dark uses warm stone neutrals. Never copy values across.
- **Do** respect `prefers-reduced-motion`. The modal already collapses its 200ms entrance to 0.01ms; new motion must do the same.
- **Do** show what matters now. Surface the active event phase (voting, chores, expenses) as the dominant UI of any screen rooted in an event.
- **Do** announce state with icon + text + color, not color alone.

### Don't:

- **Don't** add likes, hearts, comments, activity feeds, post-style entries, follower counts, or any other engagement-loop pattern. Tayaway has nothing to sell users.
- **Don't** ship configuration-heavy chrome — no "configure your view", no view-builder, no settings the user shouldn't have to think about. The right view is the only view.
- **Don't** use the SaaS template aesthetic: no gradient hero, no sidebar shell, no identical card grids, no hero-metric template, no marketing-style feature cards.
- **Don't** use side-stripe borders (a colored `border-left: 4px` accent on a list item or callout). This is the system's strongest absolute ban.
- **Don't** use gradient text (`background-clip: text` over a gradient). Solid color, weight, and scale carry hierarchy.
- **Don't** use glassmorphism or backdrop-blur as decoration. The only `backdrop-filter` in the system is on the modal backdrop, which is a darkened scrim, not a frosted glass.
- **Don't** layer cards inside cards. Nested cards are always a structural mistake — split the page, or remove a layer.
- **Don't** reach for a modal first. Inline expansion, progressive disclosure, and dedicated routes beat modals for most state. Modals are for blocking confirms (delete, sign out) and short focused entry (new event).
- **Don't** put two saturated colors at full strength in the same viewport. CRT Amber on the nav is already there; the page action layer carries Attention Red, not also Amber.
- **Don't** size primary content at `text-sm`. If it matters, it's 16px.
- **Don't** decorate. If a color, icon, or shadow is on screen, it carries meaning. Decoration for decoration's sake violates the Quiet-Surface Rule.
- **Don't** add fine print, "learn more" links to nowhere, marketing-tone microcopy, or hedge language. Components say what they mean.
- **Don't** use bouncy or elastic motion. Ease-out only — the modal's `cubic-bezier(0.25, 1, 0.5, 1)` is the canonical curve.
- **Don't** animate CSS layout properties. Transform and opacity only, with `will-change` reserved for known-hot interactions.

## 7. Using the system in code

The design system lives in three places: `frontend/src/style.css` (the Tailwind `@theme` tokens), `frontend/src/components/common/` and `frontend/src/components/form/` (the primitives), and `/design` (the gallery — every primitive in every state, light and dark).

### Semantic tokens

`style.css` defines tokens that automatically swap in dark mode, so components don't need to carry `dark:` variants for color. Reach for these before raw Tailwind colors:

| Use                                | Token                                                                           |
| ---------------------------------- | ------------------------------------------------------------------------------- |
| Page background                    | `bg-surface-page`                                                               |
| Card / dialog surface              | `bg-surface`                                                                    |
| Sunken fill (input, secondary btn) | `bg-surface-sunken`                                                             |
| Action card variant                | `bg-surface-action` + `ring-ring-action`                                        |
| Urgent card variant                | `bg-surface-urgent` + `ring-ring-urgent`                                        |
| Body text                          | `text-ink`                                                                      |
| Muted text (subtitles, meta)       | `text-ink-muted`                                                                |
| Faint text (helper, "last synced") | `text-ink-faint`                                                                |
| Hairline edge / outline            | `outline-line` / `border-line` / `ring-ring-hairline`                           |
| Top-nav surfaces                   | `bg-nav` / `bg-nav-active` / `bg-nav-hover` / `text-nav-text`                   |
| Focus indicator (system-wide)      | `focus-visible:outline-focus`                                                   |
| Form-control error outline         | `outline-state-danger-outline` (one step deeper than `-ink`)                    |
| Badge / state tints                | `bg-state-{success,danger,warning,pending,info,neutral}-fill` + matching `-ink` |
| Soft button surfaces               | `bg-btn-{secondary,inflow,outflow}-fill` (+`-fill-hover`, `-ink`)               |
| Avatar variants                    | `bg-avatar-{default,pending}-fill` + matching `-ink`                            |
| Typography ramp                    | `text-{page-title,page-title-sm,section-heading,body,label,meta}`               |
| Spacing roles                      | `p-card` / `m-card` (24px), `mt-section` (32px), `mb-heading` (16px)            |

Saturated brand voices (`rose-`, `cyan-`, `amber-`) stay as raw Tailwind utilities — they carry meaning and shouldn't bleed into anonymous tokens.

### Rules for code

**Use the primitive, not the raw element.** `<AppButton>` over `<button>`, `<TextButton>` over `<a>`-styled-as-button, `<BaseCard>` over a hand-styled `<div>`. If the primitive doesn't fit, change the primitive — don't fork the styling inline.

**Color comes from tokens, not hex.** No `#` literals in components. New shades go in `style.css` or the existing `@theme` palette. The `--color-*` namespace is the contract.

**No `dark:` for color.** Surfaces, ink, and lines switch via tokens. `dark:` is reserved for genuinely dark-mode-only properties (e.g. the inset highlight on cards). If you find yourself writing `bg-X dark:bg-Y`, the right move is a token.

**Spacing comes from the Tailwind scale.** No arbitrary `p-[13px]`. The 4-px scale is the system; if a value needs to land off-grid, the surrounding layout is wrong. Three semantic roles are tokenised on top of that scale: `p-card` / `m-card` (24px) for card-and-page-header padding, `mt-section` (32px) for the gap between named regions on a page, and `mb-heading` (16px) for the gap below a `SectionHeading`. Reach for the role token where it fits so the value lives in one place.

**Add to the gallery when you add a primitive.** Anything in `components/common` or `components/form` should appear in `/design`. The gallery is the screenshot baseline — primitives missing from it have no regression coverage.

**Visual regression: `mise run e2e -- design-system`.** Diffs the gallery against `e2e/tests/design-system.spec.ts-snapshots/`, which holds the Linux-rendered baseline used by CI. After an intentional design change, refresh the baseline with `mise run e2e:snapshots:update` — the task dispatches a GitHub workflow that re-renders on Linux and pushes the updated images back to your branch, so the committed baseline stays platform-stable. Running `--update-snapshots` locally on macOS produces a darwin-suffixed image which is gitignored by design.
