-- v6: registro de aceptación del aviso de privacidad y términos de uso.
alter table public.perfiles add column if not exists terminos_aceptado timestamptz;
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
  insert into public.perfiles (user_id, email, nombre, rol, centro_id, sede, anio_res, terminos_aceptado)
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
    new.raw_user_meta_data->>'anio_res',
    nullif(new.raw_user_meta_data->>'acepto_terminos','')::timestamptz
  )
  on conflict (user_id) do nothing;
  if inv.email is not null then update public.invitaciones set usado = now() where email = inv.email; end if;
  return new;
end $$;
