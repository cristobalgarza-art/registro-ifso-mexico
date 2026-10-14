-- =====================================================================
--  REGISTRO IFSO MÉXICO · esquema de base de datos (Supabase / Postgres)
--  Pegar completo en: Supabase → SQL Editor → New query → Run
--  Es seguro correrlo más de una vez.
-- =====================================================================

create extension if not exists pgcrypto;

-- ---------- Tablas ----------
create table if not exists public.centros (
  id          uuid primary key default gen_random_uuid(),
  nombre      text not null unique,
  ciudad      text,
  estado      text,
  codigo      text not null unique default upper(substr(encode(gen_random_bytes(6),'hex'),1,6)),
  activo      boolean not null default true,
  creado      timestamptz not null default now()
);

create table if not exists public.perfiles (
  user_id     uuid primary key references auth.users(id) on delete cascade,
  email       text,
  nombre      text,
  rol         text not null default 'centro' check (rol in ('admin','centro')),
  centro_id   uuid references public.centros(id) on delete set null,
  creado      timestamptz not null default now()
);

create table if not exists public.pacientes (
  id          uuid primary key default gen_random_uuid(),
  centro_id   uuid not null references public.centros(id) on delete cascade,
  creado_por  uuid references auth.users(id) on delete set null,
  fecha       date not null,
  folio       text,
  sexo        text not null check (sexo in ('M','H')),
  edad        integer not null check (edad between 10 and 100),
  imc         numeric(5,1) not null check (imc between 15 and 120),
  dm2         boolean not null default false,
  has         boolean not null default false,
  dislip      boolean not null default false,
  tipo        text not null check (tipo in ('primaria','revisional')),
  proc        text not null check (proc in ('manga','oagb','bypass','sadis','oatb','biparticion','manga_endo','allurion','balon','otra')),
  abordaje    text not null check (abordaje in ('laparoscopica','robotica','abierta','endoscopica')),
  estancia    integer not null check (estancia between 0 and 365),
  reop        boolean not null default false,
  muerte      boolean not null default false,
  notas       text,
  creado      timestamptz not null default now(),
  actualizado timestamptz not null default now()
);
create index if not exists pacientes_centro_fecha on public.pacientes (centro_id, fecha desc);

-- ---------- Funciones auxiliares (evitan recursión en las políticas) ----------
create or replace function public.es_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select rol = 'admin' from public.perfiles where user_id = auth.uid()), false);
$$;

create or replace function public.mi_centro() returns uuid
language sql stable security definer set search_path = public as $$
  select centro_id from public.perfiles where user_id = auth.uid();
$$;

-- Perfil automático al registrarse. El PRIMER usuario registrado es administrador.
create or replace function public.crear_perfil() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.perfiles (user_id, email, nombre, rol)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data->>'nombre', split_part(new.email,'@',1)),
    case when (select count(*) from public.perfiles) = 0 then 'admin' else 'centro' end
  )
  on conflict (user_id) do nothing;
  return new;
end $$;
drop trigger if exists crear_perfil on auth.users;
create trigger crear_perfil after insert on auth.users
  for each row execute function public.crear_perfil();

-- Un cirujano se une a su centro con el código que le dio el administrador.
create or replace function public.unirse_a_centro(p_codigo text) returns public.centros
language plpgsql security definer set search_path = public as $$
declare c public.centros;
begin
  select * into c from public.centros where codigo = upper(trim(p_codigo)) and activo;
  if c.id is null then raise exception 'Código no válido'; end if;
  update public.perfiles set centro_id = c.id where user_id = auth.uid();
  return c;
end $$;

create or replace function public.actualizar_nombre(p_nombre text) returns void
language sql security definer set search_path = public as $$
  update public.perfiles set nombre = trim(p_nombre) where user_id = auth.uid();
$$;

