# Design — Diagramas e Esquemas + Base de Conhecimento (sobre Supabase)

**Status:** design aprovado em conversa, aguardando revisão do usuário sobre o texto escrito.
**Ler também:** `../../../CLAUDE.md` (contexto geral do app) e `../../handoff/2026-08-03-diagramas-esquemas-handoff.md` (histórico do brainstorming, diagnóstico original, decisões da primeira metade da sessão).

## 1. Escopo

Este design cobre dois dos sete subprojetos futuros listados no handoff, fundidos num só porque passaram a depender da mesma fundação de armazenamento: **Diagramas e Esquemas** (subprojeto 1) e **Base de Conhecimento** (subprojeto 2). A fusão foi decisão explícita do usuário: ele quer a base de armazenamento já escalável desde o início, não um remendo temporário.

Fora de escopo aqui: progresso do aluno, configurações, nível/ciclo (`S` hoje) continuam em `localStorage`, sem migrar — não fazem parte deste subprojeto. Cards de Lei Seca, Banco de Questões regex, Trilha/Ciclo, Discursiva e Painel/Sincronização (subprojetos 3–7) não são tocados aqui.

## 2. Motivação e restrições

- Diagnóstico original (ver handoff 2026-08-03): cobertura de fichas quase nula (3/131 tópicos), Base de Conhecimento com teto de 3,5 MB compartilhado que descarta PDFs antigos sem avisar, retrieval por palavra-chave simples, e os 5 moldes offline de diagrama não davam conta de texto de PDF corrido.
- Guia de Carga Cognitiva (CLT/BNCC) trazido pelo usuário é restrição de design vinculante: Single-Card View, código de cor semântico fixo (`core`=verde/regra, `alert`=âmbar/atenção-exceção, `anchor`=azul/termo técnico), blocos "por que isso cai" e verificação, limites de ≤40 palavras/parágrafo e ≤150 palavras/unidade de tela.
- "Qualidade visual máxima" (prioridade nº1 definida no handoff) significa **clareza e hierarquia bem executadas — não decoração/estilização.** Confirmado explicitamente pelo usuário nesta sessão.
- Motivação de negócio nova: o usuário considera vender o app para uma empresa no futuro. Isso pesou a favor de uma arquitetura com contas/dados centralizados em vez de armazenamento só local.

## 3. Arquitetura

Migração de `localStorage` para **Supabase** (Postgres + `pgvector`), trocando a promessa atual de "sem conta, sem nuvem" por "com conta, sempre online" **só para esta área do app** (fichas, base de conhecimento, banco de questões). O resto do app continua local.

- **Supabase Auth**: login simples (email/senha ou magic link).
- **RLS (row-level security) por `user_id` desde o início**, mesmo com um único usuário hoje — é o padrão correto e evita retrabalho se a empresa compradora quiser abrir para vários usuários depois.
- **`pgvector`** substitui a busca por palavra-chave (`recuperarTrechos`) por retrieval semântico de verdade, e remove o teto artificial de 3,5 MB da Base de Conhecimento atual.
- Sincronização Drive/OneDrive existente deixa de ser necessária para os dados que forem para o Supabase (ele sincroniza sozinho entre dispositivos); continua útil só para o que ficar local (`S`).

## 4. Modelo de dados

### `knowledge_chunks`
Trechos indexados dos PDFs enviados, um por linha, com coluna `embedding vector` (`pgvector`). Substitui o `BASE` atual do `localStorage`.

### `fichas`
Modelo unificado que funde `FICHAS` (estático, feito à mão) e `S.fichasUser` (dinâmico) — hoje são dois formatos incompatíveis, essa é a correção real do design.

| Campo | Conteúdo |
|---|---|
| `id`, `user_id` | identidade + isolamento por RLS |
| `disciplina_id`, `topico` | chave de busca (única por usuário) |
| `conceito_central` | texto guia, ≤150 palavras |
| `por_que_cai` | 1-2 pontos de relevância pra prova |
| `diagrama_schema` | JSON estruturado: nós, relações, ênfase semântica por nó (`core`/`alert`/`anchor`), tipo de layout escolhido pela IA |
| `problema_resolvido` | enunciado + explicação passo a passo (worked example, fixo 1:1 com a ficha) |
| `source_chunk_ids` | quais `knowledge_chunks` originaram esta ficha (rastreabilidade, usado na revisão anti-alucinação) |

### `problems`
Problemas independentes extraídos do PDF, **acumulando ao longo do tempo** (não um par fixo) — alimentam a área de Revisão com repetição espaçada que já existe no app.

| Campo | Conteúdo |
|---|---|
| `id`, `ficha_id` (FK) | vínculo com a ficha/tópico |
| `enunciado` | o problema, extraído do PDF |
| `gabarito`, `correcao_detalhada` | revelados só depois que o aluno responde |
| `origem_chunk_id` | trecho de origem (evita gerar o mesmo problema de novo) |

### `review_log`
Histórico de toda revisão feita pela IA sobre o próprio trabalho (ver seção 6) — resultado passou/falhou, o que foi sinalizado, se houve regeneração. Consultável no Painel para orientar ajuste manual de prompts ao longo do tempo.

## 5. Pipeline de IA — geração

Duas chamadas com padrões de cache diferentes, seguindo o mesmo princípio de "gerar uma vez, reusar" que o app já usa hoje nas outras 6 chamadas de IA existentes:

