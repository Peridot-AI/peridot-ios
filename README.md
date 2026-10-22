# Peridot for iOS

[Peridot AI](https://tryperidot.io) on iPhone and iPad: a native SwiftUI app that talks to the same API as the website, the desktop app and the [CLI](https://github.com/Peridot-AI/peridot-cli). The Android app is [peridot-android](https://github.com/Peridot-AI/peridot-android).

- **Chat** with streamed answers, rendered as Markdown (code blocks with a copy button, tables, lists, links). Stop an answer at any time; a stopped answer is kept.
- **Models and effort**: tap the model name at the top. Models your plan doesn't include are shown locked.
- **History** (signed in): every exchange is saved to your account, so chats from the website or the CLI are in the chat list, and chats from the phone show up there. Swipe or long-press a chat to rename or delete it.
- **Account**: plan, messages used today and this month's usage.
- Without signing in you can chat with the free limits; history needs an account.
- In English, Spanish, Chinese, Japanese, French, German and Italian, like the website.

Sign in with Google (Google's sign-in page in a system web authentication sheet) or with email and password. New email accounts are created on [tryperidot.io](https://tryperidot.io/signup).

## Privacy

The app only talks to the Peridot API (`https://api.tryperidot.io/api`). The sign-in token is kept in the Keychain, on this device only (it is not included in backups).

## Build

Requires Xcode 16 or later; the app runs on iOS 17 and later. There are no third-party dependencies.

1. Open `Peridot.xcodeproj`.
2. Pick your team under *Signing & Capabilities* (only needed to run on a device).
3. Run the **Peridot** scheme. `⌘U` runs the unit tests (SSE parser, Markdown).

From the command line:

```bash
xcodebuild test -project Peridot.xcodeproj -scheme Peridot -destination 'platform=iOS Simulator,name=iPhone 16'
```

### Another server

Edit the scheme (*Run → Arguments → Environment Variables*) and enable `PERIDOT_API_URL` / `PERIDOT_WEB_URL`; they point at a local `bun run dev` server (`http://localhost:3001/api`) by default. Plain HTTP is allowed only for local addresses.

### Google sign-in (one-time setup)

The app uses no Google SDK: it opens Google's sign-in page in an `ASWebAuthenticationSession` for the app's own **iOS** OAuth client, redeems the code with PKCE (iOS clients have no secret) and sends the ID token to `POST /api/auth/google`. It reads the client ID from `GET /api/auth/config`, so nothing is built into the app. Once per deployment:

1. In [Google Cloud Console → APIs & Services → Credentials](https://console.cloud.google.com/apis/credentials), in the project of the server's `GOOGLE_CLIENT_ID`: **Create credentials → OAuth client ID → iOS**, bundle ID `ai.peridot.app` (App Store ID and Team ID are optional).
2. Put its client ID (`….apps.googleusercontent.com`) in the server's `.env` as `GOOGLE_IOS_CLIENT_ID` and restart the server. `/api/auth/config` then hands it to the app, and the server accepts ID tokens issued for it.
3. The OAuth consent screen must be published (or your account listed as a test user).

The redirect goes to the reversed client ID (`com.googleusercontent.apps.…:/oauth2redirect`), which the authentication session catches by itself: no URL type in `Info.plist` is needed. Without `GOOGLE_IOS_CLIENT_ID` the app says Google sign-in isn't available; email sign-in keeps working.

## Layout

```
Peridot/
  PeridotApp.swift, Config.swift
  API/        PeridotAPI (REST + streaming), GoogleSignIn, SSEParser, Keychain, API models
  Markdown/   Markdown parser (same rules as the Android app)
  Store/      ChatStore: account, chat, streaming, history
  Views/      ChatView, HistoryView, ModelPickerView, AccountView, SignInView, MarkdownView, Theme
  Localizable.xcstrings
PeridotTests/  unit tests
```

The project uses folder-synchronized groups: files added under `Peridot/` or `PeridotTests/` are part of the target without editing the project.

CI (GitHub Actions, macOS) runs the unit tests on a simulator and builds the app for devices on every push.
