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
  ink-muted: '#6b7280'
  ink-faint: '#9ca3af'
  ink-dark: '#ffffff'
  ink-muted-dark: '#a8a29e'
  ink-faint-dark: '#78716c'
  state-danger: '#dc2626'
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
  xs: '4px'
  sm: '8px'
  md: '16px'
  lg: '24px'
  xl: '32px'
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
    backgroundColor: '{colors.crt-amber}'
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
- **Ink muted** (`#6b7280` light / `#a8a29e` dark): Subtitles, secondary metadata.
- **Ink faint** (`#9ca3af` light / `#78716c` dark): Helper text, "last synced" labels — the quietest tier.

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

- **Page title** (700, `1.875rem` / 30px, `tracking-tight`): The H1 in `PageHeader`. One per screen. Bold and tracking-tight — confident without being loud. A small variant (`text-2xl` / 24px) for sub-pages.
- **Section heading** (600, `1.125rem` / 18px): The `SectionHeading` H2 with a `size-5` CRT Amber icon to its left. Splits a page into named regions.
- **Body** (400, `1rem` / 16px, line-height `1.5`): The default. Anything a user needs to read at a glance is body size. Cap at 65–75ch where prose-like.
- **Label** (500, `0.875rem` / 14px, line-height `1.5`): Form labels, button text, primary metadata. The 14px tier is for _deliberate_ uses, not "small text".
- **Meta** (400, `0.875rem` / 14px, sometimes `0.75rem` / 12px): Captions, "last synced X ago", timestamps, helper text under inputs. The quietest tier; lives in `ink-faint`.

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
- **Hover ring on interactive cards** (`ring-2 ring-rose-500`): A 2px Attention Red ring appears on hover for clickable cards. The ring _is_ the hover affordance — no scale, no shadow change.

### Named Rules

**The Calm-Field Rule.** Static content is flat and ringed; saturated lift is reserved for things you can act on. If a card is glowing without being clickable, the glow is wrong.

**The Press-Don't-Lift Rule.** Active states press in (inset shadow, brightness-95), they don't pop out. The exception is hover — hover gets a ring, never a translation.

## 5. Components

### Buttons (`AppButton`)

- **Shape:** Rounded `6px` (`rounded-md`), `font-semibold`, `shadow-sm`, `transition-colors`. Three sizes: `sm` (`px-3 py-1.5 text-sm`), `md` (`px-3 py-2 text-sm`, default), `lg` (`px-6 py-4 text-lg`).
- **Primary** (Attention Red, `#e11d48`, white text): The single "do this" button on a screen — and the only saturated button variant inside the authenticated shell. Hovers to `#f43f5e`.
- **Secondary** (`#f3f4f6` light / `#44403c` dark, ink text): The neutral button. Cancel, Back, "Got it" dismissals, secondary actions.
- **Cyan-soft** (`#cffafe` light / `#164e63`-tinted dark, cyan-700 text): A quiet chip-style button for "incoming / good news" row actions — most often "Mark as received" on settlement rows. Tinted background + saturated text mirrors the AppBadge pattern.
- **Amber-soft** (`#fde68a` light / amber-900-tinted dark, amber-900 text): The dual to cyan-soft for "outgoing / needs attention" row actions — most often "Pay via QR" on settlement rows. Sits a step deeper than cyan-soft because it lives on the amber-tinted `action` card variant; same visual role, different absolute weight.
- **Amber** (CRT Amber, `#d97706`, white text): Pre-auth surfaces only (Login, Auth Verify, Invite Accept) — the amber voice carries the brand on screens with no nav present. Don't use inside the authenticated shell, where the amber nav already carries that voice.
- **Danger** (`#dc2626`, white text): Destructive actions. Pairs with `confirm` flows.
- **Loading state:** Replaces the slot with an animated spinner (`animate-spin` on a 16px SVG) plus the `loadingLabel` prop. The button width does not collapse — the action stays where the user clicked.
- **Focus:** `focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-rose-500`. Attention Red ring on every button regardless of variant.

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
- **Internal Padding:** `p-6` (24px) when `padded` is true. Cards without `padded` are bare containers — typography and spacing come from inside.

### Inputs (`FormInput`)

- **Style:** `bg-gray-100` light / `bg-white/5` dark, `outline-1 -outline-offset-1 outline-gray-300` light / `outline-white/10` dark, `rounded-md` (6px), `px-3 py-1.5`, `text-base` (mobile) / `text-sm/6` (desktop).
- **Label:** Above the field, `text-sm/6 font-medium`, ink color.
- **Focus:** `focus:outline-2 focus:-outline-offset-2 focus:outline-rose-500`. The Attention Red ring is the system-wide focus signal — same on buttons, cards, modals, inputs.
- **Prefix:** Optional inline prefix slot (currency, URL scheme) sits inside the same outlined shell, separated visually by a `select-none` ink-muted span.
- **Disabled:** `disabled:opacity-50` plus `disabled:cursor-not-allowed`.

### Badges (`AppBadge`)

