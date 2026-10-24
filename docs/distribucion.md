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

## 1. Repositorio en GitHub

El repositorio ya existe: <https://github.com/guimo-dev/ghostlime-iptv>.

```bash
git clone https://github.com/guimo-dev/ghostlime-iptv.git
```

## 2. Supabase (una vez)

1. Crear un proyecto en <https://supabase.com> (plan gratuito).
2. SQL Editor → pegar `supabase/schema.sql` → Run.
3. Authentication → Providers → Email: activado. Recomendado: "Confirm email" activado.
   Authentication → Sign In / Providers → "Minimum password length" a 10 (la app
   también lo exige).
4. Authentication → Email Templates: la app de escritorio no tiene enlaces profundos, así
   que confirma la cuenta y restablece la contraseña con un **código** que se escribe en la app.
   Las plantillas **"Confirm signup"**, **"Reset password"** y **"Magic Link"** tienen que
   incluir `{{ .Token }}` (por ejemplo: `Tu código es: {{ .Token }}`). Sin él, el correo
   solo trae un enlace que la app no puede usar. "Magic Link" es el correo de
   "¿Olvidaste el PIN?" del control parental (la app no inicia sesión con enlaces).
5. Settings → API: copiar **Project URL** y la clave **anon public**.
6. GitHub → Settings → Secrets and variables → Actions → New repository secret:
   `SUPABASE_URL` y `SUPABASE_ANON_KEY`.
7. Para desarrollo local, añadirlas a `env/dev.json` (`SUPABASE_URL`, `SUPABASE_ANON_KEY`).

La clave `anon` es pública por diseño: la seguridad la ponen las políticas RLS del
esquema y el cifrado de extremo a extremo de la app.

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
