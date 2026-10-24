# Distribución

Cómo se publica Ghostlime IPTV y qué tiene que hacer el propietario (cosas que Claude no
puede hacer por él: crear cuentas, pagar, firmar con sus claves).

## Resumen

- El código vive en GitHub. Cada etiqueta `vX.Y.Z` lanza `.github/workflows/release.yml`,
  que pasa los tests y genera:
  - **Windows**: instalador `Ghostlime-IPTV-X.Y.Z-windows-setup.exe` (Inno Setup).
  - **Android**: `.apk` (instalar directamente) y `.aab` (para Google Play).
  - **Linux**: `.tar.gz` con el ejecutable y sus librerías.
- Todo se adjunta a una **Release de GitHub**: la página de descargas.
- La sincronización usa **Supabase** (gratuito); sin sus claves la app funciona igual,
  sin cuentas.

## Antes de publicar: textos legales

Antes de publicar, sustituir los marcadores `[DOMINIO]`, `[EMAIL_CONTACTO]` y `[RESPONSABLE]` en `docs/legal/` (y revisar los textos). La build de una etiqueta falla si quedan: el job `test` ejecuta `flutter test test/legal --dart-define=LEGAL_RELEASE_CHECK=true`.

**Cada build de etiqueta falla mientras queden marcadores sin sustituir. Es intencionado**: impide publicar con textos legales a medias.

## 1. Repositorio en GitHub

El repositorio ya existe: <https://github.com/guimo-dev/ghostlime-iptv>.

```bash
git clone https://github.com/guimo-dev/ghostlime-iptv.git
```

## 2. Supabase (una vez)

1. Crear un proyecto en <https://supabase.com> (plan gratuito).
2. SQL Editor → pegar `supabase/schema.sql` → Run.
3. Authentication → Providers → Email: activado, con **"Confirm email" activado**
   (obligatorio: sin él, cualquiera podría crear cuentas con emails ajenos).
   Authentication → Sign In / Providers → "Minimum password length" a 10 (la app
   también lo exige).
4. Authentication → Emails → **SMTP Settings** → activar **Custom SMTP** con un
   proveedor propio (Resend, Brevo, Postmark…) y un remitente de tu dominio
   (por ejemplo `Ghostlime IPTV <no-reply@[DOMINIO]>`). El SMTP de Supabase por defecto
   solo envía a miembros del equipo y con un límite muy bajo: sin el propio, los
   usuarios no recibirían los códigos.
5. Authentication → Email Templates: la app de escritorio no tiene enlaces profundos, así
   que todo se confirma con un **código** que se escribe en la app. Pega en cada
   plantilla (campo "Message body", y un asunto corto en "Subject") el HTML de
   `supabase/templates/`:

   | Plantilla de Supabase | Fichero | Para qué sirve |
   | --- | --- | --- |
   | Confirm signup | `confirmar-alta.html` | Código al crear la cuenta |
   | Reset password | `recuperar-contrasena.html` | Código para restablecer la contraseña |
   | Magic Link | `codigo-acceso.html` | Recuperar el PIN del control parental y confirmar el borrado de la cuenta (la app no inicia sesión con enlaces) |
   | Change Email Address | `cambio-email.html` | No usada por la app hoy; plantilla de reserva |
   | Reauthentication | `reautenticacion.html` | No usada por la app hoy; plantilla de reserva |

   Todas llevan `{{ .Token }}` (el código); sin él, el correo solo traería un enlace
   que la app no puede usar. Solo usan la imagen del logo de GitHub (cámbiala por la de
   tu dominio cuando lo tengas) y ningún seguimiento.
6. Project Settings → General → **Región**: elige una de la UE (por ejemplo Frankfurt) si
   los usuarios están en Europa; no se puede cambiar después sin migrar el proyecto, y
   debe coincidir con lo que diga `docs/legal/privacidad.md`.
7. Settings → API: copiar **Project URL** y la clave **anon public**.
8. GitHub → Settings → Secrets and variables → Actions → New repository secret:
   `SUPABASE_URL` y `SUPABASE_ANON_KEY`.
9. Para desarrollo local, añadirlas a `env/dev.json` (`SUPABASE_URL`, `SUPABASE_ANON_KEY`).

La clave `anon` es pública por diseño: la seguridad la ponen las políticas RLS del
esquema y el cifrado de extremo a extremo de la app.

### Edge Functions