- **Shape:** `rounded-full`, `text-xs font-medium`, `px-2 py-0.5` (xs) or `px-2.5 py-0.5` (sm).
- **Variants:** Six tinted variants (`green`, `red`, `yellow`, `amber`, `blue`, `gray`). Each is a soft tinted background with a saturated ink color (e.g. `bg-green-100 text-green-700` light / `bg-green-900 text-green-300` dark).
- **Rule:** Badges carry state, not decoration. A badge without a meaning is a violation.

### Avatars (`AppAvatar`)

- **Shape:** `rounded-full`, `font-semibold`, initials only — no image avatars by design.
- **Variants:** `rose` (default — soft rose tint with rose ink), `amber` (CRT-warm — amber tint with amber ink), `nav` (white-ink-on-amber-hover for the top nav).
- **Sizes:** `sm` (32px), `md` (40px), `lg` (48px).

### Modal (`BaseModal`)

- **Element:** Native `<dialog>` with `showModal()`. Backdrop is `bg-gray-500/85` (light) / `bg-stone-900/80` (dark).
- **Shape:** `rounded-lg`, `shadow-xl`, `ring-1 ring-black/10`, `p-4 sm:p-6`. Five widths (`sm` through `2xl`).
- **Motion:** 200ms `cubic-bezier(0.25, 1, 0.5, 1)` ease-out — fades + slides 8px up + scales from 0.98. Backdrop fades with the same curve. `@starting-style` and `allow-discrete` carry the entry transition under modern browsers; `prefers-reduced-motion` collapses to 0.01ms.
- **Close:** Top-right X button (`XMarkIcon`), keyboard `Escape`, backdrop click. Title is `text-lg font-semibold` — same scale as a section heading.

### Top navigation (`AuthenticatedLayout`)

- **Style:** `sticky top-0 z-40`, `bg-nav` (CRT Amber Bright `#f59e0b` light / CRT Amber Deep `#b45309` dark), `h-16` (64px), max-width `7xl` (1280px) with `px-4 sm:px-6 lg:px-8` padding.
- **Brand:** Workspace name as `text-xl font-bold`. With multiple workspaces, a chevron opens a HeadlessUI Menu for switching.
- **Items:** Five primary nav items (Dashboard, Events, Tasks, Settle up, Members), `text-sm font-medium`. Active item carries `bg-nav-active` plus an inset shadow (`inset 0 1px 2px rgba(0,0,0,0.15)`).
- **Right rail:** Stale-cache hint, connection badge ("Offline" pill on `bg-gray-900/40`), dark-mode toggle, profile avatar.
- **Mobile:** HeadlessUI `Disclosure` collapses to a hamburger; expanded panel mirrors desktop nav.

### Section heading (`SectionHeading`)

- **Shape:** `text-lg font-semibold` ink, `mb-4` margin, with a `size-5` Heroicons icon in `text-amber-600 dark:text-amber-400` to the left of the title.
- **Right slot:** Optional action slot — typically a `TextButton` ("View all", "Edit") or a count.
- **Rule:** The amber-icon section header is the system's _only_ mandatory color use — every region of every page is announced this way.

### Empty states (`EmptyState`)

- **Shape:** Centered `py-12`, `mx-auto` Heroicons icon at 48px in `text-amber-500` (light) / `text-amber-400` (dark), `text-sm font-semibold` heading, `text-base text-gray-500` description, slot for an action button below.
- **Voice:** One sentence of context, one sentence of "what you can do next". No illustrations, no marketing copy, no fine print.

### Named Rules

**The Quiet-Surface Rule.** Cards, inputs, modals, and section bodies stay in neutrals. Saturation belongs to actions and states — buttons, focus rings, badges, the nav. A card that is "themed" with a brand color is a violation unless it is the `action` or `urgent` variant.

**The One-Action Rule.** Each card or modal carries at most one Primary button. Secondary actions are TextButtons or the secondary button variant. If you need two primaries, you are showing two screens.

**The List-Row Rule.** Repeated row actions in a list are _not_ Primary, even when they're the row's main button. A column of five Attention Red buttons stacked down the page breaks the principle that saturation is rare and meaningful. Row actions use `secondary`, `cyan-soft`, or `amber-soft` instead. Reserve Primary for one page-level CTA at most.

**The Dual-Coding Rule.** Where rows convey directional meaning (incoming vs outgoing, gain vs spend), pair `cyan-soft` with `amber-soft` so the button colors echo the row's other signals (card variant, amount text). The two soft variants exist as a dual; if you use one, you usually want the other on its counterpart row.

## 6. Do's and Don'ts

### Do:

- **Do** keep ≥90% of any screen in neutrals. The bright voices (CRT Amber `#d97706`, Attention Red `#e11d48`, Navigator Cyan `#0891b2`) earn their saturation by being rare.
- **Do** put `focus-visible:outline-rose-500` on every interactive element. The Attention Red ring is the system-wide focus signal.
- **Do** use Inter Variable at 16px for primary content. Reach for `text-sm` / `text-xs` only for secondary metadata that the user does not need to read first.
- **Do** lead each screen region with a `SectionHeading` — `text-lg font-semibold` plus a `text-amber-600` icon. This is the only mandatory color use in the body of a page.
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
