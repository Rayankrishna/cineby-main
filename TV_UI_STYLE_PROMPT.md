# Match the TV app's UI to the mobile sibling — colors, typography, animations

## Goal

The mobile sibling has a polished dark, Netflix-style look: deep charcoal
surfaces, a single vibrant red accent, gold secondary highlights, Manrope
typography, soft fade-and-slide page transitions, and a custom "squeeze"
press animation. Port that visual language exactly to the Android TV app
— with TV-specific adjustments for focus states (D-pad navigation makes
focus the dominant interaction, not tap).

This prompt is the complete visual spec. Apply it across every screen in
`lib/services/pages/` and any shared card / row widgets.

---

## 1. Color tokens

Define these once (e.g. `lib/services/theme.dart`) and use them everywhere
— **no raw hex literals in page code**:

```dart
class AppColors {
  static const background       = Color(0xFF18181A); // main scaffold bg
  static const surface          = Color(0xFF35343E); // cards, inputs, placeholders
  static const surfaceAlt       = Color(0xFF1F1E26); // floating nav, modals, toasts
  static const accentRed        = Color(0xFFEF0003); // primary CTA, focus ring, progress
  static const accentRedDark    = Color(0xFFC60002); // gradient end
  static const accentGold       = Color(0xFFF7BB0D); // ratings, bookmark, secondary focus
  static const splashSurface    = Color(0xFF292830); // splash screen bg
}
```

