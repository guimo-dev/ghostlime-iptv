# Cuenta y sincronización

Opcional. Con una cuenta, tus listas, favoritos, progreso y ajustes viajan entre
dispositivos cifrados. Con **email y contraseña** el cifrado es **de extremo a extremo**:
la clave se deriva de tu contraseña y ni URLs, ni usuarios, ni nombres de canales viajan
en claro. Con **Google** (solo en versiones de Windows compiladas con `GOOGLE_SIGN_IN`) no escribes ninguna clave: se guarda en el servidor, protegida
por una función que solo se la entrega a tu usuario. Una copia de la base de datos no
basta para leer tus datos, pero quien controle el proyecto del servidor sí podría (ver
la [política de privacidad](../legal/privacidad.md)).

![Sección Cuenta en una versión sin servicio de sincronización](img/ajustes-cuenta-sin-supabase.png)

## Pasos

1. Puedes crearla en la pantalla de bienvenida (**Entrar con email**, **Crear cuenta** o
   **Continuar con Google**, que solo aparece en versiones compiladas con él) o después en **Ajustes** > **Cuenta**.
2. Con email: escribe email y contraseña, y pulsa **Crear cuenta** (o **Entrar** si ya
   tienes). Con Google: pulsa **Continuar con Google** y termina en el navegador; no hay
   contraseña de sincronización que escribir.
3. Si se pide confirmar el email, escribe el código recibido en **Introducir código**.
4. Al entrar, la app te pregunta qué hacer con lo que ya hay en la nube y en el
   dispositivo (por ejemplo **Unir con esta cuenta** o **Descartar datos locales**).
5. **Sincronizar ahora** fuerza una sincronización; la última queda indicada.
6. Una vez iniciada la sesión aparece, en cada dispositivo, **Sincronizar ajustes en este dispositivo**, que decide si también se
   sincronizan los ajustes de la app, el orden de canales y grupos, los grupos ocultos
   y el conmutador **Guía** de Directo. Las listas, favoritos y progreso se
   sincronizan siempre.

## Borrar mi cuenta

En **Ajustes** > **Cuenta**, **Borrar mi cuenta**. La app envía un código a tu email;
escríbelo, marca si quieres **Borrar también de este dispositivo** y pulsa **Borrar
cuenta**. Se eliminan la cuenta y todos sus datos en la nube, y **no se puede deshacer**.

## Exportar mis datos

En **Ajustes** > **Cuenta** (o en la sección de cuenta aunque no hayas entrado),
**Exportar mis datos** > **Exportar** guarda un fichero JSON con lo que hay en este
dispositivo (con una cuenta, coincide con lo sincronizado): tus listas, favoritos,
progreso y ajustes, incluidas la dirección del servidor y el usuario Xtream de cada
lista, pero sin contraseñas ni PIN.

## Consejos y límites

- **Si olvidas la contraseña tendrás que empezar de cero en la nube**: nadie puede
  descifrar tus datos sin ella.
- Las cuentas solo funcionan en versiones compiladas con los datos de un servicio de
  sincronización. Si ves "Sincronización no configurada", esta versión no lo incluye
  y la app funciona igual, sin cuentas (la captura de arriba es de ese caso).
- **Cerrar sesión** deja tus datos en el dispositivo, pero dejan de sincronizarse. Con
  el [control parental](control-parental.md) activo, antes pide el PIN, y al cerrar la
  sesión lo desactiva y borra el PIN.
- El control parental necesita una cuenta iniciada; si olvidas el PIN, se recupera con
  un código que llega al email de la cuenta.
- **Empezar de cero en la nube** aparece si los datos de la nube ya no se pueden abrir
  (por ejemplo, tras restablecer la contraseña). Tras confirmar con la contraseña,
  borra lo que hay en la nube y lo sustituye por los datos de este dispositivo; lo que
  solo exista en otros dispositivos se pierde.
- El PIN y las categorías bloqueadas nunca se sincronizan.
