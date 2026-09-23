# App Review notes — Tasuke AI 1.0.0 (1)

Paste into **App Store Connect → App Review Information → Notes**, and into
**Play Console → App content → App access / Testing instructions**.

---

## There is no account, and no demo credentials to give you

Tasuke AI has **no sign-in, no sign-up, no backend and no user identity of any
kind**. Every screen and every feature is reachable from a cold install with no
credentials.

**Guideline 5.1.1(v) (account deletion) is therefore Not Applicable**: there is
no account to delete. Task data lives only in a SQLite database inside the app's
own container, and uninstalling the app removes it. Settings → "Delete all data"
also clears it in place.

We are stating this explicitly because "no account" is the most common reason a
build is bounced for missing demo credentials.

---

## Nothing to download, and no server of our own

The speech model (whisper.cpp, `ggml-base.en-q5_1`) is **bundled in the
binary**, and tasks are extracted from the transcript by deterministic,
on-device rules. There is no download on first launch, and voice capture works
from the start.

- no analytics, no crash reporter, no ads, no attribution SDK, no remote config
- no API, because there is no server
- speech and text never leave the device

The only network traffic is the subscription itself: plans, purchases and
restores go through Apple's or Google's own billing. Links such as "Manage
subscription" open in the browser or the store app.

If your test device is offline, the app still launches, and voice capture,
tasks and reminders all work. Only the paywall's plans, buying and restoring
need a connection.

---

## Microphone

- Requested only when you first tap the microphone button, with the reason
  string from `NSMicrophoneUsageDescription`.
- Active **only** while the recording sheet is on screen. It is modal and
  foreground; the app declares **no `UIBackgroundModes`** and cannot record in
  the background.
- Audio is streamed to the on-device speech model (whisper.cpp) as PCM frames
  and discarded. **No audio file is ever written to disk**, and no audio is
  transmitted.
- Denying the microphone does not break the app — task creation falls back to
  typing.

## Notifications

Local notifications only (`flutter_local_notifications`). They are scheduled by
the device for a task's own reminder time. There is no push service, no device
token and no server that could send you anything.

On Android the app requests `POST_NOTIFICATIONS` and `SCHEDULE_EXACT_ALARM`. It
deliberately does **not** declare `USE_EXACT_ALARM`; if exact alarms are refused
the app degrades to an inexact reminder and says so.

---

## Test script — please run this one

1. Launch the app. Accept the microphone prompt.
2. Tap the large microphone button in the centre of the bottom bar.
3. Say, in one breath:

   > **"Tomorrow at 3 PM send the build to James and Friday check App Store"**

4. Stop the recording.

**Expected result — the Confirm screen lists exactly two tasks:**

| Task | Date | Time |
| ---- | ---- | ---- |
| Send the build to James | tomorrow's date | 3:00 PM |
| Check App Store | the coming Friday | no time |

5. Tap **Save**. Both tasks appear on Home, grouped under their dates.
6. Open the first task → a reminder is scheduled for tomorrow at 3:00 PM.

Everything in steps 2–6 works with the device in **Airplane Mode**, and we
encourage you to try it that way.

---

## Free tier and the paywall

- **Free, with no time limit:** 1 capture per day, spoken or typed (a voice
  note or a task added by hand), unlimited reminders, unlimited history, every
  settings screen.
- The counter resets at local midnight. Only a *successful* capture counts — a
  capture that hit silence or failed to transcribe does not consume quota.
- After the first capture in a day, tapping the microphone shows the paywall
  with "You've used today's free capture." Dismissing it returns to the app,
  which continues to work; only adding new tasks is gated.
- **Tasuke Pro** removes the daily limit: `tasuke_pro_monthly` ($4.99/month) and
  `tasuke_pro_yearly` ($39.99/year), one subscription group, auto-renewing, no
  introductory offer. Prices shown in-app are always the store's own localised
  strings.
- **Restore Purchases** is on the paywall and in Settings.
- Terms of Use and Privacy Policy are linked from the paywall and are also
  bundled **inside the app** (`assets/legal/`), so they open with no network.

To reach the paywall without using the day's capture: **Settings →
Subscription**.

---

## What the app does not do

No location, no photos, no contacts, no calendar, no health data, no tracking,
no IDFA, no third-party SDKs beyond the open-source Flutter packages listed in
`pubspec.yaml`. `PrivacyInfo.xcprivacy` declares exactly three required-reason
APIs: UserDefaults (CA92.1), file size and timestamps inside our own container
(C617.1), and disk space for writing files (E174.1).

## Contact

<!-- Must match the address on the App Store Connect listing and in
     store/privacy-policy.html. -->
info@digital-group.uz
