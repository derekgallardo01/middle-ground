# Middle Ground — Brand Design System

> **Tagline:** Meet in the Middle.

## Brand Essence

Middle Ground is the operating system for shared decisions. It turns everyday requests — from date nights to dinner plans — into calm, collaborative workflows.

The brand should feel like a wellness app, not therapy software: **calm, positive, encouraging, modern, beautiful, and lighthearted.** It is never judgmental or clinical.

## Personality Keywords

- Calm
- Positive
- Encouraging
- Modern
- Beautiful
- Lighthearted
- Approachable
- Clear
- Collaborative
- Flexible
- Supportive

## Design Influences

- **Apple Calendar** — airy, clean, generous whitespace
- **Airbnb** — warm, human, inviting
- **Notion** — minimal, functional, considered
- **Duolingo** — playful, rewarding, gamified
- **Headspace** — mindful, soft, friendly

## Core Visual Metaphor

Two people coming together around a shared heart.

The logo mark shows two abstract figures — one in indigo, one in teal — with a coral heart where they meet. It represents empathy, compromise, and connection.

## Color Palette

### Primary Colors

| Token | Hex | Usage |
|-------|-----|-------|
| `--mg-indigo` | `#6366F1` | Primary brand color, CTAs, active states |
| `--mg-teal` | `#14B8A6` | Secondary, wellness, success, balance |
| `--mg-coral` | `#FF8FA3` | Heart accent, warmth, playful highlights |

### Supporting Accents

| Token | Hex | Usage |
|-------|-----|-------|
| `--mg-sunshine` | `#FFC857` | Celebrations, milestones, streaks |
| `--mg-lavender` | `#A78BFA` | Negotiation, compromise states |
| `--mg-sky` | `#7DD3FC` | Reschedule, notifications, freshness |

### Neutral Colors

| Token | Hex | Usage |
|-------|-----|-------|
| `--mg-sand` | `#F7F6F3` | App background, canvas |
| `--mg-surface` | `#FFFFFF` | Cards, sheets, modals |
| `--mg-warm-gray-100` | `#F0EFEC` | Subtle dividers, hover backgrounds |
| `--mg-warm-gray-200` | `#E4E3E0` | Borders, inactive states |
| `--mg-warm-gray-400` | `#A1A1AA` | Placeholder text, disabled |
| `--mg-warm-gray-600` | `#71717A` | Secondary text, captions |
| `--mg-slate` | `#334155` | Primary text, headings |

### Semantic Colors

| Token | Hex | Usage |
|-------|-----|-------|
| `--mg-success` | `#14B8A6` | Accepted, complete, healthy communication |
| `--mg-warning` | `#FFC857` | Needs attention, pending |
| `--mg-error` | `#FF8FA3` | Declined, blocked — kept soft, never alarming |
| `--mg-negotiate` | `#A78BFA` | Counter-offers, compromise |
| `--mg-reschedule` | `#7DD3FC` | Later, postponed |
| `--mg-saved` | `#FF8FA3` | Saved for later, favorites |

### Gradients

- **Middle Gradient (primary):** `linear-gradient(135deg, #6366F1 0%, #818CF8 50%, #14B8A6 100%)`
- **Warm Gradient:** `linear-gradient(135deg, #FF8FA3 0%, #FFC857 100%)`
- **People Gradient:** `linear-gradient(135deg, #6366F1 0%, #14B8A6 100%)`

---

## Typography

**Shipped faces: the system family.** Headings use **SF Pro Rounded** (`Font.Design.rounded`)
and body copy uses **SF Pro** (`.default`).

This is a deliberate choice rather than a shortfall. SF Pro Rounded carries the same warm,
approachable tone the brand asks for, and using the system family means:

- no font binaries in the bundle and no registration step,
- automatic Dynamic Type, optical sizing and full glyph coverage,
- correct rendering in every locale we might later ship to.