1. **`gerarFichaIA(disciplina, topico)`** — roda uma vez por tópico, resultado persistido em `fichas`:
   - Busca semântica em `knowledge_chunks` via `pgvector`.
   - Uma chamada à IA recebe os trechos recuperados e retorna JSON estruturado: `conceito_central`, `por_que_cai`, `diagrama_schema`, `problema_resolvido`.

2. **`gerarProblemaIndependente(disciplina, topico)`** — **repetível**, chamada de novo sempre que a Revisão espaçada precisar de mais um problema para aquele tópico:
   - Mesma busca semântica; evita reusar `origem_chunk_id` já usado antes para não repetir o mesmo problema.
   - Cada chamada gera uma linha nova em `problems`.

## 6. Pipeline de IA — revisão e autoaprimoramento

Depois de cada geração (ficha ou problema independente), uma segunda chamada de IA revisa o próprio resultado em três frentes:

1. **Fidelidade à fonte** — o conteúdo gerado bate com os `knowledge_chunks` referenciados (`source_chunk_ids`/`origem_chunk_id`), pega alucinação.
2. **Conformidade com o guia de Carga Cognitiva** — limites de palavras, cor semântica aplicada corretamente, layout condizente com o conteúdo.
3. **Correção factual/matemática** — a conta/resposta do problema está certa.

**Comportamento em caso de falha:**
- 1ª falha → regenera automaticamente (1 nova tentativa) antes de mostrar ao aluno.
- Falha novamente após o retry → mostra mesmo assim, com aviso discreto sinalizado ao aluno, e grava em `review_log` como "falhou após retry".

**Autoaprimoramento**: todo resultado de revisão é persistido em `review_log`. Isso forma um histórico consultável de padrões (ex. "layout X erra com frequência", "cor semântica sai errada na disciplina Y") que o desenvolvedor revisa periodicamente para ajustar os prompts de geração com base em dado real. **Não é** um sistema que se retreina ou ajusta prompts sozinho — isso seria uma categoria de risco/complexidade maior, fora de escopo aqui.

## 7. Motor de composição SVG

Consome `diagrama_schema` (JSON) e renderiza SVG puro — substitui os 5 moldes fixos atuais, que falhavam porque esperavam texto já organizado e recebiam parágrafo corrido de PDF.

- **Layout**: a IA escolhe o tipo de layout (`sequência`/`hierarquia`/`comparação`/`ciclo`/`mapa`) como campo do próprio schema; o motor tem um renderer por tipo, agora trabalhando sobre dado estruturado, não texto bruto.
- **Cor semântica fixa**: `core`=verde (regra/conceito-chave), `alert`=âmbar (atenção/exceção), `anchor`=azul (termo técnico) — aplicada por nó, nunca como "primário/secundário" genérico.
- **Tipografia**: hierarquia de 3 níveis (título do diagrama, rótulo de nó, texto de apoio), tamanhos fixos em tokens.
- **Tema claro/escuro**: mesma cor semântica, luminosidade ajustada por tema — o significado nunca muda, só o contraste.

## 8. Fluxo do card (composição aprovada: A)

Composição A — texto guia + diagrama + exemplo em caixa, numa única unidade visual (Single-Card View do guia CLT). Três telas em sequência por tópico:

1. **Diagrama + teoria**: `conceito_central` (verde) + `diagrama_schema` renderizado + `por_que_cai` (âmbar).
2. **Problema resolvido**: `problema_resolvido` — enunciado + explicação passo a passo (azul), extraído do PDF por IA.
3. **Problema independente**: enunciado de um item de `problems`, campo de resposta, e só depois de responder revela gabarito + correção detalhada (verde).

## 9. Tratamento de erro

| Cenário | Comportamento |
|---|---|
| IA indisponível ou JSON malformado | Estado "não foi possível gerar agora" + botão de tentar de novo. Nunca mostra erro técnico cru ao aluno. |
| Revisão falha 2x seguidas (retry incluso) | Mostra a ficha mesmo assim com aviso discreto; grava em `review_log`. |
| Retrieval não acha trechos relevantes pro tópico | Avisa que falta material-fonte para esse tópico; não tenta gerar do zero (evita alucinação por falta de contexto). |
| Supabase offline/sem internet | Aviso de "sem conexão" restrito à área de fichas/diagramas/base de conhecimento. Resto do app (progresso local) continua funcionando normalmente. |

## 10. Plano de teste/verificação

O app não tem teste automatizado hoje (convenção do projeto — verificação sempre manual). Mantido para tudo, **com uma exceção**:

- **RLS ganha teste automatizado** — é a única camada que impede um usuário de ver dado de outro, e falha nela é silenciosa até virar vazamento real. Testes em SQL confirmando isolamento entre usuários em `fichas`, `problems` e `knowledge_chunks`.
- **Resto continua manual**: subir um PDF de teste, gerar uma ficha ponta a ponta, conferir as 3 telas, forçar uma falha de revisão para checar o caminho de regeneração/aviso.

## 11. Fora de escopo (explicitamente adiado)

- Migração de `S` (progresso/config) para o Supabase — fica local por enquanto.
- Ajuste automático de prompts/modelo (fine-tuning ou self-tuning) — o `review_log` é insumo manual para o desenvolvedor, não um sistema que se retreina sozinho.
- Multiusuário de verdade (times, permissões entre usuários) — a base (RLS por `user_id`) já suporta isso tecnicamente, mas nenhuma UI ou fluxo multiusuário é construído agora.
- Subprojetos 3–7 (Cards de Lei Seca, Banco de Questões regex, Trilha/Ciclo, Discursiva, Painel/Sincronização) — não tocados por este design.
