<p align="center">
  <img src="branding/ghostlime-192.png" width="96" alt="Ghostlime IPTV">
</p>

<h1 align="center">Ghostlime IPTV</h1>

<p align="center">Tu IPTV, a tu manera. Reproductor de listas IPTV (Xtream Codes y M3U)
para Windows, Android y Linux.</p>

> **English:** Ghostlime IPTV is a lightweight IPTV player (Xtream Codes and M3U) built
> with Flutter and libmpv. It plays HEVC/4K channels that browser-based players can't,
> lets you sort channels your way, and syncs your playlists across devices with
> end-to-end encryption. It ships no content: you bring your own playlists.

## Qué ofrece

- **Reproduce lo que otros no pueden**: usa libmpv, así que canales HEVC/4K con audio
  MP2 o AC3 se ven y se oyen (en reproductores web solo suena el audio o fallan).
- **Directo pensado para la tele**: vista previa del canal, guía EPG, ahora y después,
  reconexión automática.
- **Ordena los canales como quieras**, por categoría: original, A→Z, Z→A, manual
  (arrastrando) y favoritos primero.
- **Películas y series** con portadas, fichas, temporadas y "seguir viendo" donde lo
  dejaste, con siguiente episodio automático.
- **Favoritos, recientes y búsqueda** en todo el catálogo.
- **Control parental** con PIN y categorías ocultas.
- **Cuenta opcional con sincronización cifrada de extremo a extremo**: listas,
  favoritos, progreso y ajustes en todos tus dispositivos. El servidor solo guarda
  datos cifrados con una clave derivada de tu contraseña; ni URLs, ni usuarios, ni
  nombres de canales viajan en claro.

## Descargar

Las versiones publicadas están en
[Releases](https://github.com/guimo-dev/ghostlime-iptv/releases):

| Plataforma | Fichero |
|---|---|
| Windows 10/11 (x64), instalador | `Ghostlime-IPTV-X.Y.Z-windows-setup.exe` |
| Windows 10/11 (x64), portable | `Ghostlime-IPTV-X.Y.Z-windows-portable.zip` |
| Android | `Ghostlime-IPTV-X.Y.Z-android.apk` |
| Linux (x64) | `Ghostlime-IPTV-X.Y.Z-linux-x64.tar.gz` |

La versión portable no se instala: descomprime y ejecuta `iptv_player.exe`. Necesita el
[runtime de Visual C++](https://aka.ms/vs/17/release/vc_redist.x64.exe) (casi todos los
Windows ya lo tienen; el instalador lo añade si falta). Los datos se guardan igualmente
en `%APPDATA%\dev.guimo\iptv_player`.

En Windows, el instalador no está firmado: la primera vez SmartScreen avisa
(**Más información → Ejecutar de todas formas**). En Linux hacen falta `libmpv2`,
`libgtk-3-0`, `libsecret-1-0` y un llavero activo (ver
[docs/distribucion.md](docs/distribucion.md)).

## Guía de uso

Página por página, con capturas: [docs/guia](docs/guia/README.md).

## Compilar desde el código

Requisitos: [Flutter](https://docs.flutter.dev/get-started/install) 3.47 (stable).

```bash
flutter pub get
flutter test
flutter run -d windows
```

Para activar las cuentas, crea un proyecto de [Supabase](https://supabase.com),
ejecuta [supabase/schema.sql](supabase/schema.sql) y pasa sus claves al compilar:

```bash
flutter run -d windows --dart-define=SUPABASE_URL=https://xxxx.supabase.co --dart-define=SUPABASE_ANON_KEY=...
```

O cópialas en `env/dev.json` (plantilla en `env/dev.example.json`, ignorado por git) y
usa `--dart-define-from-file=env/dev.json`. Sin ellas la app funciona igual, sin
cuentas.

Cómo se publican las versiones (GitHub Actions, firma de Android, Google Play):
[docs/distribucion.md](docs/distribucion.md).

## Aviso

Ghostlime IPTV no incluye, vende ni enlaza canales, listas ni ningún otro contenido.
Solo reproduce las listas que añade cada usuario, que es responsable de tener derecho
a verlas.

## Licencia

[Apache-2.0](LICENSE). El nombre "Ghostlime" y su logo no están cubiertos por la
licencia (ver [NOTICE](NOTICE)): un fork debe usar nombre y logo propios.
