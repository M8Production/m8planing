-- ============================================================
--  M8 Stone Solutions — Esquema Supabase (completo)
--  Cole TUDO em: Supabase -> SQL Editor -> New query -> Run
-- ============================================================

-- ------------------------------------------------------------
-- 1) CONTAS / LOGINS  (fonte de verdade dos utilizadores)
-- ------------------------------------------------------------
create table if not exists public.contas (
  id         bigint generated always as identity primary key,
  nome       text not null,
  email      text not null unique,
  pass       text not null,                    -- (interno; ver nota de seguranca no fim)
  tipo       text not null default 'desenho',  -- admin | desenho | tecnico
  cor        text default '#c9a84c',
  projetos   jsonb not null default '[]'::jsonb,
  created_at timestamptz default now()
);

-- Contas iniciais (pode alterar/apagar depois na app)
insert into public.contas (nome, email, pass, tipo, cor, projetos) values
  ('Administrador', 'admin@m8stone.pt',   'admin123', 'admin',   '#c9a84c', '[]'::jsonb),
  ('Ana Desenho',   'desenho@m8stone.pt', 'd123',     'desenho', '#2563eb', '["PRJ-2024-0587","PRJ-2024-0584"]'::jsonb),
  ('Joao Tecnico',  'tecnico@m8stone.pt', 't123',     'tecnico', '#059669', '["PRJ-2024-0587","PRJ-2024-0577"]'::jsonb)
on conflict (email) do nothing;

-- RLS ligado: NINGUEM le a tabela contas diretamente pela chave anon
-- (assim a coluna "pass" nunca sai para o browser). Todo o acesso e feito
-- pelas funcoes abaixo (SECURITY DEFINER) e pela view sem password.
alter table public.contas enable row level security;

-- View publica (sem a coluna pass) para listar contas no painel de admin
create or replace view public.contas_publicas as
  select id, nome, email, tipo, cor, projetos from public.contas;

grant select on public.contas_publicas to anon;

-- ------------------------------------------------------------
-- 2) FUNCOES DE AUTENTICACAO / GESTAO DE CONTAS
-- ------------------------------------------------------------
-- Valida email+password e devolve a conta (sem a password)
create or replace function public.verificar_login(p_email text, p_pass text)
returns table (id bigint, nome text, email text, tipo text, cor text, projetos jsonb)
language sql security definer set search_path = public as $$
  select id, nome, email, tipo, cor, projetos
  from public.contas
  where lower(email) = lower(p_email) and pass = p_pass
  limit 1;
$$;

-- Criar conta
create or replace function public.criar_conta(
  p_nome text, p_email text, p_pass text, p_tipo text, p_cor text, p_projetos jsonb)
returns bigint language plpgsql security definer set search_path = public as $$
declare v_id bigint;
begin
  insert into public.contas (nome, email, pass, tipo, cor, projetos)
  values (p_nome, lower(p_email), p_pass, coalesce(p_tipo,'desenho'),
          coalesce(p_cor,'#c9a84c'), coalesce(p_projetos,'[]'::jsonb))
  returning id into v_id;
  return v_id;
end $$;

-- Atualizar conta (password so muda se p_pass nao for vazio)
create or replace function public.atualizar_conta(
  p_id bigint, p_nome text, p_email text, p_tipo text, p_projetos jsonb, p_pass text)
returns void language plpgsql security definer set search_path = public as $$
begin
  update public.contas set
    nome     = p_nome,
    email    = lower(p_email),
    tipo     = p_tipo,
    projetos = coalesce(p_projetos, '[]'::jsonb),
    pass     = case when p_pass is null or p_pass = '' then pass else p_pass end
  where id = p_id;
end $$;

-- Remover conta (nunca remove um admin)
create or replace function public.remover_conta(p_id bigint)
returns void language plpgsql security definer set search_path = public as $$
begin
  delete from public.contas where id = p_id and tipo <> 'admin';
end $$;

grant execute on function public.verificar_login(text, text)                       to anon;
grant execute on function public.criar_conta(text, text, text, text, text, jsonb)  to anon;
grant execute on function public.atualizar_conta(bigint, text, text, text, jsonb, text) to anon;
grant execute on function public.remover_conta(bigint)                             to anon;

-- ------------------------------------------------------------
-- 3) ESTADO DA APLICACAO  (clientes, projetos, fracoes, agendamentos)
--    Guardado como um unico registo JSON com id = 'main'.
-- ------------------------------------------------------------
create table if not exists public.app_state (
  id         text primary key,
  data       jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

insert into public.app_state (id, data)
values ('main', '{}'::jsonb)
on conflict (id) do nothing;

alter table public.app_state enable row level security;

drop policy if exists "app_state anon rw" on public.app_state;
create policy "app_state anon rw"
  on public.app_state for all to anon
  using (true) with check (true);

-- Historico de snapshots do app_state (rede de seguranca contra perda de dados:
-- antes de cada gravacao a app guarda aqui a versao anterior, para poder recuperar
-- caso uma gravacao acidental sobreponha dados bons com dados vazios/antigos).
create table if not exists public.app_state_history (
  id         bigint generated always as identity primary key,
  data       jsonb not null,
  created_at timestamptz not null default now()
);
alter table public.app_state_history enable row level security;
drop policy if exists "app_state_history anon rw" on public.app_state_history;
create policy "app_state_history anon rw"
  on public.app_state_history for all to anon
  using (true) with check (true);

-- ------------------------------------------------------------
-- 4) EQUIPAS  (equipas de desenho / tecnicos de montagem)
--    Cada equipa tem um nome, um tipo e a lista de elementos.
-- ------------------------------------------------------------
create table if not exists public.equipas (
  id         bigint generated always as identity primary key,
  nome       text not null,
  tipo       text not null default 'tecnico',   -- desenho | tecnico
  membros    jsonb not null default '[]'::jsonb, -- ["Nome 1","Nome 2", ...]
  conta_id   bigint references public.contas(id) on delete set null, -- conta de login associada
  created_at timestamptz not null default now()
);

