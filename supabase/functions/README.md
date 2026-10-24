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
