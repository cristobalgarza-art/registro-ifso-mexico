-- ===== migracion_v8_borrar_usuario =====
-- v8: al borrar una cuenta, su invitación vuelve a "Pendiente" y sin centro,
-- para que ese correo pueda registrarse de nuevo y crear su propio centro.
create or replace function public.admin_borrar_usuario(p_user uuid) returns void
language plpgsql security definer set search_path = public, auth as $$
declare v_email text;
begin
  if not public.es_admin() then raise exception 'Solo administradores'; end if;
  if p_user = auth.uid() then raise exception 'No puedes borrar tu propia cuenta'; end if;
  select email into v_email from auth.users where id = p_user;
  delete from auth.users where id = p_user;
  if v_email is not null then
    update public.invitaciones set usado = null, centro_id = null where lower(email) = lower(v_email);
  end if;
end $$;
grant execute on function public.admin_borrar_usuario(uuid) to authenticated;
