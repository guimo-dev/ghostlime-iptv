# Cuenta y sincronización

Opcional. Con una cuenta, tus listas, favoritos, progreso y ajustes viajan entre
dispositivos con **cifrado de extremo a extremo**: el servidor solo guarda datos
cifrados con una clave derivada de tu contraseña. Ni URLs, ni usuarios, ni nombres de
canales viajan en claro.

![Sección Cuenta en una versión sin servicio de sincronización](img/ajustes-cuenta-sin-supabase.png)

## Pasos

1. Abre **Ajustes** > **Cuenta**.
2. Escribe email y contraseña, y pulsa **Crear cuenta** (o **Entrar** si ya tienes).
3. Si se pide confirmar el email, escribe el código recibido en **Introducir código**.
4. Al entrar, la app te pregunta qué hacer con lo que ya hay en la nube y en el
   dispositivo (por ejemplo **Unir con esta cuenta** o **Descartar datos locales**).
5. **Sincronizar ahora** fuerza una sincronización; la última queda indicada.
6. Una vez iniciada la sesión aparece, en cada dispositivo, **Sincronizar ajustes en este dispositivo**, que decide si también se
   sincronizan los ajustes de la app, el orden de canales y grupos, los grupos ocultos
   y el conmutador **Guía** de Directo. Las listas, favoritos y progreso se
   sincronizan siempre.

## Consejos y límites

- **Si olvidas la contraseña tendrás que empezar de cero en la nube**: nadie puede
  descifrar tus datos sin ella.
- Las cuentas solo funcionan en versiones compiladas con los datos de un servicio de
  sincronización. Si ves "Sincronización no configurada", esta versión no lo incluye
  y la app funciona igual, sin cuentas (la captura de arriba es de ese caso).
- **Cerrar sesión** deja tus datos en el dispositivo, pero dejan de sincronizarse.
- **Empezar de cero en la nube** aparece si los datos de la nube ya no se pueden abrir
  (por ejemplo, tras restablecer la contraseña). Tras confirmar con la contraseña,
  borra lo que hay en la nube y lo sustituye por los datos de este dispositivo; lo que
  solo exista en otros dispositivos se pierde.
- El PIN y las categorías bloqueadas nunca se sincronizan.
