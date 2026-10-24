# Edge Functions

## `delete-account`

Borra al usuario que la llama; sus filas de `sync_items` y `profiles` caen con él
(`on delete cascade` de `schema.sql`), de forma atómica. Supabase solo deja borrar usuarios con la clave de servicio, que
por eso vive únicamente en la función (`SUPABASE_URL` y `SUPABASE_SERVICE_ROLE_KEY`
las inyecta Supabase; no hay que configurar nada). Verifica el JWT del usuario y
borra **solo a ese usuario**; sin JWT válido responde 401. No registra tokens.

La app la llama tras comprobar el código que se envía por email (Ajustes → Cuenta →
"Borrar mi cuenta").

### Desplegar

Con la CLI de Supabase (desde la raíz del repo):

```
supabase login
supabase link --project-ref <ID_DEL_PROYECTO>
supabase functions deploy delete-account
```

O desde el panel: Edge Functions → Deploy a new function → "Via Editor", nombre
`delete-account`, pegar `delete-account/index.ts` y desplegar. La función verifica
ella misma el token (`auth.getUser`), así que con las claves de firma JWT
asimétricas nuevas y la clave publicable puede hacer falta **desactivar** el
interruptor "Verify JWT" de la pasarela (CLI: `--no-verify-jwt`); si no, la
pasarela puede rechazar con 401 tokens válidos. Comprueba también que
`SUPABASE_SERVICE_ROLE_KEY` existe en el entorno de la función (en proyectos
con claves nuevas puede haber que crearla como secreto con ese nombre).

### Probar

Usa un usuario de prueba, nunca uno real. Con su sesión (el `access_token` que
devuelve `POST <SUPABASE_URL>/auth/v1/token?grant_type=password`):

```
# Sin JWT: debe dar 401
curl -i -X POST "$SUPABASE_URL/functions/v1/delete-account"

# Con el JWT del usuario de prueba: 200 y el usuario desaparece de Authentication
curl -i -X POST "$SUPABASE_URL/functions/v1/delete-account" \
  -H "Authorization: Bearer $USER_JWT" \
  -H "apikey: $SUPABASE_PUBLISHABLE_KEY"
```

Comprueba en el panel que el usuario y sus filas de `sync_items` y `profiles` ya no
existen. En local: `supabase start` y `supabase functions serve delete-account`.

Nota: no se ha podido ejecutar en este equipo (no hay Deno ni CLI de Supabase), así
que la función está sin probar hasta el primer despliegue.

## `key-escrow`

Custodia la clave de datos de las cuentas que entran con Google, para que no tengan que
escribir ninguna contraseña de sincronización (opción B del diseño). Verifica el JWT del
usuario con `auth.getUser` y toma el usuario **solo del token**; sin JWT válido, 401.

- `GET` → `200 { "key": "<base64 de 32 bytes>" }`, o `404` si no hay clave custodiada.
- `PUT { "key": "<base64 de 32 bytes>" }` → `200` si la guarda; `409` si ya había una
  (nunca la sustituye) o si la cuenta tiene perfil con contraseña (sigue siendo de
  extremo a extremo); `400` si la clave no es de 32 bytes.
- Otros métodos: `405`. Secreto ausente o mal formado: `500 not_configured`.

En `profiles.escrowed_key` guarda `base64(nonce | cifrado | tag)`: AES-256-GCM con el
secreto `KEY_ESCROW_SECRET` y el `user_id` como datos asociados (un valor copiado a la
fila de otro usuario no se abre). Una copia de la base de datos sin el secreto no basta
para leer las claves; quien controle el proyecto de Supabase sí podría. No registra
claves, tokens ni cuerpos.

### Secreto

32 bytes aleatorios en base64, generados una vez:

```
node -e "console.log(require('crypto').randomBytes(32).toString('base64'))"
supabase secrets set KEY_ESCROW_SECRET=<el valor>
```

O en el panel: Edge Functions → Secrets. Guárdalo también fuera de Supabase: si se pierde
o se cambia, las cuentas de Google no pueden abrir sus datos de la nube.

### Desplegar

```
supabase functions deploy key-escrow
```

(o "Via Editor" con el nombre `key-escrow`). Lo mismo que en `delete-account` sobre
"Verify JWT" y `SUPABASE_SERVICE_ROLE_KEY`. Antes, ejecutar otra vez `schema.sql`
(columna `escrowed_key` y `kdf_salt`/`wrapped_key` opcionales).

### Probar

Con un usuario de prueba (nunca uno real) y su `access_token`:

```
# Sin JWT: 401
curl -i "$SUPABASE_URL/functions/v1/key-escrow"

# Sin clave todavía: 404
curl -i "$SUPABASE_URL/functions/v1/key-escrow" \
  -H "Authorization: Bearer $USER_JWT" -H "apikey: $SUPABASE_PUBLISHABLE_KEY"

# Guardar una clave de prueba: 200; repetirlo (o con otra clave): 409
KEY=$(node -e "console.log(require('crypto').randomBytes(32).toString('base64'))")
curl -i -X PUT "$SUPABASE_URL/functions/v1/key-escrow" \
  -H "Authorization: Bearer $USER_JWT" -H "apikey: $SUPABASE_PUBLISHABLE_KEY" \
  -H "Content-Type: application/json" -d "{\"key\":\"$KEY\"}"

# Leerla: 200 con la misma clave
curl -i "$SUPABASE_URL/functions/v1/key-escrow" \
  -H "Authorization: Bearer $USER_JWT" -H "apikey: $SUPABASE_PUBLISHABLE_KEY"

# Clave mal formada: 400
curl -i -X PUT "$SUPABASE_URL/functions/v1/key-escrow" \
  -H "Authorization: Bearer $USER_JWT" -H "apikey: $SUPABASE_PUBLISHABLE_KEY" \
  -H "Content-Type: application/json" -d '{"key":"corta"}'
```

Comprueba también: con el JWT de un usuario con contraseña (perfil con `wrapped_key`),
el `PUT` da 409 y `escrowed_key` sigue vacío; en Table Editor, `escrowed_key` no
contiene la clave en claro; con el JWT de otro usuario, el `GET` da 404. Borra los
usuarios de prueba al acabar.

Nota: sin Deno en este equipo, la lógica se probó en Node 24 con un cliente de Supabase
falso (401/405/404/400, primer `PUT` 200, segundo 409, `GET` devuelve la clave, cuenta
con contraseña 409, valor copiado a otro usuario ilegible, secreto ausente o corto 500,
nada en los logs). Falta la prueba contra un Supabase real.
