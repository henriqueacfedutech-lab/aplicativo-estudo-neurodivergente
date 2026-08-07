# Handoff — Redesenho do subsistema de Diagramas e Esquemas

**Status:** SUPERADO por `docs/superpowers/specs/2026-08-05-diagramas-esquemas-base-conhecimento-design.md` — sessão continuada em outro dispositivo fundiu este subprojeto com Base de Conhecimento e migrou a arquitetura pra Supabase (motivo: possível venda do app para empresa). Este arquivo fica só como registro histórico do diagnóstico original. Leia o spec de 05/08 e seus 5 planos em `docs/superpowers/plans/2026-08-05-*.md` antes de continuar qualquer trabalho de diagramas.

> **Atualização (sessão seguinte):** app publicado no GitHub Pages — **https://henriqueacfedutech-lab.github.io/aplicativo-estudo-neurodivergente/** (branch `gh-pages`, atualiza sozinha a cada push nela; código-fonte fica em `master`). PWA instalável no Android via "Adicionar à tela inicial". Repo: `github.com/henriqueacfedutech-lab/aplicativo-estudo-neurodivergente`, público.
>
> **Prioridade explícita do usuário:** ele precisa começar a estudar logo — segue usando o app publicado (já funcional: cards, questões, ciclo, revisão) enquanto a reforma de Diagramas/Base de Conhecimento continua em paralelo, **sem pressa artificial**. Não tratar o spec de 05/08 como bloqueante para o uso do app.
>
> **Revisão do spec de 05/08 — respostas coletadas (faltava só isso pro "usuário revisa" formal):**
> - Fichas manuais legadas (Regência e crase, DRE, Interpretação de texto): **descartar** — não migrar, deixar a IA regerar quando esses tópicos forem acessados no novo sistema.
> - Método de login Supabase Auth: **e-mail + senha** (não magic link).
> - Motivo de negócio (possível venda do app pra empresa) que justifica RLS multi-tenant desde o início: **confirmado, ainda válido**.
> - Custo operacional do Supabase (não discutido no spec original): **não é bloqueio agora** — usuário quer um modelo real funcionando primeiro, avalia custo depois se virar problema.
>
> Com essas 4 respostas, o spec de 05/08 está formalmente revisado e pronto pra virar trabalho de implementação (os 5 planos já escritos) — só falta decidir *quando* retomar, dado que não há pressa.
**Onde parou:** aguardando reação do usuário aos mockups visuais (link abaixo). Ele vai continuar pelo celular, então qualquer sessão nova (desktop ou mobile) deve ler este arquivo primeiro.
**Ler também:** `../../CLAUDE.md` (contexto geral do app, sempre a fonte de verdade sobre onde tudo está).

---

## 1. Como isso começou

Pedido original: "reestruturar todo o aplicativo" porque os diagramas/esquemas "não funcionam, ou carecem de organização e resultado". Segui a skill `brainstorming` (dentro de `using-superpowers`): explorei o projeto, decompus o pedido em subprojetos, e fui fundo só no primeiro.

## 2. Decisões já tomadas (não reabrir sem motivo novo)

| Pergunta | Decisão do usuário |
|---|---|
| Escopo | "App inteiro" é grande demais pra uma sessão — decompor em subprojetos (tabela abaixo), desenhar só o primeiro agora. |
| Base de Conhecimento (RAG local) vs. Diagramas — qual primeiro? | Diagramas agora, mas **o design já deve assumir uma base com muitos PDFs simultâneos** (retrieval robusto, mais controle manual). Base de Conhecimento é o subprojeto seguinte. |
| Prioridade #1 do motor de diagramas | **Qualidade visual máxima quando usa IA** (não cobertura ampla, não robustez sem-IA). Aceito que o caminho sem IA continua limitado. |
| Abordagem arquitetural | **Aprovada: "B" — IA compõe um esquema estruturado mais rico (nós, relações, ênfases, texto de apoio) → motor de composição SVG novo com tokens de design (tipografia, cor semântica, tema claro/escuro nativo).** Descartadas: "A" (só ampliar os 5 moldes atuais) e "C" (IA gera SVG bruto direto — teto mais alto mas imprevisível e arriscado). |

### Decomposição completa do app (subprojetos futuros, nesta ordem de prioridade)

