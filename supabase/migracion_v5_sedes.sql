-- v5: sedes de residencia / fellowship en cirugía bariátrica (lista que administra el coordinador).
create table if not exists public.sedes (
  id      uuid primary key default gen_random_uuid(),
  nombre  text not null unique,
  ciudad  text,
  estado  text,
  activo  boolean not null default true,
  creado  timestamptz not null default now()
);
alter table public.sedes enable row level security;
drop policy if exists "sedes leer" on public.sedes;
create policy "sedes leer" on public.sedes for select to anon, authenticated using (true);
drop policy if exists "sedes admin" on public.sedes;
create policy "sedes admin" on public.sedes for all to authenticated using (public.es_admin()) with check (public.es_admin());
grant select on public.sedes to anon, authenticated;
grant insert, update, delete on public.sedes to authenticated;
