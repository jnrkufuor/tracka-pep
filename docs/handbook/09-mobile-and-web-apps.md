# 09 · Mobile and web apps

## The idea

The **app** is the part people touch: screens, buttons, the camera roll.
It's the **client**. It shows things and collects input, and talks to the
**server** (the API) for anything that must be shared, safe or heavy.
Rule of thumb: **the client is untrusted.** Anyone can modify an app or
fake its requests, so every important check (who you are, what you're
allowed to see) happens on the server.

## The common approaches

### How to build for phones

| Approach | What it is | Examples | Trade-off |
|---|---|---|---|
| **Native** | A separate app per platform in its own language | Swift (iOS), Kotlin (Android) | Best performance and platform feel; two codebases |
| **Cross-platform** | One codebase, compiled for iOS, Android (and web) | **Flutter** (Dart), React Native (JavaScript) | One team, one codebase; occasional platform quirks |
| **Web app / PWA** | A website that behaves like an app; can be "installed" | React, Vue, Flutter web | No app store; weaker camera, storage and notification access |

**Flutter** draws every pixel itself (it doesn't use the platform's
buttons), so the app looks identical everywhere, and the same Dart code
builds for Android, iOS and the web. React Native uses the platform's own
components instead.

### How an app is put together
- **Widgets / components**: small reusable UI pieces (a score card, a
  button) combined into screens.
- **State**: the data the UI shows right now (logged-in user, videos,
  upload progress). **State management** is how changes in data redraw
  the right parts of the screen. Flutter options: `setState` (one
  widget), **Provider** / ChangeNotifier (simple, shared), Riverpod, Bloc
  (bigger apps).
- **Navigation**: moving between screens (tabs, pushing a detail screen).
- **Networking**: calling the API, handling slow connections, retries and
  errors.
- **Local storage**: saving tokens and settings on the phone. Secrets go
  in **secure storage** (iOS Keychain, Android Keystore), never plain
  files.

### Phone-specific realities
- **Bad networks**: in much of Ghana, mobile data is slow and costly.
  Show progress, allow retries, keep uploads small, never lose a user's
  work because a request failed.
- **Permissions**: camera, photos, notifications, each needs the user's
  OK and an explanation.
- **App stores**: Google Play and Apple's App Store review apps. You need
  developer accounts (Google one-off fee; Apple yearly), signing keys,
  privacy labels, and age ratings. iOS apps can only be built on a Mac.
- **Versions in the wild**: people don't update. The API must keep
  working with older app versions (that's why it's `/v1`).

### Design systems
A **design system** is the shared set of colours, fonts, spacing and
components, so every screen looks like the same product. Define it once
(a **theme**) and use it everywhere instead of picking colours per screen.

#### Design tokens
A **design token** is one design decision with a name: `Tk.pep` instead
of `Color(0xFFB98CFF)`, `Motion.sheet` instead of `320`. Screens only use
names, so changing a token changes every screen at once, and nobody
invents a 51st shade of grey. Good tokens are named by **job**, not by
look: "the colour for warnings" survives a rebrand; "dark yellow" doesn't.

#### Theming at runtime
Some tokens can change while the app runs: a player picks a main colour,
and every button, chip and progress bar follows. In Flutter the theme is
data passed down the widget tree; replace it at the top and everything
below rebuilds. A **ThemeExtension** lets you add your own typed values
(like the main colour) to the same theme.

#### Motion and reduce motion
Animation should *explain* a change (where a sheet came from, that a tap
landed), never be the only way information is shown. Phones have a
"reduce motion" / "remove animations" setting for people who get dizzy or
distracted; apps should honour it by making changes happen instantly.

#### Component libraries
Shared widgets (cards, chips, warnings, empty and error screens) built
once and reused. Fix a component and every screen using it is fixed.

## How Tracka does it

**Flutter**, one codebase in `app/`, built for **Android, iOS and the
web**. Players get the phone app; the web build (Cloudflare Pages) is for
anyone without space for another app, and for testing.

