# Ingestão da Base de Conhecimento (Plano 2/5) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fazer os PDFs enviados pelo aluno virarem embeddings pesquisáveis em `public.knowledge_chunks` (Supabase + `pgvector`), com uma função de retrieval semântico que o Plano 3 (pipeline de IA) vai consumir — substituindo a busca por palavra-chave (`recuperarTrechos`) como fonte principal, sem quebrá-la (fica como fallback).

**Architecture:** `processarPDFs` (já existe, extrai texto de PDF no navegador) passa a, além de alimentar `BASE`/`localStorage` como hoje, também gerar embeddings via Voyage AI e gravar em `public.knowledge_chunks`. Uma função Postgres (`match_knowledge_chunks`) faz a busca por similaridade de cosseno respeitando RLS. Um novo `recuperarTrechosSemanticos()` chama essa função; se o Supabase não estiver configurado ou a chamada falhar, cai de volta para o `recuperarTrechos()` por palavra-chave que já existe — nenhuma funcionalidade atual quebra.

**Tech Stack:** Voyage AI (`voyage-3-lite`, API de embeddings), `pgvector` (já habilitado no Plano 1), `@supabase/supabase-js@2` (já carregado no Plano 1).

## Global Constraints

(herdadas do Plano 1, mais:)

- Este plano **depende do Plano 1 já implementado** (tabelas + RLS + cliente Supabase + auth funcionando).
- `BASE`/`recuperarTrechos()`/`processarPDFs()` (código existente, `Programa/tutor-fiscal.html` linhas ~2531-2690) continuam existindo e funcionando exatamente como hoje — usados por `gerarCasoIA` e outras 5 chamadas de IA fora do escopo deste redesenho (spec, Seção 1 "fora de escopo"). Este plano **adiciona** uma segunda via de indexação (Supabase), não substitui a primeira.
- Chave da Voyage AI segue a mesma convenção da chave Anthropic já existente: campo em `S` (`S.voyageApiKey`), nunca commitada, com uma função `headersVoyage()` espelhando `headersIA()` (linha ~3074).
- `tutor-fiscal.html` e `tutor-fiscal-windows/index.html` precisam ficar sincronizados manualmente (regra do `CLAUDE.md`) — toda task que mexe no primeiro tem uma task-irmã de sincronização.

---

### Task 1: Função de busca semântica (`match_knowledge_chunks`) com teste pgTAP

**Files:**
- Test: `supabase/tests/database/002_match_knowledge_chunks.test.sql`
- Create: `supabase/migrations/<timestamp>_match_knowledge_chunks.sql`

**Interfaces:**
- Consumes: tabela `public.knowledge_chunks` (Plano 1)
- Produces: função SQL `public.match_knowledge_chunks(query_embedding vector(512), p_disciplina_id text, match_count int default 5) returns table(id uuid, texto text, similarity float)` — chamada via `supabaseClient.rpc('match_knowledge_chunks', {...})` na Task 4.

- [ ] **Step 1: Escrever o teste pgTAP (vai falhar — a função ainda não existe)**

```sql
-- supabase/tests/database/002_match_knowledge_chunks.test.sql
begin;
select plan(4);

insert into auth.users (id, email) values
  ('33333333-3333-3333-3333-333333333333', 'user-c@test.local'),
  ('44444444-4444-4444-4444-444444444444', 'user-d@test.local');

select set_config('request.jwt.claims', '{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated"}', true);
set local role authenticated;

insert into public.knowledge_chunks (user_id, disciplina_id, pdf_nome, texto, embedding) values
  ('33333333-3333-3333-3333-333333333333', 'cont', '00.pdf', 'trecho proximo da consulta',
   ('[1' || repeat(',0', 511) || ']')::vector),
  ('33333333-3333-3333-3333-333333333333', 'cont', '00.pdf', 'trecho distante da consulta',
   ('[-1' || repeat(',0', 511) || ']')::vector),
  ('33333333-3333-3333-3333-333333333333', 'trib', '01.pdf', 'trecho de outra disciplina',
   ('[1' || repeat(',0', 511) || ']')::vector);

-- consulta idêntica ao "trecho proximo": deve vir em 1º, filtrado só pela disciplina 'cont'
select results_eq(
  $$select texto from public.match_knowledge_chunks(('[1' || repeat(',0', 511) || ']')::vector, 'cont', 5) limit 1$$,
  $$values ('trecho proximo da consulta'::text)$$,
  'retorna o trecho mais proximo primeiro, filtrado pela disciplina certa'
);

select is(
  (select count(*) from public.match_knowledge_chunks(('[1' || repeat(',0', 511) || ']')::vector, 'cont', 5))::int,
  2,
  'nao retorna trechos de outra disciplina'
);

-- troca para usuario D: RLS ainda se aplica dentro da funcao (nao eh security definer)
select set_config('request.jwt.claims', '{"sub":"44444444-4444-4444-4444-444444444444","role":"authenticated"}', true);

select is(
  (select count(*) from public.match_knowledge_chunks(('[1' || repeat(',0', 511) || ']')::vector, 'cont', 5))::int,
  0,
  'usuario D nao ve chunks indexados pelo usuario C'
);

select isnt_definer('public', 'match_knowledge_chunks', 'match_knowledge_chunks nao eh security definer (RLS precisa se aplicar)');

select * from finish();
rollback;
```

