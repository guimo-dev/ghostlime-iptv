<p align="center">
  <img src="branding/ghostlime-192.png" width="96" alt="Ghostlime IPTV">
</p>

<h1 align="center">Ghostlime IPTV</h1>

<p align="center">Your IPTV, your way. A lightweight IPTV player for Xtream Codes and M3U
playlists, built with Flutter and libmpv.</p>

## Features

- **Plays what browser-based players can't.** It uses libmpv, so HEVC/4K channels with
  MP2 or AC3 audio show picture and sound (web players often play only the audio, or
  fail).
- **Live TV built for the big screen.** Channel preview, the programme guide inside
  Live TV (the selected channel's schedule, or a full grid with one toggle), now/next,
  automatic reconnection.
- **Sort channels your way**, per category: provider order, A→Z, Z→A, manual
  (drag and drop) and favourites first.
- **Movies and series** with posters, details, seasons and "continue watching", with
  automatic next episode.
- **Favourites, recents and search** across the whole catalogue, from Home.
- **Parental control** with a PIN and hidden categories.
- **Optional account with end-to-end encrypted sync**: playlists, favourites, progress
  and, if you choose per device, settings. The server only stores data encrypted with a
  key derived from your password; no URLs, usernames or channel names leave your device
  in clear text.

## Download

Releases are published on
[Releases](https://github.com/guimo-dev/ghostlime-iptv/releases).

| Platform | File |
|---|---|
| Windows 10/11 (x64), installer | `Ghostlime-IPTV-X.Y.Z-windows-setup.exe` |
| Windows 10/11 (x64), portable | `Ghostlime-IPTV-X.Y.Z-windows-portable.zip` |
| Android (64-bit phones, tablets and TVs) | `Ghostlime-IPTV-X.Y.Z-android-arm64.apk` |
| Android (old 32-bit devices) | `Ghostlime-IPTV-X.Y.Z-android-armv7.apk` |
| Android (universal, if unsure) | `Ghostlime-IPTV-X.Y.Z-android.apk` |
| Linux x64 *(in progress)* | `Ghostlime-IPTV-X.Y.Z-linux-x64.tar.gz` |

On an Android TV you can install an APK with the Downloader app by entering the
[Releases](https://github.com/guimo-dev/ghostlime-iptv/releases) page address.

The portable version needs no installation: unzip it and run `iptv_player.exe`. It needs
the [Visual C++ runtime](https://aka.ms/vs/17/release/vc_redist.x64.exe) (almost every
Windows PC already has it; the installer adds it when missing). Data is stored in
`%APPDATA%\dev.guimo\iptv_player` either way.

The Windows installer is not code-signed, so SmartScreen warns the first time
(**More info → Run anyway**). On Linux you need `libmpv2`, `libgtk-3-0`,
`libsecret-1-0` and a running keyring (see [docs/distribucion.md](docs/distribucion.md)).

## User guide

Page by page, with screenshots (in Spanish for now): [docs/guia](docs/guia/README.md).

## Build from source

Requirements: [Flutter](https://docs.flutter.dev/get-started/install) 3.47 (stable).

```bash
flutter pub get
flutter test
flutter run -d windows
```

To enable accounts, create a [Supabase](https://supabase.com) project, run
[supabase/schema.sql](supabase/schema.sql) and pass its keys when building:

```bash
flutter run -d windows --dart-define=SUPABASE_URL=https://xxxx.supabase.co --dart-define=SUPABASE_ANON_KEY=...
```

Or put them in `env/dev.json` (template in `env/dev.example.json`, ignored by git) and use
`--dart-define-from-file=env/dev.json`. Without them the app works the same, without
accounts.

How releases are built (GitHub Actions, Android signing, Google Play):
[docs/distribucion.md](docs/distribucion.md) (Spanish).

## Privacy

Accounts are optional. Email accounts sync end-to-end encrypted; for Google accounts
the encryption key is kept on the server, so the project owner could access that data.
See the [privacy policy](docs/legal/privacidad.md) (Spanish).

## Disclaimer

Ghostlime IPTV does not include, sell or link to any channels, playlists or other
content. It only plays the playlists each user adds, and each user is responsible for
having the right to watch them.

## License

[Apache-2.0](LICENSE). The "Ghostlime" name and logo are not covered by the license (see
[NOTICE](NOTICE)): forks must use their own name and logo.