-- Administrador: reasignar rol o centro de un usuario.
create or replace function public.admin_actualizar_perfil(p_user uuid, p_rol text, p_centro uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.es_admin() then raise exception 'Solo administradores'; end if;
  update public.perfiles set rol = p_rol, centro_id = p_centro where user_id = p_user;
end $$;

-- Resumen nacional: cualquier usuario autenticado recibe las filas SIN centro, fecha ni folio
-- (no se puede saber de qué centro es cada una). Con eso la app calcula el resumen de México.
create or replace function public.pacientes_anonimos(p_anio integer default null)
returns table (sexo text, edad integer, imc numeric, dm2 boolean, has boolean, dislip boolean,
               tipo text, proc text, abordaje text, estancia integer, reop boolean, muerte boolean)
language sql stable security definer set search_path = public as $$
  select sexo, edad, imc, dm2, has, dislip, tipo, proc, abordaje, estancia, reop, muerte
  from public.pacientes
  where auth.uid() is not null and (p_anio is null or extract(year from fecha) = p_anio)
  order by random();
$$;

create or replace function public.tocar_actualizado() returns trigger language plpgsql as $$
begin new.actualizado = now(); return new; end $$;
drop trigger if exists pacientes_actualizado on public.pacientes;
create trigger pacientes_actualizado before update on public.pacientes
  for each row execute function public.tocar_actualizado();

-- ---------- Seguridad por fila (RLS) ----------
alter table public.centros   enable row level security;
alter table public.perfiles  enable row level security;
alter table public.pacientes enable row level security;

drop policy if exists centros_ver on public.centros;
create policy centros_ver on public.centros for select to authenticated
  using (public.es_admin() or id = public.mi_centro());
drop policy if exists centros_admin on public.centros;
create policy centros_admin on public.centros for all to authenticated
  using (public.es_admin()) with check (public.es_admin());

drop policy if exists perfiles_ver on public.perfiles;
create policy perfiles_ver on public.perfiles for select to authenticated
  using (public.es_admin() or user_id = auth.uid());

drop policy if exists pacientes_centro on public.pacientes;
create policy pacientes_centro on public.pacientes for all to authenticated
  using (public.es_admin() or centro_id = public.mi_centro())
  with check (public.es_admin() or centro_id = public.mi_centro());

grant usage on schema public to authenticated;
grant select, insert, update, delete on public.centros, public.perfiles, public.pacientes to authenticated;
grant execute on function public.es_admin(), public.mi_centro(), public.unirse_a_centro(text),
  public.actualizar_nombre(text), public.admin_actualizar_perfil(uuid, text, uuid),
  public.pacientes_anonimos(integer) to authenticated;

-- Gestión de centros por el coordinador: renombrar, activar/desactivar, fusionar, borrar.
create or replace function public.admin_fusionar_centros(p_origen uuid, p_destino uuid) returns integer
language plpgsql security definer set search_path = public as $$
declare n integer;
begin
  if not public.es_admin() then raise exception 'Solo administradores'; end if;
  if p_origen = p_destino then raise exception 'El origen y el destino son el mismo centro'; end if;
  if not exists (select 1 from public.centros where id = p_destino) then raise exception 'Centro destino no existe'; end if;
  update public.pacientes set centro_id = p_destino where centro_id = p_origen;
  get diagnostics n = row_count;
  update public.perfiles set centro_id = p_destino where centro_id = p_origen;
  delete from public.centros where id = p_origen;
  return n;
end $$;

create or replace function public.admin_borrar_centro(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.es_admin() then raise exception 'Solo administradores'; end if;
  if exists (select 1 from public.pacientes where centro_id = p_id) then raise exception 'El centro tiene pacientes; fusiónalo o desactívalo'; end if;
  update public.perfiles set centro_id = null where centro_id = p_id;
  delete from public.centros where id = p_id;
end $$;

grant execute on function public.admin_fusionar_centros(uuid, uuid), public.admin_borrar_centro(uuid) to authenticated;
-- =====================================================================
--  Migración v2: campos nuevos (origen, sector, GLP-1) + módulo de residentes
--  Es seguro correrla más de una vez.
-- =====================================================================

-- ---------- Registro principal: campos nuevos ----------
alter table public.pacientes add column if not exists origen text not null default 'nacional';
alter table public.pacientes add column if not exists sector text not null default 'privado';
alter table public.pacientes add column if not exists glp1   boolean not null default false;
alter table public.pacientes drop constraint if exists pacientes_origen_check;
alter table public.pacientes add constraint pacientes_origen_check check (origen in ('nacional','internacional'));
alter table public.pacientes drop constraint if exists pacientes_sector_check;
alter table public.pacientes add constraint pacientes_sector_check check (sector in ('publico','privado'));

-- El resumen nacional anónimo también devuelve los campos nuevos.
drop function if exists public.pacientes_anonimos(integer);
create or replace function public.pacientes_anonimos(p_anio integer default null)
returns table (sexo text, edad integer, imc numeric, dm2 boolean, has boolean, dislip boolean,
               tipo text, proc text, abordaje text, estancia integer, reop boolean, muerte boolean,
               origen text, sector text, glp1 boolean)
language sql stable security definer set search_path = public as $$
  select sexo, edad, imc, dm2, has, dislip, tipo, proc, abordaje, estancia, reop, muerte, origen, sector, glp1
  from public.pacientes
  where auth.uid() is not null and (p_anio is null or extract(year from fecha) = p_anio)
  order by random();
$$;
grant execute on function public.pacientes_anonimos(integer) to authenticated;

-- ---------- Residentes ----------
-- Un residente es un usuario con rol 'residente'. Lleva su propia bitácora (no cuenta en el reporte IFSO).
alter table public.perfiles drop constraint if exists perfiles_rol_check;
alter table public.perfiles add constraint perfiles_rol_check check (rol in ('admin','centro','residente'));
alter table public.perfiles add column if not exists sede text;      -- hospital / programa de residencia
alter table public.perfiles add column if not exists anio_res text;  -- año de residencia (R1, R2, fellow…)

-- Al registrarse desde la página de residentes, la app manda rol='residente' en los metadatos.
create or replace function public.crear_perfil() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.perfiles (user_id, email, nombre, rol, sede, anio_res)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data->>'nombre', split_part(new.email,'@',1)),
    case when (select count(*) from public.perfiles) = 0 then 'admin'
         when new.raw_user_meta_data->>'rol' = 'residente' then 'residente'
         else 'centro' end,
    new.raw_user_meta_data->>'sede',
    new.raw_user_meta_data->>'anio_res'
  )
  on conflict (user_id) do nothing;
  return new;