Text opacity ladder (Material's standard whites):

- `Colors.white`     — primary copy, titles
- `Colors.white70`   — meta info, time/duration, secondary copy
- `Colors.white54`   — labels, hints, dim icons
- `Colors.white38`   — placeholder/inactive text, empty-state icons
- `Colors.white30`   — input placeholder
- `Colors.white24`   — empty placeholder icons in cards
- `Colors.white12`   — divider lines, progress track

Theme seed in `lib/main.dart`:

```dart
theme: ThemeData(
  brightness: Brightness.dark,
  scaffoldBackgroundColor: AppColors.background,
  colorScheme: ColorScheme.fromSeed(
    seedColor: AppColors.accentRed,
    brightness: Brightness.dark,
    surface: AppColors.surface,
    background: AppColors.background,
  ),
  textTheme: GoogleFonts.manropeTextTheme(
    ThemeData.dark().textTheme.apply(
      bodyColor: Colors.white,
      displayColor: Colors.white,
    ),
  ),
  pageTransitionsTheme: const PageTransitionsTheme(builders: {
    TargetPlatform.android: FadeSlidePageTransitionsBuilder(),
    TargetPlatform.iOS:     FadeSlidePageTransitionsBuilder(),
    TargetPlatform.linux:   FadeSlidePageTransitionsBuilder(),
    TargetPlatform.windows: FadeSlidePageTransitionsBuilder(),
    TargetPlatform.macOS:   FadeSlidePageTransitionsBuilder(),
    TargetPlatform.fuchsia: FadeSlidePageTransitionsBuilder(),
  }),
),
```

---

## 2. Typography (Manrope via `google_fonts`)

Apply `GoogleFonts.manropeTextTheme(...)` once in the global theme. Within
pages, lean on these exact sizes/weights:

| Role                        | Size | Weight | Letter spacing |
|-----------------------------|------|--------|----------------|
| Logo / brand text           | 22   | w800   | -0.6           |
| Page title (movie/TV name)  | 26   | bold   | —              |
| Section header              | 19   | w700   | -0.5           |
| Section subtitle            | 12.5 | w400   | -0.1           |
| Search input (text + hint)  | 14.5 | w500 / w400 | -0.1      |
| Card title (rail poster)    | 13   | w600   | -0.1           |
| Card title (grid poster)    | 12   | w500   | -0.1           |
| Meta row (year/runtime/⭐)  | 14   | w400   | —              |
| Overview / description      | 14   | w400   | (line-height 1.5) |
| Tagline                     | 14   | w400 italic | —         |
| Button text (primary CTA)   | 16   | bold   | —              |
| Nav pill label              | 13.5 | w600   | -0.2           |
| Account section label (caps)| 11.5 | w600   | 1.4 (uppercase)|
| Stats value / label         | 13   | w700 / w500 | -0.1      |
| Cast name / character       | 11 / 10 | w400 | —             |
| Tag / chip                  | 12   | w400   | —              |

Defaults for body text: `color: Colors.white`, `height: 1.0` unless
otherwise noted. For long-form (overview), `height: 1.5`.

---

## 3. Spacing & layout primitives

Standard page horizontal padding is **20 px**. Card-interior padding is
**12 px** outside, **10 px** inside. Inter-section gap is **14 px** above,
**4 px** below section title. Bottom list padding ends with **120 px** to
clear the floating nav. (All values get the `.s(context)` responsive
multiplier from §11 of the feature-port prompt — `width: 220.s(context)`
not `width: 220`.)

Card / image dimensions:

| Component                | Width  | Height | Aspect / radius   |
|--------------------------|--------|--------|-------------------|
| Rail poster              | 118    | 176    | radius 14         |
| Grid poster card         | dynamic| —      | aspect 0.58, radius 14 |
| Hero backdrop            | full   | 280    | —                 |
| Episode still            | 130    | 76     | aspect ≈1.71, radius 12 |
| Profile avatar (circle)  | 96     | 96     | circle            |
| History rail poster      | 142    | 168    | radius 12         |
| History row poster (list)| 54     | 80     | radius 10         |
| Cast circle avatar       | r=36   | —      | circle            |

Grid columns (helper in `lib/services/responsive.dart`):

```dart
int posterGridColumns(double w) =>
    w >= 1500 ? 7 :
    w >= 1200 ? 6 :
    w >= 950  ? 5 :
    w >= 700  ? 4 : 3;
```

Cross-axis spacing 12, main-axis spacing 18, child aspect ratio 0.58.

---

## 4. Shape, shadow, borders

| Surface                 | Border radius | Shadow |
|-------------------------|---------------|--------|
| Poster card             | 14            | `BoxShadow(color: black α 0.4, blur 12, offset (0, 6))` |
| Episode tile            | 12            | none / subtle |
| Input field             | 14            | none |
| Search bar              | 13            | none |
| Genre / chip            | 20 (pill)     | none |
| Primary play button     | 6             | none |
| Floating nav container  | 100 (pill)    | `BoxShadow(color: black α 0.45, blur 22, offset (0, 8))` |
| Toast                   | 14            | `BoxShadow(color: black α 0.4, blur 18, offset (0, 6))` |
| Avatar circle           | circle        | `BoxShadow(color: accentRed α 0.28, blur 22, offset (0, 8))` |
| Modal sheet (top only)  | 24            | (drawn by sheet) |

Border colors (1 px hairlines):

- Inactive surfaces: `Colors.white.withValues(alpha: 0.06)`
- Active surfaces:   `Colors.white.withValues(alpha: 0.16)`
- Focus / accent:    `AppColors.accentGold.withValues(alpha: 0.55)`, 1.2 px

---

## 5. Buttons

**Primary CTA (Play / Resume)** — white pill on dark:
- Background `Colors.white`, foreground `Colors.black`
- Radius 6, height 52, padding vertical 12
- Icon `play_arrow` / `play_circle_outline_rounded`, size 28
- Label size 16, weight bold

**Secondary CTA (Login submit, etc.)** — red:
- Background `AppColors.accentRed`, foreground `Colors.white`
- Radius 12, height 50
- Label size 15, w600

**Floating-nav pill** — see §8.

All buttons should use the **SqueezeButton** wrapper from §7 so the
press animation is consistent.

---

## 6. Inputs

Text field shell (login, search):

- Background: `Colors.white α 0.03` (idle) → `α 0.06` (focused/active)
- Border 1 px: `Colors.white α 0.06` (idle) → `α 0.16` (active with text)
- Focus border 1.2 px: `AppColors.accentGold α 0.55`
- Border radius: 14 (login fields), 13 (search bar)
- Content padding vertical 12
- Text size 14.5–15, w500
- Hint color `Colors.white38`
- Cursor color: `AppColors.accentGold` for search, `AppColors.accentRed` for login
- Animate state transitions with `AnimatedContainer` 220 ms,
  `Curves.easeOutCubic`

---

## 7. Animations & motion

### Page transitions

`lib/services/page_transitions.dart` defines `FadeSlidePageTransitionsBuilder`:

```dart
class FadeSlidePageTransitionsBuilder extends PageTransitionsBuilder {
  const FadeSlidePageTransitionsBuilder();
  @override
  Widget buildTransitions<T>(route, ctx, animation, secondary, child) {
    final fade = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
    final slide = Tween<Offset>(
      begin: const Offset(0, 0.035),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));
    final dim = Tween<double>(begin: 1.0, end: 0.6)
        .animate(CurvedAnimation(parent: secondary, curve: Curves.easeInCubic));
    return FadeTransition(opacity: fade,
      child: SlideTransition(position: slide,
        child: FadeTransition(opacity: dim, child: child)));
  }
}
```

Hook it up in the global `ThemeData.pageTransitionsTheme` (see §1).

### `FadeInUp` helper

For reveal animations on grid items, detail body sections, lazy lists:

```dart
class FadeInUp extends StatefulWidget {
  final Widget child;
  final Duration duration;
  final double offset;       // px
  final Duration delay;
  const FadeInUp({super.key, required this.child,
    this.duration = const Duration(milliseconds: 320),
    this.offset = 16,
    this.delay = Duration.zero,
  });
  // ...AnimationController + Tween<Offset>(0, offset/100) and 0→1 opacity, easeOutCubic
}
```

Used wherever new content fades in.

### SqueezeButton (press feedback)

`lib/shared/squeeze_button.dart`. Wraps any tappable. Scale animation via
`Transform.scale` + `AnimatedBuilder`:

- Tap-down: 10 ms to scale 0.95, `Curves.easeInOut`
- Tap-up:   220 ms easing back to 1.0, `Curves.easeOutBack`
- Optional long-press: 160 ms to a deeper scale (e.g. 0.92), 220 ms release

Apply on **every** card and button. On TV, the SqueezeButton ALSO listens
for `LogicalKeyboardKey.select`/`enter` so the same press animation plays
on D-pad OK.

### Focus animations (TV-critical, replaces hover)

Add an `AnimatedScale` + glow on every focusable poster card / button:

- Unfocused: `scale: 1.0`, border `Colors.white α 0.06`, no glow
- Focused:   `scale: 1.08`, border 2 px `AppColors.accentRed`, plus a
  soft outer glow `BoxShadow(color: accentRed α 0.45, blur 24, spread 1)`
- Animation: 180 ms, `Curves.easeOutCubic`

Use `Focus`/`FocusableActionDetector` + an `Listener` on `onFocusChange`
to drive a local `_focused` bool, then feed it into an `AnimatedContainer`.

### Loading / progress

- `CircularProgressIndicator` always uses `color: AppColors.accentRed`
- `LinearProgressIndicator`:
  - `backgroundColor: Colors.white12` (or `white α 0.25`)
  - `valueColor: AlwaysStoppedAnimation(AppColors.accentRed)`
  - `minHeight: 3`, optional `borderRadius: 2`

### Other implicit animations to use

- `AnimatedContainer` for search bar state (220 ms easeOutCubic)
- `AnimatedSize` for nav pill expand/collapse (240 ms easeOutCubic)
- `AnimatedSwitcher` (180 ms fade) for icon swaps like bookmark
  filled/outline

Total animation budget: keep the longest user-driven transition under
**380 ms**. Default curve is **`Curves.easeOutCubic`**.

---

## 8. Navigation chrome

### Mobile sibling has a floating bottom pill — for TV, replace with a side rail

The pill aesthetic (rounded, dim, white-active) is the right one. Just
re-orient for TV:

```
+----------+
| ⌂  Home  |  ← focused: white bg, black text
|          |
| ⊕  Lib   |
|          |
| ◌  Pro   |
+----------+
```

Container:
- Background `AppColors.surfaceAlt α 0.92`
- Border radius 100 (capsule shape vertical)
- Border 1 px `Colors.white α 0.06`
- Shadow `BoxShadow(black α 0.45, blur 22, offset (0, 8))`
- Inner padding 6 px between pills

Each pill (`_NavPill`):
- Focused: bg `Colors.white`, label `Colors.black`, padding 18/10
- Unfocused: bg transparent, label `Colors.white60`, padding 14/10
- Animation: `AnimatedContainer` 240 ms `Curves.easeOutCubic`
- Icon size 20, label size 13.5 w600 letter-spacing -0.2, gap 8 px

Position: left edge, vertically centred, 14 px from safe area edge.

### App bars on detail pages

No real AppBar — stack a back button (top-left) and bookmark button
(top-right) over the backdrop, inside SafeArea + 8 px padding. Icons
`Colors.white`. Both must be focusable.

### Library / settings AppBar

If used:
- Background `AppColors.background`, elevation 0
- TabBar: label `Colors.white`, unselected `Colors.white54`, indicator
  `AppColors.accentRed` 2.5 px, label w600

---

## 9. Imagery

TMDB base: `https://image.tmdb.org/t/p/{size}{path}`.

| Component                  | Size  |
|----------------------------|-------|
| Poster (grid / rail)       | w300  |
| Poster (history row, small)| w185  |
| Backdrop (hero)            | w780  |
| Cast profile               | w185  |
| Avatar                     | w300  |
| Episode still              | w300  |

**Loading placeholder** (in `Image.network`'s `loadingBuilder`):
small centred `CircularProgressIndicator` (22×22, stroke 2,
`color: Colors.white30`).

**Error placeholder** (in `errorBuilder`):
container `AppColors.surface` + centred muted icon —
`Icons.movie_rounded` for posters (size 32, `white24`),
`Icons.tv_rounded` for episodes (`Colors.black26` bg + `white24` icon),
`Icons.person` for cast (size 28, `white54`).

Backdrop gets a top-to-bottom gradient overlay to fade into background:

```dart
LinearGradient(
  begin: Alignment.topCenter,
  end:   Alignment.bottomCenter,
  colors: [Colors.transparent, AppColors.background],
  stops:  [0.4, 1.0],
)
```

Profile hero gets a radial red glow:

```dart
RadialGradient(
  center: Alignment(0, -0.9),
  radius: 0.85,
  colors: [Color(0x33E50914), Color(0x00000000)],
)
```

---

## 10. Iconography

Always prefer the **`_rounded`** variants. Standard sizes 18–28 by
context. Key mappings:

| Icon                            | Color                                       |
|---------------------------------|---------------------------------------------|
| `search_rounded`                | `white38` idle → `white70` focused          |
| `close_rounded`                 | `white70`                                   |
| `play_arrow` / `play_circle_outline_rounded` | `Colors.black` on white CTA   |
| `play_arrow_rounded` (overlay)  | `Colors.white`                              |
| `bookmark_rounded` (saved)      | `AppColors.accentGold`                      |
| `bookmark_outline_rounded`      | `Colors.white`                              |
| `star` (rating)                 | `AppColors.accentGold`, size 16             |
| `error_outline`                 | `AppColors.accentRed`                       |
| `info_outline_rounded` (toast)  | `AppColors.accentGold`                      |
| Nav icons (`home_rounded`, `person_rounded`) | focused `Colors.black`, idle `Colors.white60` |
| Placeholders (`movie_rounded`, `tv_rounded`) | `Colors.white24`              |

---

## 11. Toast / snackbar

Custom toast (`lib/services/toast.dart`):
- Container bg `AppColors.surfaceAlt`, border 14
- Border 1 px `Colors.white α 0.06`
- Shadow `black α 0.4, blur 18, offset (0,6)`
- Info badge: bg `accentGold α 0.15`, border `accentGold α 0.35`,
  icon `info_outline_rounded` gold, size 16
- Body text: 12.5 w500 letter-spacing -0.1, line-height 1.35,
  `Colors.white`

---

## 12. Splash

`pubspec.yaml`:

```yaml
flutter_native_splash:
  color: "#292830"           # AppColors.splashSurface
  image: assets/favicon.jpg
  android_12:
    image: assets/favicon.jpg
    color: "#292830"
  android: true
  ios: true
  fullscreen: false
```

The splash colour is intentionally **one shade lighter** than the
in-app background (`#18181A`) so the boot-to-app handoff feels like a
gentle dim, not a flash.

---

## 13. TV-specific deltas from the mobile design

These are NOT in the mobile sibling — add them only on TV:

1. **Focus ring everywhere.** Every interactive widget (cards, buttons,
   tiles, tabs, input fields) draws an `AppColors.accentRed` 2 px outline
   + soft glow when focused. Implement in a shared `FocusableCard`
   wrapper so it's impossible to forget.
2. **Scale-up on focus** (1.08×) — replaces the mobile "shrink on press"
   as the dominant motion. Press (OK) still triggers the squeeze.
3. **Side nav rail** instead of bottom pill (§8 above).
4. **No touch-only affordances.** Drop swipe-to-dismiss, drag handles,
   long-press menus — replace with focusable trash / overflow icons.
5. **Larger hit targets.** All buttons min 48 dp, all card titles must
   stay readable from 3 m (use the `.s(context)` extension from the
   feature-port prompt — TV titles end up ~1.5× mobile size).
6. **No bottom-sheet modals.** Use full-screen dialogs (`showGeneralDialog`
   with `FadeSlidePageTransitionsBuilder`) so they don't fight focus
   traversal.

---

## 14. Implementation order

1. Add `google_fonts: ^6.2.1` to `pubspec.yaml`.
2. Create `lib/services/theme.dart` with `AppColors` + the full
   `ThemeData` (§1, §2).
3. Create `lib/services/page_transitions.dart` with
   `FadeSlidePageTransitionsBuilder` + `FadeInUp` (§7).
4. Create `lib/shared/squeeze_button.dart` (§7) and
   `lib/shared/focusable_card.dart` (§13 #1 + #2) — the two shared
   wrappers every interactive widget will use.
5. Create `lib/services/responsive.dart` with `posterGridColumns()`
   helper + the `.s(context)` extension (also in feature-port prompt §11).
6. Replace the existing nav widget with the vertical pill rail.
7. Sweep every page in `lib/services/pages/` and update colours, text
   sizes, paddings, radii to match the tables above. Wrap every
   interactive element in `FocusableCard` / `SqueezeButton`.
8. Update `Image.network` placeholders globally (§9).
9. Update `pubspec.yaml`'s `flutter_native_splash` block (§12) and run
   `dart run flutter_native_splash:create`.
10. Run on Android TV emulator at 1080p and a real 4K device — side-by-
    side with the mobile app — and adjust any drift.

---

## 15. Acceptance criteria

- All hex literals in page code are gone; everything routes through
  `AppColors`.
- Manrope is the only font family rendered.
- Every page transition is the fade-slide (no Material default slide).
- Every interactive element scales 1.08× and glows red when focused, and
  squeezes to 0.95 on OK / tap.
- Posters use radius 14 + the standard black-α-0.4 shadow.
- Loading spinners are red. Progress bars are red on a `white12` track.
- The nav rail (or pill) uses the white-active / transparent-idle pattern.
- Splash colour `#292830`, app background `#18181A` — the handoff is a
  gentle dim, not a colour pop.
- The look passes a side-by-side eyeball check against the mobile
  sibling on these screens: home, search, movie detail, TV detail,
  library, profile, login.
