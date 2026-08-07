# Tutor Fiscal — contexto do projeto

> Leia este arquivo antes de mexer em qualquer coisa. Ele existe pra continuar o trabalho em qualquer chat/sessão nova sem perder contexto. Atualize-o ao final de cada sessão relevante.

> **⏸ Spec de 2026-08-05 REVISADO pelo usuário (respostas coletadas), nenhum código do Supabase escrito ainda.** Redesenho de Diagramas e Esquemas + Base de Conhecimento (fundidos, migrando para Supabase). Spec em `docs/superpowers/specs/2026-08-05-diagramas-esquemas-base-conhecimento-design.md`, 4 pontos em aberto resolvidos (fichas legadas descartadas, login e-mail+senha, motivo de negócio confirmado, custo Supabase não é bloqueio) — decisões registradas em `docs/handoff/2026-08-03-diagramas-esquemas-handoff.md`. 5 planos já escritos em `docs/superpowers/plans/2026-08-05-*.md`, prontos pra implementação.
> **Prioridade explícita do usuário: sem pressa nisso.** Ele precisa estudar logo e vai usar o app publicado (abaixo) como está — essa reforma segue em paralelo, sem bloquear o uso.

## O que é o app

**Tutor Fiscal** — app de estudo para concursos fiscais (Receita Federal e área fiscal estadual), construído sobre a Teoria da Carga Cognitiva de John Sweller e adaptado para perfil **AuDHD com TPAC** (memória de trabalho limitada). Roda 100% no navegador, sem conta, sem nuvem — os dados ficam no aparelho (com sincronização opcional via Google Drive/OneDrive).

Cinco áreas: **Hoje** (uma matéria por vez) · **Ciclo** (blocos por nível) · **Revisão** (banco de questões com repetição espaçada) · **Painel** (histórico, backup, material gerado) · **Ajustes** (tema, banca, IA).

Recursos com IA (opcionais — o app funciona sem IA usando banco interno): geração de casos de estudo, cards de lei unificados, esquemas/diagramas, trilha de estudo a partir de PDF, avaliação de discursivas.

## Onde tudo está

```
C:\Users\henri\Documents\Claude Code\Aplicativo_Estudo_Neurodivergente\   ← pasta canônica do projeto
├── CLAUDE.md                              ← este arquivo
└── Programa\
    ├── tutor-fiscal.html                  ← FONTE DA VERDADE (arquivo único, HTML+CSS+JS)
    └── tutor-fiscal-windows\               ← ÚNICA forma de distribuição/instalação hoje
        ├── index.html                      ← CÓPIA sincronizada manualmente de tutor-fiscal.html
        ├── Iniciar Tutor Fiscal.bat        ← launcher (abre em modo --app do Edge/Chrome)
        ├── manifest.webmanifest, sw.js, icone-*.png
        └── LEIA-ME-WINDOWS.txt
```

**Regra crítica:** `tutor-fiscal.html` e `tutor-fiscal-windows\index.html` são dois arquivos separados com o mesmo conteúdo. **Toda edição de código em um precisa ser replicada manualmente no outro** (só existe uma diferença intencional entre eles: a linha do `<link rel="manifest">` — o fonte usa data-URI inline, a cópia distribuída referencia `manifest.webmanifest`). Não existe build step automático — já aconteceu de esquecer isso e os dois desalinharem.

