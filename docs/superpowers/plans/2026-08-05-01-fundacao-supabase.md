# Fundação Supabase (Plano 1/5) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Colocar de pé a fundação de dados do redesenho de Diagramas/Esquemas: projeto Supabase local versionado, schema das 4 tabelas novas com RLS, testes automatizados de isolamento entre usuários, e autenticação básica funcionando na `tutor-fiscal.html`.

**Architecture:** Supabase (Postgres + `pgvector` + Auth) rodando localmente via Supabase CLI, migrações versionadas em git, RLS por `user_id` em todas as tabelas desde a primeira migração. Cliente `@supabase/supabase-js` v2 carregado via CDN (sem bundler, mesmo padrão do resto do app). Esta é a base para os planos 2-5 (ingestão de PDF, pipeline de IA, motor SVG, UI do card).

**Tech Stack:** Supabase CLI, Postgres 15+ com extensão `vector` (pgvector), pgTAP (testes de RLS), `@supabase/supabase-js@2` via CDN, JS vanilla (sem build step).

## Global Constraints

- RLS por `user_id` obrigatório em toda tabela nova, desde a primeira migração — não existe tabela sem RLS neste projeto (spec, Seção 3).
- Progresso/config do aluno (`S`, hoje em `localStorage`) **não migra** para o Supabase — fica local (spec, Seção 1/11).
- Chaves de API (Supabase anon key incluída) ficam salvas só no `localStorage` do navegador do usuário, nunca commitadas em arquivo (convenção existente do projeto, `CLAUDE.md`).
- `tutor-fiscal.html` é a fonte da verdade; toda edição feita nela precisa ser replicada manualmente em `Programa/tutor-fiscal-windows/index.html` — são dois arquivos, sem build step (`CLAUDE.md`).
- Sem framework/bundler: qualquer biblioteca nova (aqui, `@supabase/supabase-js`) entra via `<script>` de CDN, nunca via `npm install` no app em si.
- **Decisão de implementação tomada neste plano (não estava no spec):** embeddings gerados via **Voyage AI, modelo `voyage-3-lite`, 512 dimensões** — é o provedor de embeddings recomendado pela Anthropic, mantendo o app dentro do mesmo ecossistema das outras 6 chamadas de IA que já existem. Isso introduz uma nova chave de API (`VOYAGE_API_KEY`), armazenada com a mesma convenção acima. A geração de embeddings em si é implementada no Plano 2 (ingestão), mas a coluna `vector(512)` já é criada aqui porque faz parte do schema.

---

### Task 1: Inicializar controle de versão e projeto Supabase CLI local

**Files:**
- Create: `.git/` (via `git init` na raiz do projeto)
- Create: `.gitignore`
- Create: `supabase/config.toml` (via `supabase init`)

**Interfaces:**
- Consumes: nada (primeira task)
- Produces: repositório git na raiz do projeto; stack Supabase local iniciável via `npx supabase start`; pasta `supabase/migrations/` onde as próximas tasks escrevem migrações.

- [ ] **Step 1: Verificar se já existe um repositório git na pasta do projeto**

Run: `git -C "C:\Users\henri\Documents\Claude Code\Aplicativo_Estudo_Neurodivergente" rev-parse --is-inside-work-tree`
Expected: falha com "not a git repository" (confirmado numa sessão anterior) — se já existir, pule para o Step 3.

- [ ] **Step 2: Inicializar o repositório**

Run: `git -C "C:\Users\henri\Documents\Claude Code\Aplicativo_Estudo_Neurodivergente" init`

- [ ] **Step 3: Criar `.gitignore`**

```gitignore
# Supabase local
supabase/.branches
supabase/.temp

# Companheiro visual de brainstorming (mockups temporários)
.superpowers/

# Chaves/segredos nunca versionados (embora hoje só existam no navegador)
.env
.env.local
```

- [ ] **Step 4: Inicializar o projeto Supabase (CLI via npx, sem instalar globalmente)**

Run: `npx supabase@latest init` (na raiz do projeto)
Expected: cria `supabase/config.toml` e `supabase/migrations/` (vazia), e uma pasta `supabase/.gitignore` própria do CLI.

- [ ] **Step 5: Subir a stack local e confirmar que funciona**

Run: `npx supabase start`
Expected: baixa as imagens Docker necessárias (Postgres, GoTrue/Auth, etc.) e imprime, ao final, `API URL`, `anon key` e `service_role key` locais. Guarde a `API URL` e a `anon key` — são usadas no Task 3.

- [ ] **Step 6: Commit**

```bash
git add .gitignore supabase/config.toml supabase/.gitignore
git commit -m "chore: inicializar git e projeto Supabase local"
```

