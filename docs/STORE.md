# Getting Tracka into the stores

Everything Google Play and the App Store will ask for, with Tracka's answers.
Rules checked in November 2026. Stores change their forms often, so check
each item against the console when you fill it in.

## Decisions only you can make

1. **Youngest age allowed.** Today anyone can sign up, and onboarding has a
   U13 group. Choose one:
   - **13 and over (simpler):** Play target audience 13–15, 16–17, 18+. Not
     in the Families programme. Apple rating 13+. Add a "you must be 13" check
     at sign-up.
   - **Under 13 too:** Play's Families policy applies to the whole app (only
     approved SDKs, stricter review, a teacher-approved badge is possible).
     Firebase Messaging is allowed, but check every new package against
     Families rules first. Apple: don't pick the Kids category (it bans most
     outside services and needs a parental gate before any link).
2. **Who publishes it:** a company account (needs a D-U-N-S number) or a
   personal one. Google asks newer *personal* accounts to run a closed test
   with real testers for about two weeks before production. Check the
   current numbers in Play Console.
3. **Register with Ghana's Data Protection Commission** as a data controller
   (Data Protection Act 2012, section 27), before launch. It's renewed every
   two years. The privacy policy should name the registration.
4. **Support email:** `PEP_SUPPORT_EMAIL` (default support@tracka.app) is
   shown on the public pages and in both listings. It has to be an inbox
   someone reads.

## Links both stores ask for

