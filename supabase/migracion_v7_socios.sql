-- ===== migracion_v7_socios =====
-- v7: un socio = un centro. El coordinador solo carga la lista de correos de los socios;
-- al registrarse con un correo invitado, el socio crea su propio centro automáticamente
-- (nombre = su nombre, con ciudad, estado y hospitales donde opera).

alter table public.centros add column if not exists hospitales text;

-- Crea un centro con nombre único. Si el nombre ya existe, agrega la ciudad o un número.
create or replace function public._crear_centro_unico(p_nombre text, p_ciudad text, p_estado text, p_hospitales text) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_base text; v_nombre text; v_n int := 2; v_id uuid;
begin
  v_base := nullif(trim(p_nombre), '');
  if v_base is null then raise exception 'Falta el nombre del centro.'; end if;
  v_nombre := v_base;
  if nullif(trim(p_ciudad), '') is not null and exists (select 1 from public.centros c where lower(c.nombre) = lower(v_nombre)) then
    v_nombre := v_base || ' (' || trim(p_ciudad) || ')';
  end if;
  while exists (select 1 from public.centros c where lower(c.nombre) = lower(v_nombre)) loop
    v_nombre := v_base || ' (' || v_n || ')'; v_n := v_n + 1;
  end loop;
  insert into public.centros (nombre, ciudad, estado, hospitales)
  values (v_nombre, nullif(trim(p_ciudad), ''), nullif(trim(p_estado), ''), nullif(trim(p_hospitales), ''))
  returning id into v_id;
  return v_id;
end $$;
revoke all on function public._crear_centro_unico(text, text, text, text) from public;

-- Al crear la cuenta: si el correo está invitado como cirujano (o coordinador) y la invitación
-- no trae centro, se crea el centro del socio con los datos del formulario de alta.
create or replace function public.crear_perfil() returns trigger
language plpgsql security definer set search_path = public as $$
declare inv public.invitaciones; cerrado boolean; primero boolean; v_rol text; v_centro uuid; v_nombre text;
begin
  primero := (select count(*) from public.perfiles) = 0;
  cerrado := coalesce((select valor from public.ajustes where clave='registro_cerrado'),'true') = 'true';
  select * into inv from public.invitaciones where lower(email) = lower(new.email);
  if cerrado and not primero and inv.email is null then
    raise exception 'Este correo no tiene invitación. Pide al coordinador del registro que te invite.';
  end if;
  v_nombre := coalesce(nullif(trim(new.raw_user_meta_data->>'nombre'), ''), split_part(new.email,'@',1));
  v_rol := case when primero then 'admin'
                when inv.email is not null then inv.rol
                when new.raw_user_meta_data->>'rol' = 'residente' then 'residente'
                else 'centro' end;
  v_centro := inv.centro_id;
  if v_rol <> 'residente' and v_centro is null then
    v_centro := public._crear_centro_unico(v_nombre, new.raw_user_meta_data->>'ciudad', new.raw_user_meta_data->>'estado', new.raw_user_meta_data->>'hospitales');
  end if;
  insert into public.perfiles (user_id, email, nombre, rol, centro_id, sede, anio_res, terminos_aceptado)
  values (
    new.id, new.email, v_nombre, v_rol, v_centro,
    new.raw_user_meta_data->>'sede',
    new.raw_user_meta_data->>'anio_res',
    nullif(new.raw_user_meta_data->>'acepto_terminos','')::timestamptz
  )
  on conflict (user_id) do nothing;
  if inv.email is not null then update public.invitaciones set usado = now() where email = inv.email; end if;
  return new;
end $$;

-- Cuenta ya existente sin centro (por ejemplo, creada antes de v7): el propio usuario crea su centro.
create or replace function public.crear_mi_centro(p_ciudad text, p_estado text, p_hospitales text) returns uuid
language plpgsql security definer set search_path = public as $$
declare p public.perfiles; v_id uuid;
begin
  select * into p from public.perfiles where user_id = auth.uid();
  if p.user_id is null then raise exception 'Sin perfil.'; end if;
  if p.centro_id is not null then return p.centro_id; end if;
  if p.rol = 'residente' then raise exception 'Los residentes no tienen centro.'; end if;
  v_id := public._crear_centro_unico(coalesce(p.nombre, split_part(p.email,'@',1)), p_ciudad, p_estado, p_hospitales);
  update public.perfiles set centro_id = v_id where user_id = p.user_id;
  return v_id;
end $$;
grant execute on function public.crear_mi_centro(text, text, text) to authenticated;