---

### Task 2: Schema das 4 tabelas + RLS (migração) com teste de isolamento entre usuários

**Files:**
- Test: `supabase/tests/database/001_rls_isolation.test.sql`
- Create: `supabase/migrations/<timestamp>_diagramas_esquemas_schema.sql`

**Interfaces:**
- Consumes: stack Supabase local rodando (Task 1)
- Produces: tabelas `public.knowledge_chunks`, `public.fichas`, `public.problems`, `public.review_log`, todas com RLS habilitado e política "dono only" (`auth.uid() = user_id`). Colunas exatas documentadas abaixo — planos 2-5 dependem destes nomes.

- [ ] **Step 1: Escrever o teste pgTAP (vai falhar — as tabelas ainda não existem)**

```sql
-- supabase/tests/database/001_rls_isolation.test.sql
begin;
select plan(10);

-- dois usuários de teste
insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'user-a@test.local'),
  ('22222222-2222-2222-2222-222222222222', 'user-b@test.local');

-- age como usuário A
select set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}', true);
set local role authenticated;

insert into public.fichas (user_id, disciplina_id, topico, conceito_central, por_que_cai, diagrama_schema, problema_resolvido)
values ('11111111-1111-1111-1111-111111111111', 'contabilidade', 'patrimonio-equacao', 'texto', 'texto', '{}'::jsonb, '{}'::jsonb);

select is((select count(*) from public.fichas)::int, 1, 'usuario A ve a propria ficha');

insert into public.knowledge_chunks (user_id, disciplina_id, pdf_nome, texto, embedding)
values ('11111111-1111-1111-1111-111111111111', 'contabilidade', '00.pdf', 'trecho de teste', array_fill(0.1, array[512])::vector);

select is((select count(*) from public.knowledge_chunks)::int, 1, 'usuario A ve o proprio chunk');

insert into public.problems (user_id, ficha_id, enunciado, gabarito, correcao_detalhada)
select '11111111-1111-1111-1111-111111111111', id, 'enunciado teste', 'gabarito teste', 'correcao teste'
from public.fichas limit 1;

select is((select count(*) from public.problems)::int, 1, 'usuario A ve o proprio problema');

insert into public.review_log (user_id, ficha_id, tipo_conteudo, passou)
select '11111111-1111-1111-1111-111111111111', id, 'ficha', true
from public.fichas limit 1;

select is((select count(*) from public.review_log)::int, 1, 'usuario A ve o proprio review_log');

-- troca para usuário B: nao deve enxergar nada do usuário A
select set_config('request.jwt.claims', '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}', true);

select is((select count(*) from public.fichas)::int, 0, 'usuario B nao ve ficha do usuario A');
select is((select count(*) from public.knowledge_chunks)::int, 0, 'usuario B nao ve chunk do usuario A');
select is((select count(*) from public.problems)::int, 0, 'usuario B nao ve problema do usuario A');
select is((select count(*) from public.review_log)::int, 0, 'usuario B nao ve review_log do usuario A');

-- usuário B nao consegue inserir ficha em nome do usuário A (with check bloqueia)
select throws_ok(
  $$insert into public.fichas (user_id, disciplina_id, topico, conceito_central, por_que_cai, diagrama_schema, problema_resolvido)
    values ('11111111-1111-1111-1111-111111111111', 'x', 'y', 'z', 'w', '{}'::jsonb, '{}'::jsonb)$$,
  '42501',
  null,
  'usuario B nao consegue inserir ficha em nome do usuario A'
);

-- unique constraint (user_id, disciplina_id, topico) em fichas
select set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}', true);
select throws_ok(
  $$insert into public.fichas (user_id, disciplina_id, topico, conceito_central, por_que_cai, diagrama_schema, problema_resolvido)
    values ('11111111-1111-1111-1111-111111111111', 'contabilidade', 'patrimonio-equacao', 'dup', 'dup', '{}'::jsonb, '{}'::jsonb)$$,
  '23505',
  null,
  'nao permite duas fichas com mesmo disciplina_id+topico pro mesmo usuario'
);

select * from finish();
rollback;
```

- [ ] **Step 2: Rodar o teste para confirmar que falha**

Run: `npx supabase test db`
Expected: FAIL — `relation "public.fichas" does not exist` (ou erro equivalente para as outras tabelas).

- [ ] **Step 3: Escrever a migração**