| What | URL (on the API's public address) |
|---|---|
| Privacy policy | `/legal/privacy` (the full text still needs the lawyer's review) |
| Terms | `/legal/terms` |
| Delete your account without the app | `/delete-account` |
| Child safety standards (Play, social apps) | `/child-safety` |
| Support | `mailto:` the support email |

## Listing text (English, Ghana first)

**Name** (30 characters max on both): `Tracka: Football Coach`

**Short description** (Play, 80 max):
`Film your football. Pep, your AI coach, shows what's strong and what to train.`

**Subtitle** (Apple, 30 max): `Your AI football coach`

**Full description** (Play 4,000 max; Apple "Description"):

> Tracka helps young footballers in Ghana get better, one clip at a time.
>
> Film a match, a drill or a challenge on your phone. Pep, Tracka's AI coach,
> watches it and shows you what you did well and what to work on next, in
> plain words. Your speed, your first touch, your movement: measured from the
> video, never guessed.
>
> • Clips and drills: film yourself and get Pep's notes.
> • Your road: see where you're growing, area by area, at your own pace.
> • Training: a simple plan for your week, built around school and rest.
> • Pitchside: share your best clips with other players. No private
>   messages, and contact details can't be posted.
> • Your player card: share it with a coach on WhatsApp.
>
> Built for young players:
> • Under 18? A parent or guardian approves before anyone can see your clips.
> • Only your shirt name, position, age group and region are ever shown.
> • Report or block anything in one tap. Our team reviews safety reports first.
> • Delete your clips or your whole account at any time.
>
> Pep is an AI coach. It doesn't diagnose injuries: if something hurts, stop
> and tell an adult.

**Apple keywords** (100 max, commas, no spaces):
`football,soccer,coach,training,drills,skills,academy,scout,ghana,player,AI,highlights`

**Category:** Sports (both). **Price:** free. **Ads:** none. **In-app purchases:** none.

## Google Play: Data safety form

Collected = leaves the phone. "Shared" means given to another company for its
own use: we share nothing. Companies working for us (hosting, Firebase for
pushes, the AI model writing Pep's words) count as service providers, not sharing.

| Data type (Play's name) | Collected? | Why | Optional? |
|---|---|---|---|
| Name | Yes (display name; shown publicly only as a shirt name) | App functionality, account | No |
| Email address | Yes | Account | No |
| Phone number | Yes (the guardian's, for under-18s) | Guardian approval | Under 18 only |
| Other info: birth date, height, positions, region/town | Yes | Pep's scoring needs age and role | No |
| Health info | Yes (how you feel: fine, sore, in pain or injured, and where) | Safer training plans | Yes |
| Fitness info | Yes (speeds and skills measured from clips) | App functionality | No |
| Videos | Yes (clips you choose to upload) | App functionality | No |
| App interactions | Yes (posts, respects, follows, reports) | App functionality, safety | No |
| Crash logs, diagnostics | Yes (crashes, no personal details) | Analytics (fixing bugs) | No |
| Device or other IDs | Yes (push token) | Notifications | Yes |
| Location | **No** (no GPS; region is typed in) | | |

- Encrypted in transit: **Yes** (release builds are https only).
- You can request deletion: **Yes** (in the app, and `/delete-account`).
- Independent security review: No.

## Google Play: other App content forms

- **Target audience:** see decision 1.
- **Content rating (IARC questionnaire):** no violence, no fear, no sexual
  content, no gambling, no ads. **Users can interact / share content: Yes**
  (Pitchside clips and captions). No chat. Doesn't share location.
- **Child safety standards:** link `/child-safety` and the support email as
  the contact point.
- **Health apps declaration:** fitness and wellbeing guidance, not a medical
  device, no diagnosis.
- **News app / government app / financial features:** No.
- **AI-generated content:** Pep writes text with an AI model. Players can
  report a note (Help › Report a problem).

## App Store (Apple)

- **Age rating questionnaire:** user-generated content: yes; social
  features: yes; unrestricted web access: no; medical or wellness topics:
  "infrequent/mild" (readiness, injury advice to rest); in-app controls:
  yes (guardian approval). Then set the age from decision 1.
- **Guideline 1.2 (user-generated content)** needs four things, all in the
  app: filtering (contact details blocked, reported clips hidden), Report,
  Block, and a published contact (the support email).
- **Account deletion** (guideline 5.1.1): in the app, Settings › Your data.
- **Sign in with Apple:** not required, because we only use email sign-in
  (it's required if Google or Facebook sign-in is added).
- **App Privacy labels:** same data as the Play table. "Data linked to you":
  everything except crash logs. "Used to track you": none.
- **Review notes:** give Apple a demo login (an adult test account with a
  few analysed clips; `scripts/seed_demo.py`), and explain guardian approval
  so a reviewer can see Pitchside.
- **Push:** needs an APNs key uploaded to Firebase (`docs/PUSH_SETUP.md`).

## Technical checklist

- [ ] **Target API level 36 (Android 16):** required for new apps and updates
      since 31 August 2026. Check `targetSdkVersion` in the generated
      `android/app/build.gradle` (it follows Flutter's default).
- [ ] **Upload an App Bundle (.aab), not APKs:** `flutter build appbundle
      --release`. CI builds APKs today; add a signed `appbundle` step with
      the upload key in GitHub secrets, and turn on Play App Signing.
- [ ] **Permissions:** only INTERNET and POST_NOTIFICATIONS. No camera,
      microphone or media-library permissions: the system picker and camera
      need none (Play's Photo and Video Permissions policy only allows
      READ_MEDIA_VIDEO for gallery apps). `tool/setup_platforms.sh` does this.
- [ ] **https only in release builds** (plain http only in debug).
- [ ] **Version:** bump `version:` in `app/pubspec.yaml` for every upload
      (`1.0.0+1`, then `1.0.1+2`…; the number after `+` must always go up),
      and pass it as `--dart-define=APP_VERSION=…`.
- [ ] **Icons:** Play wants a 512 × 512 PNG:
      `convert app/tool/icon-ios-1024.png -resize 512x512 icon-512.png`.
      Apple uses the 1024 one. Play also needs a 1024 × 500 feature graphic.
- [ ] **Screenshots:** `.github/workflows/screenshots.yml` captures the demo
      player's screens. Play: 2–8 phone screenshots. Apple: the largest
      iPhone size the console asks for. Demo data only, no real players.
- [ ] **iOS build:** needs a Mac (or a macOS CI runner), an Apple Developer
      account and signing certificates.
- [ ] **Before submitting:** set `PEP_LAB_PASSWORD`, `PEP_SENTRY_DSN`,
      `PEP_SUPPORT_EMAIL`, and run the restore drill once (`docs/RUNBOOK.md`).
