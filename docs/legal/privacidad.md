# Política de privacidad de Ghostlime IPTV

Borrador pendiente de revisión por el responsable.

Responsable del tratamiento: [RESPONSABLE]. Contacto: [EMAIL_CONTACTO]. Más información: https://github.com/guimo-dev/ghostlime-iptv/blob/main/docs/legal/privacidad.md.

Solo guardamos lo imprescindible. Sin cuenta, ningún dato tuyo llega a servidores de Ghostlime: todo queda en tu dispositivo. La app solo se conecta a los proveedores de las listas que añades (y a las URL de guía que indiques), que ven tu dirección IP como en cualquier otro reproductor.

## Qué datos se guardan

- El email de tu cuenta, si creas una.
- Lo que sincronizas, si usas cuenta: tus listas (con sus credenciales), favoritos, progreso y ajustes.

No pedimos nombre, teléfono, fecha de nacimiento ni nada más.

## Cómo se protegen

Lo que sincronizas se cifra en tu dispositivo con AES-256-GCM antes de enviarse.

- **Cuenta con email y contraseña:** la clave de cifrado se deriva de tu contraseña (Argon2id) en tu dispositivo. Ni el responsable ni nadie con acceso al servidor puede leer tus datos. Si olvidas la contraseña, no se pueden recuperar.
- **Cuenta con Google:** no tienes que escribir ninguna clave. Tu clave de cifrado se guarda en el servidor, protegida por una función del servidor que solo se la entrega a tu usuario. Una copia de seguridad de la base de datos no basta para leer tus datos, pero quien controle el proyecto del servidor sí podría hacerlo.

## Base legal

- Cuenta y sincronización: ejecución del contrato, es decir, prestarte el servicio que pides al crear la cuenta.
- Uso sin cuenta: no tratamos datos tuyos en nuestros servidores.
- Consentimiento: aceptas estos textos y los términos de uso al empezar.

## Para qué se usan

Solo para que puedas iniciar sesión y sincronizar tus datos entre dispositivos. No se usan para nada más.

## Dónde se guardan

En servidores de Supabase, que actúa como encargado del tratamiento. La región es la que muestra el proyecto de Supabase (pendiente de confirmar: UE).

## Cuánto tiempo

Mientras tengas la cuenta. Al borrarla se borran en el servidor tu usuario y todos tus datos sincronizados. Las copias de seguridad de Supabase pueden conservarlos un tiempo limitado más.

## Analíticas y publicidad

Ghostlime no tiene analíticas, telemetría, informes de fallos, publicidad ni rastreo. El registro de reproducción (qué has visto) se queda en tu dispositivo y no se envía.

## Tus derechos

- **Acceso y portabilidad:** en Ajustes → Cuenta → "Exportar mis datos" obtienes un fichero JSON con tus datos.
- **Borrado:** en Ajustes → Cuenta → "Borrar mi cuenta" se borran tu cuenta y tus datos del servidor.
- **Otros derechos** (rectificación, oposición, limitación) o dudas: escribe a [EMAIL_CONTACTO]. También puedes reclamar ante la autoridad de protección de datos de tu país.