Sizes and weights below are the brand's own and are implemented exactly, via `MGTextStyle`
and the `.mgFont(_:)` modifier, which drives them through `@ScaledMetric` so they scale with
the reader's text-size setting.

| Token | Size | Weight | Face |
|-------|------|--------|------|
| `displayXL` | 48 | Bold | Rounded |
| `displayL` | 36 | Bold | Rounded |
| `h1` | 28 | Bold | Rounded |
| `h2` | 22 | Semibold | Rounded |
| `h3` | 18 | Semibold | Rounded |
| `body` | 16 | Regular | Default |
| `bodySmall` | 14 | Regular | Default |
| `caption` | 12 | Semibold | Default |

> Poppins and Inter were the original specification. They are not shipped; if the brand later
> requires them, both are SIL Open Font License and can be vendored into
> `Sources/MiddleGround/Resources/Fonts/`, declared via `UIAppFonts` in `App/project.yml`, and
> swapped in behind `MGTextStyle` without touching a single call site.

## Spacing & Shape

### Border Radius

- `--radius-sm`: 8px
- `--radius-md`: 16px
- `--radius-lg`: 24px
- `--radius-xl`: 32px
- `--radius-full`: 9999px (pills, avatars)
- `--radius-app-icon`: 22.37%

### Shadows

- `--mg-shadow-sm`: `0 1px 2px rgba(51, 65, 85, 0.06)`
- `--mg-shadow-md`: `0 4px 12px rgba(51, 65, 85, 0.08)`
- `--mg-shadow-lg`: `0 12px 32px rgba(51, 65, 85, 0.12)`
- `--mg-shadow-glow`: `0 8px 24px rgba(99, 102, 241, 0.24)`

---

## Iconography & Illustration

### Icon Style

- Rounded 2px stroke caps and joins
- 24px default, 20px compact
- Consistent 2px stroke width
- Soft, friendly silhouettes

### Key Icons

- Requests
- Calendar
- People
- Activities
- AI Assistant
- Stats
- Profile

### Illustration Style

- Flat, organic shapes
- Two people + heart motif
- Soft, rounded figures
- Celebratory details: sparkles, confetti, hearts, checkmarks

---

## Motion & Celebration

- **Easing:** `cubic-bezier(0.25, 0.1, 0.25, 1.0)`
- **Bounce:** `cubic-bezier(0.34, 1.56, 0.64, 1)`
- **Durations:** 200ms micro, 300ms standard, 500ms emphasis

---

## Logo Usage

### Clear Space

Maintain clear space around the logo equal to the height of the lowercase "m" in the wordmark.

### Minimum Size

- Digital: 120px wide
- App icon: 60px @1x

### Color Versions

- **Full color:** indigo + teal figures with coral heart
- **Single color:** slate or white
- **Reversed:** white mark/wordmark on gradient or dark background

---

## App Icon

The app icon uses the two-figures-with-heart mark centered on a soft sand background inside a rounded square.

Export at:
- 1024×1024 (App Store)
- 180×180 (iOS home screen @3x)
- 120×120 (iOS home screen @2x)
- 512×512 (Android / web)
- 192×192 (Android / web)

---

## Voice & Tone

### Principles

- **Encouraging:** Celebrate progress, not perfection.
- **Clear:** No jargon, no clinical language.
- **Warm:** Write like a thoughtful friend.
- **Brief:** Respect people’s time.

### Examples

| Instead of... | Use... |
|---------------|--------|
| "Your request was rejected." | "They suggested another time." |
| "Conflict detected." | "Let's find a middle ground." |
| "You have 0 streak days." | "Start your first streak today." |
| "Task incomplete." | "One small step left." |

---

## Application Examples

- Empty states use soft illustrations and warm copy.
- Cards use white surfaces on sand backgrounds.
- Badges use pastel fills with dark text.
- Primary buttons are fully rounded pills in indigo.
- Streaks and XP use sunshine/yellow for celebration.
- Notifications use sky blue to feel helpful, not urgent.
