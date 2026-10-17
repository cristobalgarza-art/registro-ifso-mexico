-- ===== migracion_v12_tore =====
-- v12: nuevo procedimiento "tore" (TORe, reducción endoscópica de la anastomosis gastroyeyunal).
alter table public.pacientes drop constraint if exists pacientes_proc_check;
alter table public.pacientes add constraint pacientes_proc_check
  check (proc in ('manga','oagb','bypass','sadis','oatb','biparticion','manga_endo','tore','allurion','balon','otra'));
alter table public.residentes_casos drop constraint if exists residentes_casos_proc_check;
alter table public.residentes_casos add constraint residentes_casos_proc_check
  check (proc in ('manga','oagb','bypass','sadis','oatb','biparticion','manga_endo','tore','allurion','balon','otra'));