1. **Diagramas e Esquemas** ← em andamento agora
2. **Base de Conhecimento (RAG local, multi-PDF)** — infraestrutura compartilhada por 1, 3, 4 e 5
3. **Cards de Lei Seca**
4. **Banco de Questões e Revisão**
5. **Trilha e Ciclo de Estudo**
6. **Discursiva**
7. **Painel, Backup e Sincronização**

## 3. Diagnóstico — por que os diagramas não entregam resultado

Validado **rodando o app de verdade** (não só lendo código), com os dois PDFs de contabilidade que o usuário enviou (`00.pdf` 33 pág. → 69 trechos, `01.pdf` 40 pág. → 81 trechos + 21 questões extraídas), processados via `processarPDFs()` real dentro do app servido localmente.

1. **Cobertura quase nula:** 3 de 131 tópicos (23 disciplinas) têm Ficha Visual pronta.
2. **Base de Conhecimento não escala:** teto de 3,5 MB de texto (`LIMITE_TOTAL`, tutor-fiscal.html linha ~2534) compartilhado por **todas** as disciplinas; ao estourar, descarta os PDFs mais antigos sem avisar. Retrieval é busca por palavra-chave simples (`recuperarTrechos`), sem ranking semântico.
3. **O molde offline espera texto que PDF nunca entrega:** os 5 moldes (`sequência/mapa/propriedades/comparação/cascata`, linha ~1008) só reconhecem estrutura já organizada (listas, "termo: definição"). Texto puro extraído de PDF é parágrafo corrido → cai sempre no molde de fallback "sequência", cortando frases no meio. Reprodução ao vivo (tópico "Patrimônio e equação contábil", sem nenhuma chamada de IA): **https://claude.ai/code/artifact/ad84d551-0a28-4480-89db-c7e55dd8d0fc**
4. **Duplicação de modelo de conteúdo:** `FICHAS` (estático, feito à mão, mistura prosa + SVG + caixas de destaque) vs. `S.fichasUser` (dinâmico, só um SVG solto) são dois formatos incompatíveis — é por isso que as 3 fichas manuais parecem muito melhores que qualquer coisa que o Estúdio gera hoje.

## 4. Restrição nova e importante: guia de Carga Cognitiva (BNCC)

O usuário trouxe `Teoria da Carga Cognitiva BNCC.pdf` (estava em Downloads — **vale copiar para dentro do projeto**, ex. `docs/referencia/carga-cognitiva-bncc.pdf`, porque Downloads é uma pasta transitória) como guia teórico-pedagógico que deve orientar o app inteiro, não só diagramas. Pontos que afetam diretamente o motor de diagramas:

- **Single-Card View** (Regra 2): conceito, diagrama e exemplo numa unidade visual só, nunca espalhados. → Já respeitado nos mockups.
- **Código de cor semântico fixo e obrigatório** — isto é uma correção real, não estética: `<core>` verde = regra/conceito-chave · `<alert>` âmbar/vermelho = atenção/exceção/pegadinha · `<anchor>` azul = termo técnico/âncora de memória. **O app inteiro hoje (as 3 fichas manuais inclusive) usa verde/âmbar como "primário/secundário" genérico, o que viola esse código.** Corrigido nos mockups v2 (ver artefato).
- **Estrutura de card do guia (Template 1)** inclui dois blocos que faltam em tudo que existe hoje: *"por que isso cai"* (1-2 pontos de relevância pra prova) e *"verificação rápida"* (pergunta certo/errado de 10s). Incorporados no mockup v2.
- **Limites rígidos:** ≤40 palavras/parágrafo, ≤150 palavras por unidade de tela, bloco de estudo ≤5 min ou 3 cards/sessão.
- **Tensão a vigiar:** o guia pede *"funcionalidade sobre estética decorativa, neutralidade visual"* — interpretação acordada implicitamente pela reação do usuário aos mockups (ainda não confirmada explicitamente): "qualidade visual máxima" = clareza e hierarquia bem executadas, **não** ornamentação. Confirmar isso com o usuário antes de fechar a seção de design sobre isso.
- Regras 1 (Pareto 80/20, níveis A/B/C), 4 (worked examples/fading) e a seção 5 (algoritmo de SRS) **não são específicas de diagramas** — relevantes para os subprojetos 4/5 mais à frente. Não resolver agora, só não esquecer.