end $$;

create table if not exists public.residentes_casos (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references auth.users(id) on delete cascade,
  fecha         date not null,
  centro_nombre text not null,
  sector        text not null check (sector in ('publico','privado')),
  participacion text not null check (participacion in ('cirujano','primer_ayudante','segundo_ayudante')),
  folio         text,
  sexo          text not null check (sexo in ('M','H')),
  edad          integer not null check (edad between 10 and 100),
  imc           numeric(5,1) not null check (imc between 15 and 120),
  origen        text not null default 'nacional' check (origen in ('nacional','internacional')),
  glp1          boolean not null default false,
  dm2           boolean not null default false,
  has           boolean not null default false,
  dislip        boolean not null default false,
  tipo          text not null check (tipo in ('primaria','revisional')),
  proc          text not null check (proc in ('manga','oagb','bypass','sadis','oatb','biparticion','manga_endo','allurion','balon','otra')),
  abordaje      text not null check (abordaje in ('laparoscopica','robotica','abierta','endoscopica')),
  estancia      integer not null check (estancia between 0 and 365),
  reop          boolean not null default false,
  muerte        boolean not null default false,
  notas         text,
  creado        timestamptz not null default now(),
  actualizado   timestamptz not null default now()
);
create index if not exists residentes_casos_user_fecha on public.residentes_casos (user_id, fecha desc);
drop trigger if exists residentes_casos_actualizado on public.residentes_casos;
create trigger residentes_casos_actualizado before update on public.residentes_casos
  for each row execute function public.tocar_actualizado();

alter table public.residentes_casos enable row level security;
drop policy if exists residentes_propios on public.residentes_casos;
create policy residentes_propios on public.residentes_casos for all to authenticated
  using (user_id = auth.uid() or public.es_admin())
  with check (user_id = auth.uid());
grant select, insert, update, delete on public.residentes_casos to authenticated;

-- El residente puede actualizar su sede/año.
create or replace function public.actualizar_residente(p_sede text, p_anio text) returns void
language sql security definer set search_path = public as $$
  update public.perfiles set sede = nullif(trim(p_sede),''), anio_res = nullif(trim(p_anio),'') where user_id = auth.uid();
$$;
grant execute on function public.actualizar_residente(text, text) to authenticated;

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