Anteriormente existia mais uma forma de instalação (`TutorFiscal-Setup\` instalador .exe) — **foi removida em 2026-08-02** a pedido do usuário pra simplificar. Não recriar sem pedido explícito.

## Publicação na web (GitHub Pages)

O app está publicado e acessível de qualquer navegador/dispositivo, incluindo instalável como PWA no Android ("Adicionar à tela inicial"):

- **Site ao vivo:** https://henriqueacfedutech-lab.github.io/aplicativo-estudo-neurodivergente/
- **Repositório:** `github.com/henriqueacfedutech-lab/aplicativo-estudo-neurodivergente` (público)
- Branch `master` = código-fonte completo do projeto (mesma estrutura desta pasta).
- Branch `gh-pages` = **só** os 5 arquivos publicados (`index.html`, `manifest.webmanifest`, `sw.js`, `icone-192.png`, `icone-512.png`, cópia de `tutor-fiscal-windows/`), na raiz. GitHub Pages publica sozinho a cada `git push` nela — não precisa de passo manual nem GitHub Actions.
- **Dado importante:** a versão web (`https://henriqueacfedutech-lab.github.io/...`) e a versão local (`file://...`) são origens diferentes pro navegador — `localStorage` (progresso, PDFs, chave de API) **não sincroniza sozinho** entre as duas. Usar a sincronização Drive/OneDrive do app, ou exportar/importar backup manual, se precisar levar dado de um lado pro outro.

## Mapa do arquivo-fonte (tutor-fiscal.html, ~3400 linhas)

Seções marcadas com `/* ═══ NOME ═══ */`, nesta ordem:

| Linha | Seção |
|---|---|
| 727 | Estado e persistência (localStorage: `S`, `CACHE`, `QB`, `BASE`) |
| 785 | Cache de material gerado por IA |
| 847 | Card de Lei Seca Unificada |
| 974 | Modos adaptativos e 3 níveis (expert reversal) |
| 1008 | Estúdio de diagramas (offline, sem IA) |
| 1267 | Banco de questões extraídas dos PDFs (regex local, sem IA) |
| 1445 | Fichas visuais por tópico |
| 1616 | Glossário |
| 1683 | Motor de blocos e rotação |
| 1816 | Banco local de casos (fallback sem IA) |
| 1908–2200 | Navegação, check-in, plano dinâmico, ciclo, revisão, editor de blocos, trilha, disciplinas próprias, sessão |
| 2531 | Base de conhecimento (RAG local a partir de PDFs) |
| 2692 | Trilha automática a partir do PDF (usa IA) |
| 2777 | Sincronização automática (Drive/OneDrive, com debounce de 1.5s) |
| 2914 | Painel, histórico e backup |
| 2983 | Motor NotebookLM (alternativa gratuita à API) |
| 3071 | Acesso à IA (`headersIA()`, `motorIA()`) |
| 3096 | Geração por IA (cards) |
| 3170 | Discursiva (casos + avaliação) |
| 3343 | Ajustes |

## Armazenamento (chaves no `store`/localStorage)

- `tutor-fiscal-v1` → `S` — estado principal: progresso, config, cards, trilhas, níveis, stats de desempenho
- `tutor-fiscal-cache-v1` → `CACHE` — material gerado por IA (casos, esquemas, discursivas) + contadores `meta.chamadas`/`meta.reusos`
- `tutor-fiscal-qb-v1` → `QB` — banco de questões extraídas de PDF (máx. 2500, dedup por ID determinístico)
- `tutor-fiscal-base-v1` → `BASE` — trechos indexados dos PDFs enviados (RAG local)

## Chamadas à API Anthropic

6 pontos de `fetch("https://api.anthropic.com/v1/messages")` no arquivo, todos usando **`model:"claude-sonnet-5"`**. Cada um (exceto avaliação de discursiva, que é sempre única) verifica cache antes de gastar token — ver tabela de funções abaixo.

| Função | Linha aprox. | Cacheável? | Chave de cache |
|---|---|---|---|
| `gerarCardIA` | 897 | Sim | `S.cards[discId+'\|'+topico]` |
| `gerarEsquemaIA` | 1156 | Sim | `CACHE.esq[disc+'\|'+topico]` |
| `gerarTrilhaPDF` | 2729 | Sim | `S.trilhaTopicos[discId]` |
| `gerarCasoIA` | 3120 | Sim (lotes de 3) | `CACHE.casos` via `chaveCaso()` |
| `novoCasoDiscursivo` | 3184 | Sim | `CACHE.disc` (array, últimos 10) |
| `avaliarDiscursiva` | 3254 | **Não** — cada resposta do aluno é única, correto não cachear | — |

## Histórico de trabalho nesta sessão (2026-08-02)

1. Ativadas skills do Claude Code nesta pasta (`.claude\skills`, via `activate-skills.ps1`).
2. Auditoria de economia de tokens: confirmado que o app já tinha boa arquitetura de cache; corrigidos 2 gaps reais:
   - `gerarTrilhaPDF` não verificava cache antes de chamar IA → corrigido.
   - `gerarTrilhaPDF` e `avaliarDiscursiva` não incrementavam `CACHE.meta.chamadas` → painel de métricas estava subestimando uso real → corrigido.
3. Modelo atualizado de `claude-sonnet-4-6` (válido, mas geração anterior) → `claude-sonnet-5` (preço promocional até 31/08/2026 + qualidade melhor) nas 6 chamadas.
4. Instalação simplificada: removidas as pastas `TutorFiscal-Setup\` (instalador .exe com aviso do SmartScreen) e `tutor-fiscal-instalacao\` (PWA via GitHub Pages) — mantida só `tutor-fiscal-windows\` (extrair pasta + duplo clique no `.bat`).
5. `tutor-fiscal-windows\index.html` estava desatualizado em relação ao fonte — sincronizado com as correções dos itens 2–3.
6. **Bug real encontrado e corrigido**: `Iniciar Tutor Fiscal.bat` tinha caracteres especiais (travessão "—", linhas "═") salvos sem BOM — `cmd.exe` lia pela codificação OEM errada e cuspia erros de "comando não reconhecido" toda vez que o app abria (funcionava, mas com erros visíveis feios). Corrigido trocando por ASCII puro (`-`, `=`). Testado rodando o `.bat` de verdade duas vezes (antes/depois) via PowerShell — segunda execução limpa, Chrome abriu com o título correto "Tutor Fiscal — AuDHD".

## Contexto importante

- **Outra sessão/processo** parece estar construindo este app em paralelo — os arquivos apareceram nesta pasta entre 11:58 e 16:09 do mesmo dia sem que esta sessão os tivesse criado. Não assumir que o estado do disco é só o que esta sessão fez.
- Sem framework, sem bundler, sem `package.json` — é HTML+CSS+JS puro num arquivo só. Edições são via busca-e-substituição de trechos exatos.
- Chave de API Anthropic fica salva só no navegador do usuário (`S.apiKey`), nunca commitada em lugar nenhum.
- Não existe teste automatizado. Verificação é manual: rodar o `.bat`, ou abrir o `index.html` direto no navegador.

## O que não foi verificado / possíveis próximos passos

- Não foi possível inspecionar o console JS nem interagir com os botões da janela aberta pelo `.bat` nesta sessão (limitação das ferramentas de browser disponíveis — Browser da sessão só faz snapshot estático de arquivos fora do projeto; extensão Claude in Chrome não estava conectada). Se quiser um teste funcional mais profundo (clicar em abas, gerar um card, etc.), conectar a extensão Claude in Chrome primeiro.
- Nenhuma funcionalidade de geração de **imagens** por IA existe no app — se isso for um requisito futuro, é feature nova, não otimização do que já existe.
