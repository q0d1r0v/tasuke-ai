# Privacy Policy

**Tasuke AI** — last updated 21 September 2026

## The short version

Tasuke AI collects nothing.

There is no account, no server and no analytics. Your voice, your transcripts
and your tasks are created on your phone, stored on your phone, and stay on your
phone. We cannot read them, because they never reach us.

## What we collect

Nothing. Not an email address, not a device identifier, not a usage statistic,
not a crash report.

We do not operate a server for this app. There is no database anywhere that has
a row for you.

## What stays on your device

All of it:

- the audio you record while the recording screen is open
- the text your speech is transcribed into
- your tasks, their dates, their reminders and their completion history
- your settings, including whether you have Tasuke Pro

This lives in the app's private storage area, which other apps on your device
cannot read. Uninstalling Tasuke AI deletes it. **Settings → Delete all data**
deletes it without uninstalling.

## Your microphone

The microphone is used only while the recording screen is open, and only after
you have granted permission.

Audio is streamed straight into the on-device speech model and discarded as it
is processed. **No audio file is ever written to storage**, and no audio is ever
transmitted anywhere. Nothing is recorded in the background — the app declares
no background audio capability and cannot listen when it is not in front of you.

If you refuse microphone access, the rest of the app works normally; you type
your tasks instead.

## The one network request

Tasuke AI makes exactly one outbound request in its entire life: on first
launch it downloads its language model file (about 219 MB) from
`huggingface.co`.

That request carries no personal data. It is an ordinary file download, the same
as any other; Hugging Face will see the request in their own server logs, as any
website would, under their own privacy policy.

After the download finishes, Tasuke AI never contacts the network again. You can
switch off mobile data and Wi-Fi permanently and every feature still works.

## Backups

Your task database is part of your app data, so it is included in your device's
own backup if you have one switched on — iCloud Backup on iOS, or Google's
backup service on Android. Those backups are encrypted by Apple and Google and
are governed by their privacy policies, not by ours. We have no access to them.

If you do not want your tasks in a backup, turn off backup for Tasuke AI in your
device settings.

## Subscriptions

Tasuke Pro is billed by Apple or by Google, never by us. We never see your name,
your card or your billing address. The app asks the store whether a subscription
is active and receives an answer; that answer is stored on your device and
nowhere else.

Apple's and Google's handling of your purchase is covered by their own privacy
policies.

## Notifications

Reminders are local notifications, scheduled by your device for a time you
chose. There is no push service, no notification token and no server that could
send you a message.

## Children

Tasuke AI is not directed at children and collects no data from anyone,
including children.

## Your rights

Data-protection law gives you the right to access, correct, export and delete
the personal data a company holds about you. We hold none, so there is nothing
to request. Your data is in your hands: it is on your device, and you can delete
it at any moment from Settings, or by uninstalling the app.

## Third-party code

Tasuke AI is built on open-source components — Flutter, whisper.cpp, llama.cpp,
SQLite and the packages listed in the project's `pubspec.yaml`. All of them run
locally on your device. None of them is an advertising, analytics or attribution
SDK, and none of them sends data anywhere.

## Changes to this policy

If this policy changes, the updated text ships inside the app and the date at
the top changes with it. Because the policy is bundled in the app rather than
fetched from a server, it cannot be changed underneath a version you have
already installed.

## Contact

support@tasuke.app