## 5. Mockups mostrados — status: aguardando reação

Dois rounds de mockup, com conteúdo real (tópico "Patrimônio e equação contábil", extraído dos PDFs enviados):

- **v1**: comparação de composição — "A · Ficha ampliada" (texto guia + diagrama + exemplo em caixa) vs. "B · Cartão-diagrama" (diagrama é o protagonista, quase sem prosa).
- **v2**: versão corrigida contra o guia de Carga Cognitiva — cor semântica certa (verde só na regra, azul nos termos técnicos, âmbar só no "erro comum"), mais os blocos "por que cai" e "verificação rápida".

Isso foi mostrado primeiro via companheiro visual (servidor local `brainstorming/scripts/start-server.sh`, sessão em `.superpowers/brainstorm/827-1785713917/` — **esse servidor já parou** e não é acessível de outro dispositivo/rede, foi por isso que o usuário não conseguiu ver). Republiquei os dois rounds como Artifact, que funciona em qualquer dispositivo com o link:

**https://claude.ai/code/artifact/e49fd575-1088-428e-aa20-fb92bdcbc559**

### Respondido (2026-08-03, sessão mobile)

1. Composição: **A — Ficha ampliada** (texto curto guia + diagrama ilustra + exemplo em caixa de destaque).
2. Blocos novos da v2: **manter os dois** ("por que isso cai" e verificação rápida certo/errado).
3. "Qualidade visual máxima" confirmado = **clareza e hierarquia, não decoração/ornamento** — alinhado ao guia de Carga Cognitiva.

Design segue agora pra modelo de dados unificado + contrato JSON da IA + motor de composição SVG (checklist §6).

## 6. Próximos passos (retomar aqui a skill `brainstorming`)

Ainda dentro do checklist da skill, faltam:

1. Coletar a reação aos mockups (pergunta acima) — **isso ainda é parte de "propor abordagens / refinar", não avançar sem isso**.
2. Fechar o modelo de dados unificado: um único formato de "ficha" (funde `FICHAS` estático + `S.fichasUser`) com os campos do Template 1 do guia (conceito central, por-que-cai, exemplo, verificação) + o diagrama.
3. Definir o contrato JSON que a IA retorna (esquema estruturado: nós, relações, ênfases — não mais "tipo fixo + 7 linhas").
4. Especificar o motor de composição SVG novo (tokens de design: tipografia, cor semântica `<core>/<alert>/<anchor>`, layout, tema claro/escuro).
5. Apresentar as seções restantes do design (arquitetura, tratamento de erro, plano de teste/verificação) uma a uma, com aprovação a cada seção.
6. Escrever o spec em `docs/superpowers/specs/2026-08-0X-diagramas-esquemas-design.md` (ainda não existe).
7. Auto-revisão do spec (placeholders, contradições, ambiguidade, escopo).
8. Usuário revisa o spec escrito.
9. Só então invocar a skill `writing-plans` — nenhuma outra skill de implementação antes disso.

## 7. Notas técnicas / limpeza

- Servidores HTTP locais de teste (portas 8843 e 8844, usados pra rodar o app de verdade fora da sandbox padrão) **já caíram sozinhos** — não precisam ser encerrados.
- `C:\Users\henri\Documents\musicas-ia\.claude\launch.json` tem duas entradas (`tutor-fiscal`, `tutor-fiscal-test`) apontando pra esses servidores de teste — ficaram órfãs, apagáveis, não pertencem a esse projeto (musicas-ia é outro projeto do usuário, sem relação).
- Cópias de teste do app e dos PDFs ficaram em scratchpad de sessão (`.../scratchpad/tutor-fiscal-test.html`, `00.pdf`, `01.pdf`) — não fazem parte do projeto, não precisam ser versionadas.
- `Teoria da Carga Cognitiva BNCC.pdf` continua só em Downloads — recomendação pendente de copiar para dentro do projeto (ver seção 4).
- Para visual companion em sessões futuras: **preferir publicar como Artifact em vez de servidor local** sempre que houver risco de troca de dispositivo/rede — é o que resolveu o problema de visualização desta sessão.