alter table public.equipas enable row level security;

-- (migracao) garante a coluna conta_id em tabelas ja existentes
alter table public.equipas add column if not exists conta_id bigint references public.contas(id) on delete set null;

drop policy if exists "equipas anon rw" on public.equipas;
create policy "equipas anon rw"
  on public.equipas for all to anon
  using (true) with check (true);

-- ------------------------------------------------------------
-- 5) PRODUCAO (Controlo de Horas de Maquina)
--    Guardado como um unico registo JSON com id = 'producao'.
--    { G: grelha por ano/mes/maquina/dia, W: lista de espera }
-- ------------------------------------------------------------
create table if not exists public.producao_state (
  id         text primary key,
  data       jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

insert into public.producao_state (id, data)
values ('producao', '{}'::jsonb)
on conflict (id) do nothing;

alter table public.producao_state enable row level security;

drop policy if exists "producao_state anon rw" on public.producao_state;
create policy "producao_state anon rw"
  on public.producao_state for all to anon
  using (true) with check (true);

-- Historico de snapshots do producao_state (mesma rede de seguranca que o app_state).
create table if not exists public.producao_state_history (
  id         bigint generated always as identity primary key,
  data       jsonb not null,
  created_at timestamptz not null default now()
);
alter table public.producao_state_history enable row level security;
drop policy if exists "producao_state_history anon rw" on public.producao_state_history;
create policy "producao_state_history anon rw"
  on public.producao_state_history for all to anon
  using (true) with check (true);

-- ------------------------------------------------------------
-- 6) ENCOMENDAS  (ligadas a um Projeto e, opcionalmente, ao
--    agendamento de Retificacao de Medidas que as originou e ao
--    agendamento de Aplicacao que as usa). O numero corresponde
--    ao mesmo numero de encomenda usado na tab Producao.
-- ------------------------------------------------------------
create table if not exists public.encomendas (
  id                        bigint generated always as identity primary key,
  proj_id                   text not null,
  numero                    text not null,
  origem_agendamento_id     bigint,
  origem_ticket_id          bigint,
  aplicacao_agendamento_id  bigint,
  corte                     date,
  zonas                     jsonb not null default '[]'::jsonb,  -- [{nome,data}, ...]
  criado_em                 timestamptz not null default now()
);

-- (migracao) origem por ticket, para instalacoes criadas antes desta coluna existir
alter table public.encomendas add column if not exists origem_ticket_id bigint;

alter table public.encomendas enable row level security;

drop policy if exists "encomendas anon rw" on public.encomendas;
create policy "encomendas anon rw"
  on public.encomendas for all to anon
  using (true) with check (true);

-- ------------------------------------------------------------
-- 7) TICKETS  (podem ligar-se a um Agendamento, a uma Encomenda,
--    ou andar soltos). Numero sequencial "001_2026", reiniciado
--    todos os anos (ano/seq com restricao de unicidade).
-- ------------------------------------------------------------
create table if not exists public.tickets (
  id           bigint generated always as identity primary key,
  numero       text not null,
  ano          int not null,
  seq          int not null,
  titulo       text not null,
  descricao    text,
  anexos       jsonb not null default '[]'::jsonb,  -- [{nome, dataUrl}, ...]
  rel_tipo     text,                                 -- 'agendamento' | 'encomenda' | null
  rel_id       text,
  proj_id      text,
  estado       text not null default 'aberto',        -- 'aberto' | 'fechado'
  origina_encomenda boolean not null default false,   -- true = ao fechar, ticket pode dar origem a uma encomenda
  criado_por   text,
  criado_em    timestamptz not null default now(),
  fechado_por  text,
  fechado_em   timestamptz,
  unique (ano, seq)
);

-- (migracao) flag "origina encomenda", para instalacoes criadas antes desta coluna existir
alter table public.tickets add column if not exists origina_encomenda boolean not null default false;

alter table public.tickets enable row level security;

drop policy if exists "tickets anon rw" on public.tickets;
create policy "tickets anon rw"
  on public.tickets for all to anon
  using (true) with check (true);

-- ============================================================
--  NOTA DE SEGURANCA
--  As passwords ficam guardadas em texto simples na coluna "pass"
--  (herdado do prototipo). A tabela tem RLS e nunca e lida pela
--  chave anon — apenas as funcoes acima lhe acedem. Ainda assim,
--  para producao recomenda-se migrar o login para Supabase Auth
--  (auth.users) e guardar apenas o perfil/role na tabela contas.
-- ============================================================