| Part | Where | Notes |
|---|---|---|
| Start-up and routing | `lib/main.dart` | Stage: starting → signed out → onboarding → ready |
| Talking to the API | `lib/api/api_client.dart` | Bearer token; on a 401 it refreshes the token once and retries; uploads stream the file and report progress |
| Data types | `lib/api/models.dart` | Mirrors the API's JSON (camelCase) |
| App state | `lib/state/app_state.dart` | One `ChangeNotifier` (Provider): user, profile, videos, coach summary; polls every 6 s while a clip is processing |
| Screens | `lib/screens/` | Splash, welcome/auth, onboarding v2 (Meet Pep, 5 steps with a casual and a looking-around path, a pitch to tap your positions, All set), the tabs (Home, Pitchside, + to add a clip, Pep, Me), Upload, Video, Profile & settings. Being rebuilt in the new design, area by area |
| Design tokens | `lib/theme/tokens.dart` | Colours by job (`Tk`): your main colour, Pep purple, warning gold, calm stone. `MainColour` (5 choices), rating `Band`, `Confidence`, `Trend` |
| Motion | `lib/theme/motion.dart` | Durations and easing; `Motion.reduced()` is true when the phone or Tracka's own setting asks for less motion |
| Theme | `lib/theme/theme.dart` | Builds Material's theme from the tokens and the player's main colour; Bricolage Grotesque (headings) + Figtree (text) |
| Components | `lib/widgets/ds.dart` | Chips, band pill, confidence dots, AI and safety notes, edit sheet, bottom toast, failsafe `StateView`, offline banner, loading `Skeleton` |
| Icons | `lib/widgets/line_icons.g.dart` (new design), `loopy_icons.g.dart` (older screens) | **Generated** by `scripts/build_brand.py` from the same drawings as the web brand. Don't hand-edit; add icons in the script and run it. Drawn with `TIcon('name')` |
| Tokens | `flutter_secure_storage` | Keychain / Keystore on phones |

Design decisions:
- **Player-only for now**: no scout features yet. Pitchside (other
  players' clips, challenges, near you) has its final layout but shows
  "coming soon" until its API routes exist. The API's structure (users with a `role`, an
  `/opportunities` route) leaves room for a scout app later.
- **Tap yourself**: on upload, the player taps their own body in a
  frame, so Pep follows the right person in a crowded match.
- **Minors**: under-18s must add a guardian and confirm consent before
  uploading (enforced by the server, not just the app).
- **Generated platform folders**: `android/`, `ios/`, `web/` are created
  by `tool/setup_platforms.sh` (then patched with permissions and icons),
  so the repo holds only the code we wrote.
- **Screenshot mode**: CI builds the web app with demo login flags and
  photographs each screen (`screenshots.yml`); real builds never contain
  them.

### Working offline: the upload queue and saved screens

Phones in Ghana often have slow, costly or patchy data, so the app is built
**offline-first** in two places:

- **The upload queue** (`lib/state/upload_queue.dart`). A clip is saved first
  and sent later: on Wi-Fi only if the player asked, when the connection comes
  back, after the guardian says yes. A dropped upload is retried, and each clip
  carries a `clientId` so the server makes it once however many times it
  arrives. That's an **idempotency key** (`upload_keys` in `pep/players/store.py`).
- **Saved screens** (`lib/api/cache.dart`). The last good answer to each main
  GET is kept. If Tracka can't be reached, the app shows the saved copy with
  "You're offline. Showing what's saved." That's a **cache** with a
  **fallback**: possibly old, clearly labelled, never used when the real thing
  answers.

### Pitchside: a small social network, built safe (pep/players/pitchside.py)

A feed looks simple (a list of clips, newest first) but every social app is
mostly **rules about who sees what**. Pitchside's are written as code and
checked by tests: posting and being findable need the guardian's yes for
under-18s, others see a shirt name (never the full name or town), there are
no messages at all, blocking hides both players from each other, and three
reports hide a clip until it's reviewed. Pep's review is never sent with
someone else's clip. Pitches are **crowd-sourced with a check**: one player
adds it, two others confirm it.