- [ ] **Step 2: Rodar o teste para confirmar que falha**

Run: `npx supabase test db`
Expected: FAIL — `function public.match_knowledge_chunks(...) does not exist`.

- [ ] **Step 3: Escrever a migração**

```sql
-- supabase/migrations/<timestamp>_match_knowledge_chunks.sql
create or replace function public.match_knowledge_chunks(
  query_embedding vector(512),
  p_disciplina_id text,
  match_count int default 5
)
returns table (id uuid, texto text, similarity float)
language sql
stable
as $$
  select id, texto, 1 - (embedding <=> query_embedding) as similarity
  from public.knowledge_chunks
  where disciplina_id = p_disciplina_id
  order by embedding <=> query_embedding
  limit match_count;
$$;
```

- [ ] **Step 4: Rodar o teste de novo e confirmar que passa**

Run: `npx supabase test db`
Expected: PASS — `4/4` asserções (mais as 10 do Plano 1, total `14/14`).

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations supabase/tests
git commit -m "feat: funcao match_knowledge_chunks para retrieval semantico via pgvector"
```

---

### Task 2: Cliente Voyage AI para embeddings

**Files:**
- Modify: `Programa/tutor-fiscal.html` (nova seção `/* ═══ EMBEDDINGS (VOYAGE AI) ═══ */`, inserida logo após a seção `SUPABASE` criada no Plano 1)

**Interfaces:**
- Consumes: `S.voyageApiKey` (novo campo em `S`, mesma convenção de `S.apiKey`)
- Produces: `async function gerarEmbeddings(textos, tipo)` → retorna `Promise<number[][]>`, um vetor de 512 posições por texto de entrada. `tipo` é `'document'` (indexação) ou `'query'` (busca) — usado pelas Tasks 3 e 4.

- [ ] **Step 1: Adicionar a seção de embeddings**

```js
/* ═══ EMBEDDINGS (VOYAGE AI) ═══
   Mesma convenção da chave Anthropic: fica só em S.voyageApiKey, salva no aparelho. */
