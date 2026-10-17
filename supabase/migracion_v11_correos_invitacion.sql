-- ===== migracion_v11_correos_invitacion =====
-- v11: seguimiento de los correos de invitación automáticos (los manda el workflow
-- "Correos de invitación" del repo privado respaldos, cada hora, vía Resend).
alter table public.invitaciones
  add column if not exists enviado          timestamptz,            -- primera invitación enviada
  add column if not exists ultimo_correo    timestamptz,            -- último correo (invitación o recordatorio)
  add column if not exists recordatorios    smallint not null default 0,
  add column if not exists reenviar         boolean not null default false,  -- el coordinador pidió reenviar
  add column if not exists correos_pausados boolean not null default false;  -- no mandarle más correos