```sql
-- supabase/migrations/<timestamp>_diagramas_esquemas_schema.sql
create extension if not exists vector;
create extension if not exists pgtap;

create table public.knowledge_chunks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  disciplina_id text not null,
  pdf_nome text not null,
  texto text not null,
  embedding vector(512) not null,
  created_at timestamptz not null default now()
);

create index knowledge_chunks_embedding_idx on public.knowledge_chunks
  using hnsw (embedding vector_cosine_ops);

create index knowledge_chunks_user_disciplina_idx on public.knowledge_chunks (user_id, disciplina_id);

create table public.fichas (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  disciplina_id text not null,
  topico text not null,
  conceito_central text not null,
  por_que_cai text not null,
  diagrama_schema jsonb not null,
  problema_resolvido jsonb not null,
  source_chunk_ids uuid[] not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, disciplina_id, topico)
);

create table public.problems (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  ficha_id uuid not null references public.fichas(id) on delete cascade,
  enunciado text not null,
  gabarito text not null,
  correcao_detalhada text not null,
  origem_chunk_id uuid references public.knowledge_chunks(id) on delete set null,
  created_at timestamptz not null default now()
);

create index problems_ficha_idx on public.problems (ficha_id);

create table public.review_log (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  ficha_id uuid references public.fichas(id) on delete cascade,
  problem_id uuid references public.problems(id) on delete cascade,
  tipo_conteudo text not null check (tipo_conteudo in ('ficha', 'problema_independente')),
  passou boolean not null,
  motivo_falha text,
  tentativa_regeneracao boolean not null default false,
  created_at timestamptz not null default now()
);

alter table public.knowledge_chunks enable row level security;
alter table public.fichas enable row level security;
alter table public.problems enable row level security;
alter table public.review_log enable row level security;

create policy "knowledge_chunks_owner_all" on public.knowledge_chunks
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "fichas_owner_all" on public.fichas
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "problems_owner_all" on public.problems
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "review_log_owner_all" on public.review_log
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
```

- [ ] **Step 4: Rodar o teste de novo e confirmar que passa**

Run: `npx supabase test db`
Expected: PASS — `10/10` asserções.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations supabase/tests
git commit -m "feat: schema de diagramas/esquemas (knowledge_chunks, fichas, problems, review_log) com RLS"
```

---

### Task 3: Cliente Supabase + autenticação básica na `tutor-fiscal.html`

**Files:**
- Modify: `Programa/tutor-fiscal.html` (nova seção `/* ═══ SUPABASE ═══ */`, inserida antes de `/* ═══ Sincronização automática ═══ */`, linha ~2777 no mapa atual)

**Interfaces:**
- Consumes: `API URL` e `anon key` impressas pelo `npx supabase start` (Task 1, Step 5)
- Produces: `window.supabaseClient` (instância do cliente, ou `null` se não configurado), `async function signUp(email, senha)`, `async function signIn(email, senha)`, `async function signOut()`, `async function getSession()` — usadas pelos Planos 2-5 para toda leitura/escrita nas 4 tabelas.

- [ ] **Step 1: Adicionar o script do cliente Supabase via CDN no `<head>`**

Localizar a tag `<head>` de `Programa/tutor-fiscal.html` e adicionar:

```html
<script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/dist/umd/supabase.js"></script>
```

- [ ] **Step 2: Adicionar a seção `SUPABASE` com cliente e funções de auth**

Inserir antes da seção `/* ═══ Sincronização automática ═══ */`:

```js
/* ═══ SUPABASE ═══ */
let supabaseClient = null;

function configurarSupabase(url, anonKey) {
  S.supabaseUrl = url;
  S.supabaseAnonKey = anonKey;
  salvar();
  supabaseClient = window.supabase.createClient(url, anonKey);
  return supabaseClient;
}

function iniciarSupabaseSalvo() {
  if (S.supabaseUrl && S.supabaseAnonKey) {
    supabaseClient = window.supabase.createClient(S.supabaseUrl, S.supabaseAnonKey);
  }
  return supabaseClient;
}

async function signUp(email, senha) {
  if (!supabaseClient) throw new Error('Configure a conexão com o Supabase em Ajustes antes de criar uma conta.');
  const { data, error } = await supabaseClient.auth.signUp({ email, password: senha });
  if (error) throw error;
  return data;
}

async function signIn(email, senha) {
  if (!supabaseClient) throw new Error('Configure a conexão com o Supabase em Ajustes antes de entrar.');
  const { data, error } = await supabaseClient.auth.signInWithPassword({ email, password: senha });
  if (error) throw error;
  return data;
}

async function signOut() {
  if (!supabaseClient) return;
  await supabaseClient.auth.signOut();
}

