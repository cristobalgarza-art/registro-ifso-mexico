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
