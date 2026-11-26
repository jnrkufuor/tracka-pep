# Setting up push notifications (Firebase)

Push is built and tested; it switches on when these settings exist. Until
then the server only logs pushes and the app skips Firebase, and the bell on
Home works either way. About 15 minutes.

## 1. Create the Firebase project
1. Go to <https://console.firebase.google.com> → **Add project** → name it
   `Tracka` (Google Analytics: off is fine).
2. **Add app → Android**. Package name: **`app.tracka.tracka`** (it must match;
   it comes from `app/tool/setup_platforms.sh`). Nickname: `Tracka Android`.
   You don't need to add `google-services.json` to the repo: the app passes the
   same values at build time. Skip the remaining steps of the wizard.
3. (iOS later) **Add app → Apple**, bundle ID `app.tracka.tracka`, then upload an
   APNs key under Project settings › Cloud Messaging. Needs an Apple developer account.

## 2. The values for the app (not secret, but keep them out of git)
Project settings › General › Your apps › Tracka Android shows them:

| GitHub variable       | Where in Firebase                         |
|-----------------------|-------------------------------------------|
| `FCM_API_KEY`         | Web API key (also `current_key` in google-services.json) |
| `FCM_APP_ID_ANDROID`  | App ID, like `1:1234567890:android:abc…`  |
| `FCM_SENDER_ID`       | Project number (Cloud Messaging tab)      |
| `FCM_PROJECT_ID`      | Project ID, like `tracka-1a2b3`           |

Add each one in GitHub: repository **Settings › Secrets and variables ›
Actions › Variables**. The Android build in CI passes them to the app
(`.github/workflows/app.yml`). For a local build:

```bash
flutter build apk --dart-define=FCM_API_KEY=… --dart-define=FCM_APP_ID_ANDROID=… \
  --dart-define=FCM_SENDER_ID=… --dart-define=FCM_PROJECT_ID=…
```

## 3. The server key (SECRET)
Project settings › **Service accounts** › **Generate new private key**. That
downloads a JSON file. Never commit it. On the server, set:

```
PEP_FCM_SERVICE_ACCOUNT=<the whole JSON file, as one line>
```

(`PEP_FCM_PROJECT_ID` is optional; it's read from the JSON.) Restart the API.

## 4. Check it works
1. Install the APK from the latest CI run, log in, allow notifications.
2. Upload a clip. When Pep finishes, the phone should buzz with
   "Pep's read on … is ready". Tapping it opens the clip.
3. Nothing arrives? Look for `push.failed` or `push.error` in the API logs.
   Quiet hours (9 pm to 7 am Ghana time, always on for under-18s) hold pushes
   back on purpose; the bell still gets them.
