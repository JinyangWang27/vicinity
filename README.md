# Vicinity

**Offline peer-to-peer chat for iPhone and iPad — no internet, no accounts, no tracking.**

Vicinity lets you chat with nearby people (family, roommates, friends) over Bluetooth and peer-to-peer Wi-Fi using Apple's MultipeerConnectivity framework. Messages never touch a server.

---

## How It Works

Vicinity uses iOS's built-in [MultipeerConnectivity](https://developer.apple.com/documentation/multipeerconnectivity) framework to discover and communicate with other devices running Vicinity on the same local network segment or over Bluetooth. No router or internet connection is required.

1. **Discovery** — The app advertises itself and browses for peers automatically on launch.
2. **Connection** — Tap a discovered peer to connect; both sides see a confirmation.
3. **Chat** — Send and receive text messages in real time using `.reliable` delivery.
4. **Persistence** — All messages are saved locally on your device using SwiftData.
5. **Scheduled Messages** — Compose a message that sends automatically the next time a specific friend comes within range, even if the app is in the background.

---

## How to Build

### Requirements

- Xcode 15 or later
- iOS 17.0+ deployment target
- A physical device is strongly recommended for testing Multipeer features (the simulator cannot test peer-to-peer networking between two instances)

### Steps

1. Clone this repository:
   ```
   git clone https://github.com/JinyangWang27/vicinity.git
   ```
2. Open `vicinity.xcodeproj` in Xcode.
3. Select your development team in **Signing & Capabilities**.
4. Build and run on a real device (`⌘R`).

No third-party dependencies. No package manager setup needed.

---

## Scheduled & Proximity Messages

Schedule a message for a specific friend and Vicinity will send it automatically the moment they come within Bluetooth range.

- **Schedule** — Open a chat, tap the **clock** icon in the top-right, then tap **+** to compose a scheduled message.
- **Auto-send (foreground)** — When the target peer connects and completes the handshake, the message is sent immediately with no user action required.
- **Auto-send (background)** — Vicinity uses Core Bluetooth to wake itself when the target peer's device is detected nearby. Once awake, MultipeerConnectivity re-establishes the connection and delivers the message automatically.
- **Notification** — A local notification confirms delivery: *"Scheduled message sent — To Alice: hey!"*
- **Manage** — The Scheduled Messages screen shows pending, sent, and cancelled messages. Swipe to cancel any pending message.

> **Note:** Background delivery requires Bluetooth permission ("Always" is not required — standard Bluetooth permission is sufficient) and that both devices are running iOS 17+.

---

## Privacy Guarantee

Vicinity is privacy-by-design:

- **No internet** — All communication happens directly between nearby devices over Bluetooth and peer-to-peer Wi-Fi.
- **No accounts** — There is no sign-in, registration, or user database.
- **No tracking** — The `PrivacyInfo.xcprivacy` manifest declares zero data collection. No analytics, no crash-reporting SDKs, no ads.
- **No servers** — Messages travel directly from device to device over Bluetooth/Wi-Fi Direct. Nothing is stored outside your device.
- **Open source** — The entire codebase is MIT-licensed and auditable.

---

## Project Structure

```
vicinity/
├── App/
│   └── VicinitApp.swift              # @main entry point, SwiftData container, service injection
├── Multipeer/
│   └── MultipeerSession.swift        # All MC logic (ObservableObject) + Combine handshake publisher
├── Models/
│   ├── Message.swift                 # SwiftData @Model — chat messages
│   ├── Peer.swift                    # Volatile peer state + connection status
│   ├── KnownPeer.swift               # SwiftData @Model — persisted friend identities
│   └── ScheduledMessage.swift        # SwiftData @Model — pending/sent/cancelled scheduled messages
├── Services/
│   ├── ScheduledMessageService.swift # Delivery orchestration, CRUD, local notifications
│   └── ProximityBluetoothService.swift # Core Bluetooth dual-role (advertise + scan) for background wakeup
├── Views/
│   ├── ContentView.swift             # Root view — peer list
│   ├── ChatView.swift                # Conversation thread
│   ├── KnownFriendsView.swift        # Persisted friends list
│   ├── ScheduledMessagesView.swift   # Scheduled messages per peer
│   ├── ScheduleMessageView.swift     # Compose new scheduled message
│   └── SettingsView.swift            # Display name + export
├── Utilities/
│   └── ExportManager.swift           # JSON export via system Share Sheet
└── Resources/
    └── PrivacyInfo.xcprivacy         # App Store privacy manifest
```

---

## Export Format

Conversations can be exported as JSON and shared via AirDrop or any iOS Share Sheet destination:

```json
{
  "exportedAt": "2024-01-01T12:00:00Z",
  "peer": "Alice's iPhone",
  "messages": [
    {
      "direction": "outgoing",
      "sender": "Bob's iPhone",
      "text": "Hey!",
      "timestamp": "2024-01-01T11:59:00Z"
    }
  ]
}
```

---

## Contributing Translations

Vicinity uses Xcode 15's `.xcstrings` string catalog — all translations live in a single JSON file: [`vicinity/Localizable.xcstrings`](vicinity/Localizable.xcstrings). The privacy permission string lives in [`vicinity/InfoPlist.xcstrings`](vicinity/InfoPlist.xcstrings).

### Option A — Edit the catalog directly (any text editor)

1. Open `vicinity/Localizable.xcstrings` in any editor (it is plain JSON).
2. For each string key, add an entry under your language code:
   ```json
   "zh-Hans" : { "stringUnit" : { "state" : "translated", "value" : "Your translation" } }
   ```
3. Open a Pull Request — the catalog is the only file that needs to change for most languages.

### Option B — Use Xcode's visual translation editor

1. Run the export script to produce `.xcloc` packages:
   ```bash
   bash scripts/export-localizations.sh
   ```
2. Double-click a `.xcloc` file in Finder — Xcode opens a side-by-side translation editor.
3. Translate the strings and save.
4. Copy the updated `Localizable.xcstrings` from inside the `.xcloc` back into `vicinity/`.
5. Open a Pull Request.

### Adding a new language

1. Add your translations to `vicinity/Localizable.xcstrings` under the new language code (e.g. `"fr"`).
2. Add the same code to `knownRegions` in `vicinity.xcodeproj/project.pbxproj`.
3. Translate the privacy permission in `vicinity/InfoPlist.xcstrings` as well.
4. Add `--exportLanguage <code>` to `scripts/export-localizations.sh` so future contributors can get an `.xcloc` for your language too.

---

## License

MIT — see [LICENSE](LICENSE) for details.