async function getSession() {
  if (!supabaseClient) return null;
  const { data } = await supabaseClient.auth.getSession();
  return data.session;
}
```

Note: `iniciarSupabaseSalvo()` lê `S.supabaseUrl`/`S.supabaseAnonKey`, então só pode rodar **depois** que `S` for hidratado do storage — não no carregamento do `<script>` (S ainda está no valor padrão da linha 763 nesse momento).

- [ ] **Step 3: Chamar `iniciarSupabaseSalvo()` no bootstrap, depois de `carregar()`**

Localizar a IIFE de bootstrap (linha ~3371 no mapa atual):

```js
(async ()=>{ await carregar(); aplicarTema(); await carregarBase(); await carregarQB(); await carregarCache(); await sincIniciar(); })();
```

Substituir por:

```js
(async ()=>{ await carregar(); iniciarSupabaseSalvo(); aplicarTema(); await carregarBase(); await carregarQB(); await carregarCache(); await sincIniciar(); })();
```

- [ ] **Step 4: Adicionar UI mínima em Ajustes (conexão + login)**

Na seção `Ajustes` (linha ~3343 no mapa atual), adicionar um bloco novo:

```html
<div class="secao-supabase">
  <h3>Conta e sincronização (Diagramas/Esquemas)</h3>
  <label>URL do Supabase <input type="text" id="supabaseUrlInput" placeholder="http://127.0.0.1:54321"></label>
  <label>Chave anônima <input type="text" id="supabaseAnonKeyInput" placeholder="anon key"></label>
  <button onclick="configurarSupabase(document.getElementById('supabaseUrlInput').value, document.getElementById('supabaseAnonKeyInput').value)">Conectar</button>
  <hr>
  <label>Email <input type="email" id="authEmailInput"></label>
  <label>Senha <input type="password" id="authSenhaInput"></label>
  <button onclick="signUp(document.getElementById('authEmailInput').value, document.getElementById('authSenhaInput').value).then(() => alert('Conta criada. Verifique se precisa confirmar email.')).catch(e => alert(e.message))">Criar conta</button>
  <button onclick="signIn(document.getElementById('authEmailInput').value, document.getElementById('authSenhaInput').value).then(() => alert('Login OK')).catch(e => alert(e.message))">Entrar</button>
  <button onclick="signOut().then(() => alert('Saiu'))">Sair</button>
</div>
```

- [ ] **Step 5: Verificação manual (não há teste automatizado de JS neste projeto — convenção existente, spec Seção 10)**

1. Abrir `Programa/tutor-fiscal.html` no navegador (Supabase local do Task 1 precisa estar rodando: `npx supabase start`).
2. Ir em Ajustes, colar a `API URL` e a `anon key` locais, clicar "Conectar".
3. Criar uma conta de teste com "Criar conta", depois "Entrar".
4. Recarregar a página, confirmar que `getSession()` (via console do navegador: `await getSession()`) retorna a sessão sem precisar logar de novo.
5. Clicar "Sair" e confirmar que `await getSession()` volta `null`.

- [ ] **Step 6: Commit**

```bash
git add "Programa/tutor-fiscal.html"
git commit -m "feat: cliente Supabase e autenticacao basica na tutor-fiscal.html"
```

---

### Task 4: Sincronizar mudanças com `tutor-fiscal-windows/index.html`

**Files:**
- Modify: `Programa/tutor-fiscal-windows/index.html`

**Interfaces:**
- Consumes: diff exato produzido nas Tasks 3
- Produces: nenhuma nova — apenas mantém os dois arquivos alinhados (regra crítica do `CLAUDE.md`)

- [ ] **Step 1: Replicar manualmente as mudanças do Task 3 (Steps 1-3) em `Programa/tutor-fiscal-windows/index.html`**

Aplicar exatamente os mesmos três trechos (script CDN no `<head>`, seção `SUPABASE`, bloco de UI em Ajustes) neste segundo arquivo. **Não alterar** a linha do `<link rel="manifest">` — ela é a única diferença intencional entre os dois arquivos (`CLAUDE.md`).

- [ ] **Step 2: Verificação manual**

Repetir o Step 4 do Task 3, mas abrindo `Programa/tutor-fiscal-windows/index.html` (ou via `Iniciar Tutor Fiscal.bat`) desta vez.

- [ ] **Step 3: Commit**

```bash
git add "Programa/tutor-fiscal-windows/index.html"
git commit -m "chore: sincronizar tutor-fiscal-windows/index.html com auth Supabase"
```

---

## Ao final deste plano

- Supabase local rodando com as 4 tabelas + RLS testado automaticamente.
- Login/logout funcionando nos dois arquivos HTML.
- **Próximo:** Plano 2/5 — Ingestão da Base de Conhecimento (PDF → `knowledge_chunks` com embeddings Voyage AI + retrieval via `pgvector`).
