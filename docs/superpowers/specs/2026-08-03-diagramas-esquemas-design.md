# Design — Subsistema de Diagramas e Esquemas (Tutor Fiscal)

**Status:** aprovado pelo usuário em brainstorming, pronto para virar plano de implementação.
**Escopo:** subprojeto 1 de 7 na decomposição do app (ver `docs/handoff/2026-08-03-diagramas-esquemas-handoff.md`). Cobre a **Ficha Visual / Estúdio de Diagramas** — não cobre Base de Conhecimento, Cards de Lei, Banco de Questões, Trilha, Discursiva ou Painel, exceto onde a interface entre eles é citada explicitamente.

---

## 1. Contexto e motivação

O Tutor Fiscal é um app de estudo para concursos fiscais, single-file HTML+CSS+JS (`Programa/tutor-fiscal.html`), construído sobre a Teoria da Carga Cognitiva de Sweller para perfil AuDHD/TPAC. Diagramas e esquemas visuais são um recurso central — a tese do app é que visualização reduz carga extrínseca — mas o subsistema atual não entrega isso na prática.

### Diagnóstico (validado ao vivo, não só por leitura de código)

Testado rodando o app de verdade (servidor local), processando dois PDFs reais de Contabilidade fornecidos pelo usuário (`00.pdf`, 33 pág. → 69 trechos; `01.pdf`, 40 pág. → 81 trechos + 21 questões extraídas) através do pipeline real (`processarPDFs` → `recuperarTrechos` → `detectarTipo` → `gerarSVG`).

1. **Cobertura quase nula.** 3 de 131 tópicos (23 disciplinas) têm Ficha Visual pronta (`FICHAS`, tutor-fiscal.html ~L1445).
2. **Base de Conhecimento não escala** para o uso pretendido (múltiplos PDFs simultâneos). Teto de 3,5 MB de texto (`LIMITE_TOTAL`, ~L2534) compartilhado por todas as disciplinas; ao estourar, descarta os PDFs mais antigos silenciosamente. Fora de escopo consertar aqui (subprojeto 2), mas **este design assume que a base vai crescer** e não depende de nenhuma melhoria nela para funcionar.
3. **Causa raiz do resultado pobre:** os 5 moldes offline (`svgSequencia/svgPropriedades/svgComparacao/svgCascata/svgMapa`, ~L1035-1152) só reconhecem estrutura já organizada no texto (listas, "termo: definição", "A x B"). Texto puro extraído de PDF é parágrafo corrido, então `detectarTipo` (~L1024) cai sempre no fallback "sequência", que corta frases no meio de forma ilegível. Reprodução gravada: tópico "Patrimônio e equação contábil", resultado real em `docs/handoff/2026-08-03-diagramas-esquemas-handoff.md` §3.
4. **Dois formatos de conteúdo incompatíveis.** `FICHAS` (objeto estático, escrito à mão, mistura prosa + SVG + caixas de destaque) e `S.fichasUser` (dinâmico, gerado pelo Estúdio, guarda só `{titulo, svg}`) não têm o mesmo poder expressivo — por isso as 3 fichas manuais parecem muito melhores que qualquer coisa que o Estúdio gera hoje. Essa lacuna, mais do que qualquer bug pontual, é o que faz o recurso parecer quebrado.

### Restrição pedagógica adicional

O usuário forneceu um guia teórico (`Teoria da Carga Cognitiva BNCC.pdf`) que orienta como IA deve gerar conteúdo neste app. Partes vinculantes para este subsistema:

- **Single-Card View** (Regra 2): conceito, diagrama e exemplo numa unidade visual só — nunca telas separadas, nunca legendas distantes.
- **Linguagem direta**: sem introdução, sem floreio, começa pela regra central.
- **Código de cor semântico fixo** (Regra 3, *Signaling Effect*): `<core>` verde = regra/conceito-chave · `<alert>` âmbar/vermelho = atenção/exceção/erro comum · `<anchor>` azul = termo técnico/âncora de memória. Hoje o app inteiro (fichas manuais incluídas) usa verde/âmbar como "primário/secundário" genérico — isso é uma violação a corrigir, não uma preferência estética.
- **Limites rígidos:** ≤ 40 palavras por parágrafo, ≤ 150 palavras por unidade de tela.
- **Foco do design:** funcionalidade e clareza acima de decoração — "neutralidade visual" para não sobrecarregar (relevante especialmente a TSA). **Confirmado com o usuário:** "qualidade visual máxima" (prioridade #1 deste redesenho) significa hierarquia e tipografia bem executadas, não ornamento.

## 2. Prioridade e trade-offs assumidos

Decisão do usuário: **qualidade visual máxima quando a IA gera o conteúdo** é a prioridade — não cobertura ampla, não robustez do caminho sem-IA. Consequência assumida conscientemente: o caminho manual/offline continua limitado; não investimos em heurísticas de detecção de estrutura em texto cru (ver §6).

Abordagem escolhida entre três propostas (A: só ampliar moldes atuais · B: esquema estruturado rico + motor de composição novo · C: IA gera SVG bruto direto): **B**, por manter segurança/previsibilidade de um contrato estruturado e cacheável, sem o teto visual dos moldes rígidos atuais nem o risco de markup arbitrário de C.

## 3. Modelo de dados unificado — `Ficha`

Substitui `FICHAS` (estático) e `S.fichasUser` (dinâmico) por uma única estrutura, guardada em `S.fichas` (chave `discId+'|'+topico`, mesma convenção de `chaveFicha` hoje):

```js
Ficha = {
  titulo: string,
  discId: string,
  topico: string,
  origem: 'manual' | 'ia' | 'legado',   // 'legado' = migrado das 3 FICHAS atuais
  conceito: string,                      // regra central, direto, ≤40 palavras
  porQueCai: string[],                   // 1-2 pontos; pode ficar vazio nas 'legado' até serem revisadas
  diagrama: Esquema,                     // ver §4
  exemplo: { entrada: string, passos: string[] } | null,
  verificacao: { pergunta: string, resposta: 'certo'|'errado' } | null,
  quando: number                         // timestamp
}
```

**Migração:** as 3 fichas manuais existentes (`port|Regência e crase`, `cont|DRE e regime de competência`, `port|Interpretação de texto`) são convertidas para este formato com `origem:'legado'`. O SVG e o texto explicativo de cada uma viram os campos `diagrama`/`conceito`/`exemplo` na medida do possível; `porQueCai` e `verificacao` ficam ausentes até alguém preencher — a ausência não impede a renderização (ver §7, tratamento de erro).

`temFicha(discId, topico)` e `abrirFicha(discId, topico)` passam a consultar só `S.fichas[chave]`, eliminando o `if (FICHAS[k]) ... else if (S.fichasUser[k])` atual.

## 4. Contrato estruturado que a IA retorna — `Esquema`

Substitui o contrato atual (`{tipo, titulo, linhas: string[]}`, usado por `gerarEsquemaIA` ~L1156) por nós e relações explícitos:

```js
Esquema = {
  layout: 'equacao' | 'fluxo' | 'comparacao' | 'linha_tempo' | 'hierarquia' | 'cascata',
  nos: [
    { id: string, texto: string, papel: 'core' | 'anchor' | 'alert' }
  ],
  relacoes: [
    { de: string, para: string, tipo: 'soma'|'resulta_em'|'opoe'|'contem', rotulo?: string }
  ]
}
```

- `papel` em cada nó mapeia diretamente para a cor semântica do guia (`core`→verde, `anchor`→azul, `alert`→âmbar/vermelho) — a cor deixa de ser decidida pelo motor de renderização e passa a vir da própria estrutura do conteúdo.
- `layout` é uma dica de composição para o motor (§5), não mais um molde rígido de caixas-em-fileira: o motor tem liberdade de espaçamento/agrupamento dentro de cada tipo de layout.
- Os seis valores de `layout` cobrem os casos reais do domínio (fiscal/contábil/jurídico): equação (Ativo=Passivo+PL), fluxo de decisão com ramos, comparação de dois lados, prazo/linha do tempo, hierarquia/organograma, cascata de subtrações sucessivas (DRE). Substitui e amplia os 5 tipos atuais (`sequencia/mapa/propriedades/comparacao/cascata`).
- O prompt para `gerarEsquemaIA` é reescrito para pedir este JSON, mais os campos `conceito`, `porQueCai`, `exemplo`, `verificacao` da `Ficha` (§3) na mesma chamada — uma chamada de IA por ficha completa, não uma chamada por diagrama solto.
- Cache: mantém a mesma estratégia atual (`CACHE.esq[disc|topico]`), mas passa a cachear a `Ficha` completa, não só o esquema.

## 5. Motor de composição SVG

Substitui as 5 funções `svgXxx()` (~L1035-1152) por:

- **Tokens de design** centralizados: cor por papel semântico (`core`/`anchor`/`alert` + neutros de texto/fundo), escala tipográfica (título/rótulo/corpo — 3 tamanhos, não mais valores de `font-size` soltos por função), espaçamento consistente.
- **Tema claro/escuro nativo.** Hoje as cores são hex fixos embutidos no SVG (não reagem ao tema escuro do app, incluindo nas 3 fichas manuais). Os tokens usam as variáveis de tema do app já existentes (mesmo padrão de `P.tinta`/`P.verde` etc., mas redefinidas por tema, igual ao restante da UI).
- **Uma função de composição por `layout`** (6 funções, uma por valor do enum), recebendo `nos`+`relacoes` genéricos em vez de linhas de texto cru. Cada função:
  - dimensiona caixas pelo conteúdo real (não larguras fixas arbitrárias);
  - quebra texto respeitando o limite de 40 palavras por nó, truncando com reticências além disso em vez de cortar no meio de uma frase visível;
  - aplica a cor do `papel` de cada nó via os tokens.
- **Fallback seguro.** `layout` desconhecido, `nos` vazio ou malformado → composição cai num layout de lista simples (cada nó vira uma linha, sem tentar adivinhar relação) — nunca lança exceção nem deixa a tela em branco.

## 6. Mudanças na UI do Estúdio (`screen-estudio`)

O caminho manual/sem-IA não é a prioridade (§2), então é simplificado em vez de reforçado:

- Remove a dependência de `detectarTipo`/"Só detectar a estrutura do texto acima (sem IA)" como fluxo principal — é essa heurística que falha com texto cru de PDF (causa raiz #3 do diagnóstico).
- No lugar, edição manual passa a ser campo-a-campo sobre a própria `Ficha` (conceito, nós do diagrama, exemplo, verificação) — mais trabalho de digitação, mas resultado previsível, sem parsing frágil de texto livre.
- O botão "Montar esquema com IA" permanece como está hoje conceitualmente (chama a IA, preenche os campos), só que agora preenche uma `Ficha` inteira, não só um SVG solto.
- Pré-visualização (`est-preview`) passa a renderizar a `Ficha` completa (igual ao que `abrirFicha` mostra), não só o SVG.

## 7. Tratamento de erros

| Situação | Comportamento |
|---|---|
| IA retorna JSON inválido ou incompleto | Mantém a mensagem de erro atual ("Não consegui interpretar o material..."); nada é cacheado em caso de falha (comportamento já existente, preservado). |
| `layout` desconhecido / `nos` malformados | Fallback para layout de lista simples (§5) — nunca quebra a tela. |
| `Ficha` sem `porQueCai` ou `verificacao` (ex.: as 3 legadas) | Bloco correspondente simplesmente não é renderizado — não é obrigatório na exibição, só recomendado na geração. |
| Texto de qualquer campo excede o limite de palavras | Trunca com reticências no limite; não bloqueia salvamento nem geração. |
| Upload de PDF sem texto extraível, falha de rede etc. | Fora de escopo — comportamento já existente em `processarPDFs`, não alterado por este subsistema. |

## 8. Plano de verificação

1. Reexecutar o mesmo teste ao vivo desta sessão de brainstorming — os dois PDFs reais de Contabilidade, tópico "Patrimônio e equação contábil" — e comparar o resultado com o mockup aprovado (composição "A · Ficha ampliada", ver artefato citado no handoff).
2. Checklist de conformidade com o guia de Carga Cognitiva como critério de aceite: Single-Card View respeitada, cor semântica correta por `papel`, limites de 40/150 palavras respeitados, "por que cai" e verificação presentes quando gerados por IA.
3. Migração das 3 fichas manuais verificada visualmente (nada quebra, `origem:'legado'` renderiza sem os campos opcionais).
4. Teste do fallback: forçar um `layout` desconhecido e um `nos` vazio, confirmar que não há exceção nem tela em branco.
5. Sem framework de teste automatizado no projeto (confirmado em `CLAUDE.md`) — verificação continua manual, abrindo o `.html` real e testando os fluxos acima.

## 9. Fora de escopo (fica para subprojetos seguintes)

- Aumentar o teto de 3,5 MB ou melhorar o ranking de `recuperarTrechos` — subprojeto 2 (Base de Conhecimento).
- Regras 1 (Pareto 80/20 por nível A/B/C), 4 (worked examples/fading) e o algoritmo de SRS do guia de Carga Cognitiva — não são específicas de diagramas, relevantes para os subprojetos de Trilha/Revisão.
- Geração de áudio sincronizado (*text-to-speech visual cueing*, Regra 3 do guia) — não existe em nenhuma parte do app hoje; é feature nova, não deste subsistema.
