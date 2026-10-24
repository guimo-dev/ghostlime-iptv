-- Ghostlime IPTV — backend de sincronización (Supabase).
-- Pegar entero en Supabase → SQL Editor → Run. Se puede ejecutar varias veces.
--
-- Todo lo que guarda la app aquí va CIFRADO en el dispositivo (AES-256-GCM con
-- una clave que solo conoce el usuario). El servidor solo ve blobs opacos.

-- Perfil de cifrado de cada usuario: sal de Argon2id y clave de datos envuelta.
create table if not exists public.profiles (
  user_id uuid primary key references auth.users (id) on delete cascade,
  kdf_salt text not null,          -- base64
  wrapped_key text not null,       -- base64(nonce | cifrado | mac)
  created_at timestamptz not null default now()
);

-- Elementos sincronizados (listas, favoritos, progreso, preferencias, ajustes).
create table if not exists public.sync_items (
  user_id uuid not null references auth.users (id) on delete cascade,
  kind text not null,
  item_id text not null,
  payload text,                    -- base64(nonce | cifrado | mac); en borrados, un vacío cifrado
  updated_at timestamptz not null, -- hora del cambio en el dispositivo (gana la más nueva)
  deleted boolean not null default false,
  synced_at timestamptz not null default now(), -- hora del servidor, para descargas incrementales
  primary key (user_id, kind, item_id)
);

create index if not exists sync_items_user_synced
  on public.sync_items (user_id, synced_at);

-- synced_at siempre lo pone el servidor. search_path vacío: nada se resuelve
-- por nombre suelto, así que nadie puede suplantar una función.
create or replace function public.touch_synced_at() returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.synced_at := pg_catalog.now();
  return new;
end $$;

drop trigger if exists sync_items_touch on public.sync_items;
create trigger sync_items_touch
  before insert or update on public.sync_items
  for each row execute function public.touch_synced_at();

-- Row Level Security: cada usuario solo ve y toca lo suyo.
alter table public.profiles enable row level security;
alter table public.sync_items enable row level security;

drop policy if exists "own profile" on public.profiles;
create policy "own profile" on public.profiles
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "own items" on public.sync_items;
create policy "own items" on public.sync_items
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- Subida de elementos con "gana el más nuevo" decidido en el servidor: un
-- dispositivo con datos viejos (o un cliente manipulado) no puede pisar una
-- fila más reciente. Corre con los permisos de quien llama (RLS aplica) y el
-- usuario sale de la sesión, nunca del argumento.
-- items: [{ "kind", "item_id", "payload", "updated_at", "deleted" }, ...]
create or replace function public.push_items(items jsonb) returns void
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  insert into public.sync_items as t
    (user_id, kind, item_id, payload, updated_at, deleted)
  select auth.uid(), i.kind, i.item_id, i.payload, i.updated_at, i.deleted
  from jsonb_to_recordset(items) as i(
    kind text, item_id text, payload text, updated_at timestamptz, deleted boolean
  )
  on conflict (user_id, kind, item_id) do update
    set payload = excluded.payload,
        updated_at = excluded.updated_at,
        deleted = excluded.deleted
    where excluded.updated_at > t.updated_at;
end $$;

revoke execute on function public.push_items(jsonb) from public, anon;
grant execute on function public.push_items(jsonb) to authenticated;
