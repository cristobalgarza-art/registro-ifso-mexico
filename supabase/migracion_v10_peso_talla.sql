-- ===== migracion_v10_peso_talla =====
-- v10: peso (kg) y talla (cm) opcionales; el IMC se sigue guardando como siempre
-- (la app lo calcula sola cuando hay peso y talla).
alter table public.pacientes
  add column if not exists peso  numeric(5,1) check (peso is null or peso between 20 and 400),
  add column if not exists talla numeric(5,1) check (talla is null or talla between 100 and 250);
alter table public.residentes_casos
  add column if not exists peso  numeric(5,1) check (peso is null or peso between 20 and 400),
  add column if not exists talla numeric(5,1) check (talla is null or talla between 100 and 250);