`delete-account` (borrar la cuenta; sin ella "Borrar mi cuenta" falla) y `key-escrow`
(clave de las cuentas de Google) se despliegan como explica
`supabase/functions/README.md` (`supabase functions deploy delete-account` y
`supabase functions deploy key-escrow`). `delete-account` no necesita secretos propios
(Supabase inyecta los suyos). `key-escrow` necesita el secreto
`KEY_ESCROW_SECRET`: 32 bytes aleatorios en base64, generados una sola vez, por ejemplo con

```bash
node -e "console.log(require('crypto').randomBytes(32).toString('base64'))"
```

y guardados en Edge Functions → Secrets (CLI: `supabase secrets set KEY_ESCROW_SECRET=...`).
Guárdalo también fuera de Supabase, en un sitio seguro: **si se pierde o se cambia, las
cuentas de Google ya no pueden abrir sus datos de la nube** (tendrían que empezar de cero).
No lo pongas nunca en el repositorio, en `env/dev.json` ni en la app.

### Entrar con Google (una vez)

Necesita una cuenta de Google Cloud del propietario (Claude no crea cuentas).

1. <https://console.cloud.google.com> → crear un proyecto (o usar uno) → APIs y servicios →
   **Pantalla de consentimiento de OAuth**: tipo "Externo", nombre "Ghostlime IPTV", email
   de asistencia `[EMAIL_CONTACTO]`, ámbitos solo `email`, `profile` y `openid` (no hace
   falta más; Supabase pide siempre `email` y `profile`, y guarda el nombre, la foto y el
   id de Google en sus tablas de autenticación; la app no los usa). Mientras esté "En pruebas", solo pueden entrar los usuarios de prueba que
   añadas; para todos, "Publicar la aplicación".
2. APIs y servicios → Credenciales → Crear credenciales → **ID de cliente de OAuth** →
   tipo **Aplicación web**. En "URIs de redireccionamiento autorizados" pon la URL de
   callback que muestra Supabase en el paso 3 (`https://<ID_DEL_PROYECTO>.supabase.co/auth/v1/callback`).
   Copia el **ID de cliente** y el **secreto de cliente**.
3. Supabase → Authentication → Sign In / Providers → **Google**: activar, pegar el ID y el
   secreto del paso 2 y guardar.
4. Supabase → Authentication → URL Configuration → **Redirect URLs**: añadir
   `ghostlime://login-callback` (es adonde vuelve el navegador; sin ella Supabase manda al
   "Site URL" y la app no se entera).
5. Ejecutar otra vez `supabase/schema.sql` (añade la columna `escrowed_key`) y desplegar
   `key-escrow` con su secreto (arriba).
6. **Encender el botón.** "Continuar con Google" solo funciona en builds compilados con
   `--dart-define=GOOGLE_SIGN_IN=true` (sin él se ve deshabilitado, "Disponible pronto").
   Hazlo solo cuando el proveedor de Google y `key-escrow` ya funcionen: en
   `.github/workflows/release.yml`, añadir `"--dart-define=GOOGLE_SIGN_IN=true"` a la línea
   `flutter build windows --release ...`; en local, a `flutter run` o a `env/dev.json`
   (`"GOOGLE_SIGN_IN": "true"`).

Cómo funciona en Windows: la app abre el navegador del sistema (flujo PKCE); al terminar,
Google → Supabase → `ghostlime://login-callback?code=...`. El instalador registra el
esquema `ghostlime` para el usuario (sin admin; para todos si se instala como admin) y lo
quita al desinstalar. El navegador abre una segunda copia de la app con el enlace, que se
lo pasa a la ventana ya abierta y se cierra. La app solo acepta ese enlace mientras espera
un "Continuar con Google" y solo con un `code` (o `error`) en la consulta; un enlace con
`access_token`/`refresh_token` se ignora siempre (evita que una web cuele otra sesión).
**La versión portable (zip) no registra el
esquema**: ahí "Continuar con Google" abre el navegador pero no vuelve a la app; se puede
usar email y contraseña.

Mismo email con contraseña y con Google: Supabase enlaza las dos identidades. Si la
cuenta ya tenía contraseña, entrar con Google pide esa contraseña una vez por dispositivo
y la cuenta sigue cifrada de extremo a extremo (la función se niega a custodiar su clave).

