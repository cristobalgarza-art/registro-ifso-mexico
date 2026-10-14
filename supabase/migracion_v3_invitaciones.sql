-- =====================================================================
--  Migración v3: registro cerrado por invitación.
--  Solo puede crear cuenta un correo que el coordinador haya invitado.
--  Al registrarse, el usuario queda en el centro (o como residente) que dice su invitación.
-- =====================================================================

create table if not exists public.invitaciones (
  email       text primary key,
  rol         text not null default 'centro' check (rol in ('admin','centro','residente')),
  centro_id   uuid references public.centros(id) on delete set null,
  nota        text,
  invitado_por uuid references auth.users(id) on delete set null,
  creado      timestamptz not null default now(),
  usado       timestamptz
);
alter table public.invitaciones enable row level security;
drop policy if exists invitaciones_admin on public.invitaciones;
create policy invitaciones_admin on public.invitaciones for all to authenticated
  using (public.es_admin()) with check (public.es_admin());
grant select, insert, update, delete on public.invitaciones to authenticated;

-- Interruptor: si está en 'true', solo se registran correos invitados.
create table if not exists public.ajustes (clave text primary key, valor text);
insert into public.ajustes (clave, valor) values ('registro_cerrado','true') on conflict (clave) do nothing;
alter table public.ajustes enable row level security;
drop policy if exists ajustes_ver on public.ajustes;
create policy ajustes_ver on public.ajustes for select to authenticated using (true);
drop policy if exists ajustes_admin on public.ajustes;
create policy ajustes_admin on public.ajustes for all to authenticated using (public.es_admin()) with check (public.es_admin());
grant select, insert, update on public.ajustes to authenticated;

-- Cualquiera (incluso sin sesión) puede preguntar si un correo está invitado, para dar un mensaje claro antes de registrarse.
create or replace function public.correo_invitado(p_email text) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select valor from public.ajustes where clave='registro_cerrado'),'true') <> 'true'
      or (select count(*) from public.perfiles) = 0
      or exists (select 1 from public.invitaciones where lower(email) = lower(trim(p_email)));
$$;
grant execute on function public.correo_invitado(text) to anon, authenticated;

-- Al crearse la cuenta: rechaza si no está invitado; si lo está, asigna rol y centro de la invitación.
create or replace function public.crear_perfil() returns trigger
language plpgsql security definer set search_path = public as $$
declare inv public.invitaciones; cerrado boolean; primero boolean;
begin
  primero := (select count(*) from public.perfiles) = 0;
  cerrado := coalesce((select valor from public.ajustes where clave='registro_cerrado'),'true') = 'true';
  select * into inv from public.invitaciones where lower(email) = lower(new.email);
  if cerrado and not primero and inv.email is null then
    raise exception 'Este correo no tiene invitación. Pide al coordinador del registro que te invite.';
  end if;
  insert into public.perfiles (user_id, email, nombre, rol, centro_id, sede, anio_res)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data->>'nombre', split_part(new.email,'@',1)),
    case when primero then 'admin'
         when inv.email is not null then inv.rol
         when new.raw_user_meta_data->>'rol' = 'residente' then 'residente'
         else 'centro' end,
    inv.centro_id,
    new.raw_user_meta_data->>'sede',
    new.raw_user_meta_data->>'anio_res'
  )
  on conflict (user_id) do nothing;
  if inv.email is not null then update public.invitaciones set usado = now() where email = inv.email; end if;
  return new;
end $$;

-- El coordinador puede borrar una cuenta (perfil + usuario de auth). Sus pacientes se conservan en el centro.
create or replace function public.admin_borrar_usuario(p_user uuid) returns void
language plpgsql security definer set search_path = public, auth as $$
begin
  if not public.es_admin() then raise exception 'Solo administradores'; end if;
  if p_user = auth.uid() then raise exception 'No puedes borrar tu propia cuenta'; end if;
  delete from auth.users where id = p_user;
end $$;
grant execute on function public.admin_borrar_usuario(uuid) to authenticated;
