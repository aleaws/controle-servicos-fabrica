-- SERVIÇOS DA FÁBRICA • sincronização v2 • 12/10/2026
-- Execute uma vez no SQL Editor do seu projeto Supabase.
-- Somente cria/atualiza objetos fabrica_aw_*_v2. Não altera tabelas do V25.
begin;

create table if not exists public.fabrica_aw_estado_v2 (
  usuario_id uuid not null references auth.users(id),
  sala text not null,
  revisao bigint not null default 0,
  dados jsonb not null default '{"servicos":[],"eventos":[],"cadastros":[],"seq":1,"adminHash":""}'::jsonb,
  atualizado_em timestamptz not null default now(),
  primary key (usuario_id, sala)
);
create table if not exists public.fabrica_aw_mutacoes_v2 (
  usuario_id uuid not null,
  sala text not null,
  mutacao uuid not null,
  revisao bigint not null,
  criado_em timestamptz not null default now(),
  primary key (usuario_id, sala, mutacao),
  foreign key (usuario_id, sala) references public.fabrica_aw_estado_v2(usuario_id, sala)
);
alter table public.fabrica_aw_estado_v2 enable row level security;
alter table public.fabrica_aw_mutacoes_v2 enable row level security;
-- A API acessa os dados somente pelas funções abaixo; a chave pública não dá acesso.
revoke all on public.fabrica_aw_estado_v2 from public, anon, authenticated;
revoke all on public.fabrica_aw_mutacoes_v2 from public, anon, authenticated;

create or replace function public.fabrica_aw_sync_v2(
  p_sala text,
  p_revisao bigint default null,
  p_dados jsonb default null,
  p_mutacao uuid default null
) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  u uuid := auth.uid();
  linha public.fabrica_aw_estado_v2%rowtype;
  confirmado bigint;
begin
  if u is null then raise exception 'Entre na conta da fábrica.' using errcode = '42501'; end if;
  if p_sala is null or length(btrim(p_sala)) < 3 or length(p_sala) > 120 then
    raise exception 'Nome da sala inválido.';
  end if;
  if p_dados is null then
    select * into linha from public.fabrica_aw_estado_v2 where usuario_id=u and sala=p_sala;
    return jsonb_build_object('aplicada',null,'revisao',coalesce(linha.revisao,0),
      'dados',coalesce(linha.dados,'{"servicos":[],"eventos":[],"cadastros":[],"seq":1,"adminHash":""}'::jsonb));
  end if;
  if p_mutacao is null or p_revisao is null or p_revisao < 0 then
    raise exception 'Identificação da gravação inválida.';
  end if;
  if jsonb_typeof(p_dados) is distinct from 'object'
     or jsonb_typeof(p_dados->'servicos') is distinct from 'array'
     or jsonb_typeof(p_dados->'eventos') is distinct from 'array'
     or jsonb_typeof(p_dados->'cadastros') is distinct from 'array'
     or p_dados ? '_syncV2' then raise exception 'Formato dos registros inválido.'; end if;
  if octet_length(p_dados::text)>20000000 then raise exception 'Volume de registros excede o limite desta versão.'; end if;

  insert into public.fabrica_aw_estado_v2(usuario_id,sala) values(u,p_sala) on conflict do nothing;
  select * into linha from public.fabrica_aw_estado_v2 where usuario_id=u and sala=p_sala for update;
  select revisao into confirmado from public.fabrica_aw_mutacoes_v2
    where usuario_id=u and sala=p_sala and mutacao=p_mutacao;
  if confirmado is not null then
    return jsonb_build_object('aplicada',true,'duplicada',true,'revisao',linha.revisao,'dados',linha.dados);
  end if;
  if linha.revisao <> p_revisao then
    return jsonb_build_object('aplicada',false,'revisao',linha.revisao,'dados',linha.dados);
  end if;
  if exists(select 1 from jsonb_array_elements(p_dados->'servicos') s where coalesce(s->>'id','')='' or coalesce(s->>'codigo','')='')
     or exists(select 1 from jsonb_array_elements(p_dados->'eventos') e where coalesce(e->>'id','')='') then
    raise exception 'Há registros sem identificação. Revise o backup importado.';
  end if;
  if exists(select 1 from jsonb_array_elements(p_dados->'servicos') s group by s->>'id' having count(*)>1)
     or exists(select 1 from jsonb_array_elements(p_dados->'servicos') s group by upper(s->>'codigo') having count(*)>1)
     or exists(select 1 from jsonb_array_elements(p_dados->'eventos') e group by e->>'id' having count(*)>1) then
    raise exception 'Há códigos ou identificações repetidos. Revise os registros.';
  end if;
  if (select count(*) from jsonb_array_elements(p_dados->'servicos') s where s->>'estado'='Andamento')>1 then
    raise exception 'Só pode existir um serviço em andamento nesta sala.';
  end if;
  update public.fabrica_aw_estado_v2 set dados=p_dados,revisao=revisao+1,atualizado_em=now()
    where usuario_id=u and sala=p_sala returning * into linha;
  insert into public.fabrica_aw_mutacoes_v2(usuario_id,sala,mutacao,revisao) values(u,p_sala,p_mutacao,linha.revisao);
  return jsonb_build_object('aplicada',true,'revisao',linha.revisao,'dados',linha.dados);
end;
$$;
revoke all on function public.fabrica_aw_sync_v2(text,bigint,jsonb,uuid) from public, anon;
grant execute on function public.fabrica_aw_sync_v2(text,bigint,jsonb,uuid) to authenticated;
notify pgrst, 'reload schema';
commit;