Para probar en desarrollo (`flutter run`), registra el esquema apuntando al ejecutable de
depuración (y bórralo al acabar con `reg delete HKCU\Software\Classes\ghostlime /f`):

```bat
reg add HKCU\Software\Classes\ghostlime /ve /d "URL:Ghostlime IPTV" /f
reg add HKCU\Software\Classes\ghostlime /v "URL Protocol" /d "" /f
reg add HKCU\Software\Classes\ghostlime\shell\open\command /ve /d "\"C:\ruta\al\repo\build\windows\x64\runner\Debug\iptv_player.exe\" \"%1\"" /f
```

Si además está instalada la versión normal, el esquema apunta a la que se registró la
última vez, y el enlace solo llega a una ventana de ese mismo ejecutable.

## 3. Firma de Android (una vez, necesaria para publicar Android)

Sin estos secretos el workflow **no publica Android** (deja un aviso): cada build de CI
se firmaría con una clave de depuración distinta y Android no dejaría actualizar sin
desinstalar.

```bash
keytool -genkey -v -keystore release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias iptv
```

Guardar `release.jks` y sus contraseñas **fuera del repo** (gestor de contraseñas). En
GitHub, secretos:
- `ANDROID_KEYSTORE_BASE64`: `base64 -w0 release.jks` (en PowerShell:
  `[Convert]::ToBase64String([IO.File]::ReadAllBytes("release.jks"))`)
- `ANDROID_KEY_ALIAS` (`iptv`), `ANDROID_KEY_PASSWORD`, `ANDROID_STORE_PASSWORD`.

Para firmar en local, crear `android/key.properties` (ignorado por git):

```properties
storeFile=../../release.jks
storePassword=…
keyAlias=iptv
keyPassword=…
```

## 4. Publicar una versión

1. Subir la versión en `pubspec.yaml` (`version: 1.1.0+2`: el `+N` debe crecer siempre
   para Android) y en `appVersion` de `lib/settings/settings_screen.dart`.
2. Etiquetar y subir:

```bash
git tag v1.1.0 && git push origin v1.1.0
```

3. En GitHub → Actions se ve el progreso; al terminar, la Release tiene los ficheros.

## 5. Google Play (opcional)

1. Cuenta de desarrollador de Google Play (pago único de 25 USD).
2. Crear la app, rellenar la ficha (descripción, capturas, política de privacidad:
   la app no recoge datos propios; la cuenta guarda datos cifrados en Supabase).
3. Subir el `.aab` de la Release a una pista de prueba interna y, cuando funcione, a
   producción. Google gestiona la clave final de firma ("Play App Signing").

Nota: Google Play revisa las apps IPTV; la app no incluye contenido ni listas, solo
reproduce las del usuario. Conviene dejarlo claro en la ficha.

## 6. Windows: SmartScreen

El instalador no está firmado con un certificado de editor (cuesta dinero al año), así
que Windows mostrará "Windows protegió su PC" la primera vez: **Más información →
Ejecutar de todas formas**. Si algún día se quiere evitar, hace falta un certificado de
firma de código y añadir `signtool` al workflow.

El instalador incluye el runtime de Visual C++ 2015-2022 x64 y lo instala solo si falta.
El workflow lo descarga a `installer\vc_redist.x64.exe`; para compilar el instalador en
local hay que descargarlo ahí antes (está ignorado por git).

Al desinstalar, el desinstalador pregunta (por defecto "No") si borrar también los datos
de la app: solo elimina `%APPDATA%\dev.guimo\iptv_player`, nunca nada por encima. En
desinstalación silenciosa no pregunta ni borra. En instalaciones por máquina (admin),
`{userappdata}` sigue siendo el AppData del usuario que lanza el desinstalador.

## 7. Linux: dependencias en el equipo

El `.tar.gz` lleva el ejecutable y las librerías de Flutter, pero usa las del sistema
para vídeo y para guardar contraseñas. En Debian/Ubuntu:

```bash
sudo apt install libmpv2 libgtk-3-0 libsecret-1-0 gnome-keyring
```

(En distribuciones antiguas el paquete es `libmpv1`.) Hace falta un llavero activo
(GNOME Keyring o KWallet) para guardar las contraseñas de las listas y la clave de sync.
Descomprimir y ejecutar `./iptv_player`.

## iOS

Fuera por ahora: requiere cuenta Apple Developer (99 USD/año) y builds en macOS
(GitHub tiene runners macOS si se quiere añadir más adelante).