function headersVoyage(){
  return {"Content-Type":"application/json", "Authorization":"Bearer "+(S.voyageApiKey||'')};
}
function salvarChaveVoyage(){
  S.voyageApiKey = document.getElementById('voyage-key').value.trim();
  salvar();
  document.getElementById('voyage-key-st').innerHTML = S.voyageApiKey
    ? '<div class="fb ok">Chave salva neste aparelho. A indexação semântica de PDFs está ativa.</div>'
    : '<div class="fb aj">Chave removida. PDFs continuam sendo indexados por palavra-chave (modo local), sem busca semântica.</div>';
}
async function gerarEmbeddings(textos, tipo){
  if(!S.voyageApiKey) throw new Error('Configure a chave da Voyage AI em Ajustes antes de indexar ou buscar semanticamente.');
  const lotes = [];
  for(let i=0;i<textos.length;i+=100) lotes.push(textos.slice(i,i+100));
  const embeddings = [];
  for(const lote of lotes){
    const r = await fetch("https://api.voyageai.com/v1/embeddings", {
      method:"POST", headers: headersVoyage(),
      body: JSON.stringify({input: lote, model: "voyage-3-lite", input_type: tipo||"document"})
    });
    if(!r.ok) throw new Error('Falha ao gerar embeddings (Voyage AI retornou '+r.status+')');
    const data = await r.json();
    data.data.forEach(d=>embeddings.push(d.embedding));
  }
  return embeddings;
}
```

- [ ] **Step 2: Adicionar campo de chave em Ajustes**

Na seção `Ajustes` (linha ~3343 no mapa atual), próximo ao campo de chave da Anthropic (`api-key`), adicionar:

```html
<label>Chave Voyage AI (embeddings para busca semântica) <input type="text" id="voyage-key" value="${S.voyageApiKey||''}"></label>
<button onclick="salvarChaveVoyage()">Salvar chave Voyage</button>
<div id="voyage-key-st"></div>
```

- [ ] **Step 3: Verificação manual**

1. Abrir o app, ir em Ajustes, colar uma chave real da Voyage AI (console.voyageai.com), salvar.
2. No console do navegador: `await gerarEmbeddings(['teste de embedding'], 'document')` — deve retornar um array com 1 array interno de 512 números.
3. Remover a chave e confirmar que a mesma chamada rejeita com a mensagem de erro clara (não trava a página).

- [ ] **Step 4: Commit**

```bash
git add "Programa/tutor-fiscal.html"
git commit -m "feat: cliente de embeddings Voyage AI (gerarEmbeddings)"
```

---

### Task 3: Indexação automática no Supabase ao processar um PDF

**Files:**
- Modify: `Programa/tutor-fiscal.html:2583-2635` (função `processarPDFs`, seção `BASE DE CONHECIMENTO`)

**Interfaces:**
- Consumes: `gerarEmbeddings` (Task 2), `supabaseClient` (Plano 1), `chunks` já calculados por `fatiar(texto)` (código existente, linha ~2570)
- Produces: `async function indexarChunksSupabase(nome, discId, chunks)` — grava em `public.knowledge_chunks`. Chamada dentro de `processarPDFs`, não exportada para outras tasks.

- [ ] **Step 1: Adicionar a função `indexarChunksSupabase`, logo antes de `processarPDFs` (linha ~2583)**

```js
async function indexarChunksSupabase(nome, discId, chunks){
  if(!supabaseClient || !S.voyageApiKey) return;
  const embeddings = await gerarEmbeddings(chunks, 'document');
  const linhas = chunks.map((texto,i)=>({disciplina_id: discId, pdf_nome: nome, texto, embedding: embeddings[i]}));
  const { error } = await supabaseClient.from('knowledge_chunks').insert(linhas);
  if(error) throw error;
}
```

- [ ] **Step 2: Chamar a função dentro de `processarPDFs`, sem quebrar o fluxo existente se falhar**

Modificar o trecho de `Programa/tutor-fiscal.html:2622-2627` (dentro do `for(const f of files)`, logo após `await salvarBase();`):

De:
```js
      await salvarBase();
      const qs = extrairQuestoes(texto, baseDiscSel, f.name);
```

Para:
```js
      await salvarBase();
      try{
        await indexarChunksSupabase(f.name, baseDiscSel, chunks);
      }catch(e){
        console.error('Falha ao indexar no Supabase (base de conhecimento semântica):', e);
        st.innerHTML += `<div class="fb aj">Indexação semântica falhou para ${f.name} (a busca por palavra-chave local continua funcionando). Detalhe: ${e.message}</div>`;
      }
      const qs = extrairQuestoes(texto, baseDiscSel, f.name);
