# Peridot for iOS

[Peridot AI](https://peridot.ai) on iPhone and iPad: a native SwiftUI app that talks to the same API as the website, the desktop app and the [CLI](https://github.com/Peridot-AI/peridot-cli). The Android app is [peridot-android](https://github.com/Peridot-AI/peridot-android).

- **Chat** with streamed answers, rendered as Markdown (code blocks with a copy button, tables, lists, links). Stop an answer at any time; a stopped answer is kept.
- **Models and effort**: tap the model name at the top. Models your plan doesn't include are shown locked.
- **History** (signed in): every exchange is saved to your account, so chats from the website or the CLI are in the chat list, and chats from the phone show up there. Swipe or long-press a chat to rename or delete it.
- **Account**: plan, messages used today and this month's usage.
- Without signing in you can chat with the free limits; history needs an account.
- In English, Spanish, Chinese, Japanese, French, German and Italian, like the website.

Sign-in is by email and password. New accounts are created on [peridot.ai](https://peridot.ai/signup); accounts created with Google can't sign in to the app yet.

## Privacy

The app only talks to the Peridot API (`https://peridot.ai/api`). The sign-in token is kept in the Keychain, on this device only (it is not included in backups).

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

## Layout

```
Peridot/
  PeridotApp.swift, Config.swift
  API/        PeridotAPI (REST + streaming), SSEParser, Keychain, API models
  Markdown/   Markdown parser (same rules as the Android app)
  Store/      ChatStore: account, chat, streaming, history
  Views/      ChatView, HistoryView, ModelPickerView, AccountView, SignInView, MarkdownView, Theme
  Localizable.xcstrings
PeridotTests/  unit tests
```

The project uses folder-synchronized groups: files added under `Peridot/` or `PeridotTests/` are part of the target without editing the project.

CI (GitHub Actions, macOS) runs the unit tests on a simulator and builds the app for devices on every push.