## Words to know
client · server · native · cross-platform · Flutter · Dart · React
Native · PWA · widget · state · state management · Provider · navigation ·
secure storage · permissions · app store review · signing · design system ·
theme · design token · ThemeExtension · component library · reduce motion ·
contrast ratio

## Workbook 09

**Try it**
1. Install Flutter, then in `app/`: `./tool/setup_platforms.sh` and
   `flutter run -d chrome --dart-define=PEP_API_URL=http://localhost:8000`
   with `pep serve` running. Sign up and finish onboarding.
2. Run `python scripts/seed_demo.py` and log in as
   `demo@tracka.app` / `tracka-demo-123` to see a full dashboard.
3. Change `TColors.neon` in `lib/theme/theme.dart` and hot-reload (`r`).
   Then change it back. Colours belong to the brand.
4. Turn off Wi-Fi mid-upload. What does the app do? What *should* it do?
   (Compare with the "Uploads" failsafe board on the design canvas.)
5. Plug in an Android phone and `flutter run`. Upload a real clip.
6. Turn on "Remove animations" (Android: Settings › Accessibility) and
   open the app. The splash and chips should change instantly. Find the
   line in `lib/theme/motion.dart` that makes that happen.
7. Sign up twice: once choosing "Get into an academy", once "Just looking
   around". Which steps did you skip the second time, and which line in
   `onboarding_screen.dart` (`flow`) decides it?
8. In `test/upload_queue_test.dart`, add a test: two clips on mobile data
   with Wi-Fi only on, then switch the fake network to Wi-Fi. Do both go?
   Which line in `UploadQueue` listens for the change?
9. Post a clip from one account and open the Feed from another. Then
   report it from three more accounts. In `tests/test_pitchside.py`, which
   assert proves the feed never carries Pep's notes?
10. `PepScreen.weekLine` turns your week into one sentence ("You have a
   match tomorrow. Keep today light."). Add the case of a match in 3 days to
   `test/pep_tab_test.dart`, then make it pass.
11. Pep's tour finds what to point at with GlobalKeys (`lib/widgets/tour.dart`).
   Hide "Tests and PBs" in Customise home, then run the tour from Settings ›
   Help. What does step 2 do when its card isn't there, and which line decides?
12. In `test/design_system_test.dart`, add `Color(0xFF7A2BFF)` (a purple)
   to the contrast test's list. Does it pass? Even if it did, why would
   Tracka still not offer it as a main colour?

**Questions**

**1. Why check "is this my video?" on the server and not just in the
app?**

*Answer:* The client is untrusted: anyone can call the API directly with
any video ID. Only the server can enforce it, which is why every video
query filters by the logged-in user's ID.

**2. Why Flutter instead of two native apps?**

*Answer:* One small team, one codebase for Android, iOS and web, with the
same look everywhere. The cost is occasional platform-specific work.

**3. Why must the API keep `/v1` working after `/v2` ships?**

*Answer:* Old app versions stay installed on phones for months; if the
API changes under them, they break.

**4. Where should the refresh token be stored on the phone?**

*Answer:* In secure storage (Keychain / Keystore), which is encrypted and
protected by the operating system, not in ordinary preferences or files.

**5. Why are colours in `tokens.dart` named by job (`Tk.gold` = "watch
out") instead of by shade?**

*Answer:* Because a screen asks "what does this mean?", not "what does it
look like?". If warnings ever change colour, one token changes and every
warning follows; nothing that merely *happened* to be yellow changes by
accident.

**6. The main colour test checks a 4.5:1 contrast ratio. What is that
number, and why black text?**

*Answer:* It's the WCAG "AA" minimum for normal text: the lighter colour's
brightness (plus a little) divided by the darker one's. Every main colour
is a button background with black text on it, so black must stay easy to
read on all five.

**7. Why does `Motion.of()` return `Duration.zero` instead of skipping
the animation code?**

*Answer:* The change still has to happen (the chip still becomes
selected, the sheet still opens), just instantly. Returning zero keeps one
code path, so reduce motion can't accidentally break a feature.
