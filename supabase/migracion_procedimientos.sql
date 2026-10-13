-- Migración: más procedimientos (SADI-S, OATB/bipartición intestinal, manga endoscópica, balón Allurion, balón endoscópico).
-- En el formato IFSO todos estos se suman en la columna "otra"; en la app se desglosan.
alter table public.pacientes drop constraint if exists pacientes_proc_check;
alter table public.pacientes add constraint pacientes_proc_check
  check (proc in ('manga','oagb','bypass','sadis','oatb','biparticion','manga_endo','allurion','balon','otra'));