```

- [ ] **Step 3: Verificação manual**

1. Com Supabase local rodando, chave Voyage configurada e usuário logado (Task 3/4 do Plano 1), enviar um PDF real de teste na aba Base de Conhecimento.
2. Confirmar na mensagem de status que aparece "N trechos indexados" (fluxo antigo, local) sem erro extra de indexação semântica.
3. Verificar no Supabase Studio local (`npx supabase status` para achar a URL do Studio) que `knowledge_chunks` tem uma linha por chunk do PDF enviado, com `embedding` preenchido.
4. Repetir sem a chave Voyage configurada — confirmar que o upload continua funcionando normalmente (só sem indexação semântica), sem travar a UI.

- [ ] **Step 4: Commit**

```bash
git add "Programa/tutor-fiscal.html"
git commit -m "feat: indexar chunks de PDF no Supabase (knowledge_chunks) ao processar upload"
```

---

### Task 4: Retrieval semântico com fallback para busca por palavra-chave

**Files:**
- Modify: `Programa/tutor-fiscal.html` (nova função, logo após `recuperarTrechos` — linha ~2689)

**Interfaces:**
- Consumes: `gerarEmbeddings` (Task 2), `supabaseClient.rpc('match_knowledge_chunks', ...)` (Task 1), `recuperarTrechos` (código existente, linha ~2677, usado como fallback)
- Produces: `async function recuperarTrechosSemanticos(discId, consulta, n)` → `Promise<string[]>` — **esta é a função que o Plano 3 (pipeline de IA) vai chamar**, não `recuperarTrechos` diretamente.

- [ ] **Step 1: Adicionar a função, logo após `recuperarTrechos` (linha ~2689)**

```js
async function recuperarTrechosSemanticos(discId, consulta, n){
  if(!supabaseClient || !S.voyageApiKey) return recuperarTrechos(discId, consulta, n);
  try{
    const [embedding] = await gerarEmbeddings([consulta], 'query');
    const { data, error } = await supabaseClient.rpc('match_knowledge_chunks', {
      query_embedding: embedding, p_disciplina_id: discId, match_count: n||5
    });
    if(error) throw error;
    if(!data || !data.length) return recuperarTrechos(discId, consulta, n);
    return data.map(r=>r.texto);
  }catch(e){
    console.error('Retrieval semântico falhou, usando busca por palavra-chave local:', e);
    return recuperarTrechos(discId, consulta, n);
  }
}
```

- [ ] **Step 2: Verificação manual**

1. Com um PDF já indexado no Supabase (Task 3), no console do navegador: `await recuperarTrechosSemanticos('cont', 'patrimônio líquido', 3)` — deve retornar até 3 trechos, vindos do Supabase (confirmar comparando com o conteúdo real do PDF de teste).
2. Desconectar do Supabase (`supabaseClient = null` no console) e repetir a mesma chamada — deve cair no `recuperarTrechos` local sem lançar erro.

- [ ] **Step 3: Commit**

```bash
git add "Programa/tutor-fiscal.html"
git commit -m "feat: recuperarTrechosSemanticos com fallback para busca por palavra-chave"
```

---

### Task 5: Sincronizar mudanças com `tutor-fiscal-windows/index.html`

**Files:**
- Modify: `Programa/tutor-fiscal-windows/index.html`

**Interfaces:**
- Consumes: diffs exatos das Tasks 2, 3 e 4
- Produces: nenhuma nova — mantém os dois arquivos alinhados (regra crítica do `CLAUDE.md`)

- [ ] **Step 1: Replicar manualmente as mudanças das Tasks 2-4 em `Programa/tutor-fiscal-windows/index.html`**

Aplicar exatamente os mesmos trechos (seção `EMBEDDINGS`, campo de chave Voyage em Ajustes, `indexarChunksSupabase` + modificação de `processarPDFs`, `recuperarTrechosSemanticos`).

- [ ] **Step 2: Verificação manual**

Repetir a verificação da Task 3 Step 3 e da Task 4 Step 2, mas abrindo `Programa/tutor-fiscal-windows/index.html` (ou via `Iniciar Tutor Fiscal.bat`).

- [ ] **Step 3: Commit**

```bash
git add "Programa/tutor-fiscal-windows/index.html"
git commit -m "chore: sincronizar tutor-fiscal-windows/index.html com ingestao semantica"
```

---

## Ao final deste plano

- PDFs enviados passam a ser indexados tanto localmente (como hoje) quanto no Supabase com embeddings.
- `recuperarTrechosSemanticos()` disponível e testado, com fallback seguro.
- **Próximo:** Plano 3/5 — Pipeline de IA (`gerarFichaIA`, `gerarProblemaIndependente`, revisão + `review_log`), que consome `recuperarTrechosSemanticos`.
