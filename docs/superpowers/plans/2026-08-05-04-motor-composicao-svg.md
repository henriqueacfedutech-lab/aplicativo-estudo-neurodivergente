# Motor de Composição SVG (Plano 4/5) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Renderizar `diagrama_schema` (JSON produzido por `gerarFichaIA`, Plano 3) em SVG, com tokens de design fixos (tipografia, cor semântica `core`/`alert`/`anchor`/`neutro`, tema claro/escuro nativo), substituindo a limitação dos 5 moldes antigos que só entendiam texto já organizado (spec, Seção 7).

**Architecture:** Um dispatcher (`renderDiagramaSVG(schema)`) escolhe um entre 5 renderers conforme `schema.layout` (`sequencia`/`hierarquia`/`comparacao`/`ciclo`/`mapa`), cada um consumindo só `schema.nos` (`{id, texto, enfase}`) e `schema.relacoes` (`{de, para, rotulo}`) — nenhum renderer lê texto bruto, só o schema estruturado. Este motor **não substitui** `gerarSVG`/`svgSequencia` etc. (linhas ~1035-1152, o Estúdio de Diagramas offline antigo) — são dois motores paralelos; o antigo continua servindo o Estúdio manual, o novo serve as fichas geradas por IA (ligação feita no Plano 5).

**Tech Stack:** JS vanilla, SVG inline (mesmo padrão do motor antigo), reaproveitando `esc()` e `quebrar()` já existentes (linhas ~1013, ~1018).

## Global Constraints

(herdadas dos planos anteriores, mais:)

- Cor semântica **fixa e obrigatória**, nunca "primário/secundário" genérico: `core`=verde (regra/conceito-chave), `alert`=âmbar (atenção/exceção), `anchor`=azul (termo técnico), `neutro`=cinza (default se a IA não classificar) — spec, Seções 4 e 7.
- Tema claro/escuro: o motor **antigo não suporta** tema escuro hoje (paleta `P`, linha 1010, é `const` fixa) — isso é uma melhoria real deste motor novo, não reaproveita nada do antigo nesse ponto. Detectar o tema ativo via `document.documentElement.getAttribute('data-tema')` (já setado por `aplicarTema()`, linha ~3346), não reimplementar a lógica de `auto`/`prefers-color-scheme`.
- Tipografia em 3 níveis fixos (título do diagrama, rótulo de nó, texto de apoio) — tamanhos fixos em tokens, nunca escolha livre da IA (spec, Seção 7).

---

### Task 1: Tokens de design e dispatcher de layout

**Files:**
- Modify: `Programa/tutor-fiscal.html` (nova seção `/* ═══ MOTOR DE COMPOSIÇÃO SVG (fichas por IA) ═══ */`, inserida logo após a seção `ESTÚDIO DE DIAGRAMAS` existente, antes de `BANCO DE QUESTÕES` — linha ~1267 no mapa atual)

**Interfaces:**
- Consumes: `esc()`, `quebrar()` (código existente, linhas ~1013/1018), `document.documentElement` `data-tema` (setado por `aplicarTema()`)
- Produces: `function corEnfase(enfase)` → `{fill, stroke, ink}`; `function renderDiagramaSVG(schema)` → string SVG. **Esta é a função que o Plano 5 chama pra desenhar a Tela 1 do card.**

- [ ] **Step 1: Adicionar os tokens e o dispatcher**

```js
/* ═══ MOTOR DE COMPOSIÇÃO SVG (fichas por IA) ═══
   Consome diagrama_schema (nos + relacoes), não texto bruto — resolve o problema
   do motor antigo (linha ~1008) que só entendia texto já organizado.
   Paralelo ao motor antigo: este serve as fichas de gerarFichaIA (Plano 3),
   o antigo continua servindo o Estúdio manual sem IA. */
const TOKENS_DIAGRAMA = {
  claro: {
    fundo:'#FFFFFF', tinta:'#26282B', tinta3:'#8A8D91', linha:'#E4E2DB',
    core:   {fill:'#E8F1EC', stroke:'#1D6A55', ink:'#0F4235'},
    alert:  {fill:'#F7EEDC', stroke:'#B07A1B', ink:'#6B4A0E'},
    anchor: {fill:'#E7EBF2', stroke:'#3C5A99', ink:'#1F3763'},
    neutro: {fill:'#F4F3EF', stroke:'#C9C6BC', ink:'#26282B'}
  },
  escuro: {
    fundo:'#1B1D1F', tinta:'#EDEEEF', tinta3:'#8A8D91', linha:'#33363A',
    core:   {fill:'#123328', stroke:'#3FA486', ink:'#B7E4D3'},
    alert:  {fill:'#3A2C0E', stroke:'#D6A146', ink:'#F0D9A6'},
    anchor: {fill:'#1E2A3F', stroke:'#6E93D6', ink:'#C7D6F0'},
    neutro: {fill:'#2A2C2F', stroke:'#4A4D51', ink:'#EDEEEF'}
  }
};
const TIPOGRAFIA_DIAGRAMA = { titulo:14, no:12, apoio:10 };

function temaAtivoDiagrama(){
  return document.documentElement.getAttribute('data-tema')==='escuro' ? 'escuro' : 'claro';
}
function corEnfase(enfase){
  const T = TOKENS_DIAGRAMA[temaAtivoDiagrama()];
  return T[enfase] || T.neutro;
}
function renderDiagramaSVG(schema){
  if(!schema || !schema.nos || !schema.nos.length) return '<p class="sub">Sem diagrama para exibir.</p>';
  const renderers = {
    sequencia: svgSchemaSequencia, hierarquia: svgSchemaHierarquia,
    comparacao: svgSchemaComparacao, ciclo: svgSchemaCiclo, mapa: svgSchemaMapa
  };
  const fn = renderers[schema.layout] || svgSchemaSequencia;
  return fn(schema);
}
```

- [ ] **Step 2: Verificação manual**

No console do navegador: `corEnfase('core')` deve retornar `{fill:'#E8F1EC', stroke:'#1D6A55', ink:'#0F4235'}` no tema claro. Trocar tema pra escuro em Ajustes e repetir — cores devem mudar mas o significado semântico continuar (verde ainda é `core`). `renderDiagramaSVG({nos:[]})` deve retornar a mensagem "Sem diagrama para exibir." sem lançar erro (os 5 renderers ainda não existem, mas isso não é chamado neste caso).

- [ ] **Step 3: Commit**

```bash
git add "Programa/tutor-fiscal.html"
git commit -m "feat: tokens de design e dispatcher do motor de composicao SVG"
```

---

### Task 2: Os 5 renderers de layout

**Files:**
- Modify: `Programa/tutor-fiscal.html` (mesma seção, logo após o dispatcher)

**Interfaces:**
- Consumes: `corEnfase`, `TOKENS_DIAGRAMA`, `TIPOGRAFIA_DIAGRAMA`, `temaAtivoDiagrama` (Task 1), `esc`, `quebrar` (existentes)
- Produces: `svgSchemaSequencia`, `svgSchemaHierarquia`, `svgSchemaComparacao`, `svgSchemaCiclo`, `svgSchemaMapa` — cada uma recebe `schema` (`{layout, titulo, nos, relacoes}`) e retorna string SVG. Chamadas só pelo dispatcher `renderDiagramaSVG` (Task 1), nunca diretamente pelo Plano 5.

- [ ] **Step 1: `svgSchemaSequencia` — lista vertical conectada, ordem = ordem de `nos`**

```js
function svgSchemaSequencia(schema){
  const T = TOKENS_DIAGRAMA[temaAtivoDiagrama()];
  const nos = schema.nos.slice(0,8);
  const alt=62, top=58, larg=560;
  const h = top + nos.length*alt + 24;
  let sv = `<svg viewBox="0 0 600 ${h}" role="img" aria-label="${esc(schema.titulo||'')}"><rect width="600" height="${h}" fill="${T.fundo}"/>
    <text x="24" y="30" font-family="'JetBrains Mono',monospace" font-size="${TIPOGRAFIA_DIAGRAMA.apoio}" letter-spacing="1" fill="${T.tinta3}">SEQUÊNCIA</text>
    <text x="24" y="48" font-family="'Atkinson Hyperlegible',sans-serif" font-size="${TIPOGRAFIA_DIAGRAMA.titulo}" font-weight="700" fill="${T.tinta}">${esc(schema.titulo||'')}</text>`;
  nos.forEach((no,i)=>{
    const y = top + i*alt;
    const cor = corEnfase(no.enfase);
    sv += `<rect x="24" y="${y}" width="${larg}" height="46" rx="6" fill="${cor.fill}" stroke="${cor.stroke}"/>
      <circle cx="46" cy="${y+23}" r="12" fill="${cor.stroke}"/>
      <text x="46" y="${y+27}" text-anchor="middle" font-family="'JetBrains Mono',monospace" font-size="12" font-weight="700" fill="${T.fundo}">${i+1}</text>`;
    quebrar(no.texto, 62).slice(0,2).forEach((l,k)=>{
      sv += `<text x="70" y="${y+20+k*16}" font-family="'Atkinson Hyperlegible',sans-serif" font-size="${TIPOGRAFIA_DIAGRAMA.no}" fill="${cor.ink}">${esc(l)}</text>`;
    });
    if(i<nos.length-1) sv += `<line x1="46" y1="${y+46}" x2="46" y2="${y+alt}" stroke="${T.linha}" stroke-width="2"/>`;
  });
  return sv + '</svg>';
}
```

- [ ] **Step 2: `svgSchemaHierarquia` — níveis por BFS a partir da raiz (nó sem pai em `relacoes`)**

```js
function svgSchemaHierarquia(schema){
  const T = TOKENS_DIAGRAMA[temaAtivoDiagrama()];
  const nos = schema.nos;
  const filhosDe = {};
  (schema.relacoes||[]).forEach(r=>{ (filhosDe[r.de]=filhosDe[r.de]||[]).push(r.para); });
  const temPai = new Set((schema.relacoes||[]).map(r=>r.para));
  const raiz = nos.find(n=>!temPai.has(n.id)) || nos[0];

  const niveis = [[raiz.id]];
  const visitados = new Set([raiz.id]);
  let atual = [raiz.id];
  while(atual.length){
    const proximo = [];
    atual.forEach(id=>(filhosDe[id]||[]).forEach(fid=>{ if(!visitados.has(fid)){ visitados.add(fid); proximo.push(fid); } }));
    if(proximo.length){ niveis.push(proximo); atual=proximo; } else break;
  }
  nos.forEach(n=>{ if(!visitados.has(n.id)){ niveis[niveis.length-1].push(n.id); visitados.add(n.id); } });

  const altNivel=90, largCaixa=170, altCaixa=54, espH=20;
  const h = 40 + niveis.length*altNivel + 20;
  const largSvg = Math.max(600, niveis.reduce((m,n)=>Math.max(m,n.length),0)*(largCaixa+espH));
  const pos = {};
  let sv = `<svg viewBox="0 0 ${largSvg} ${h}" role="img" aria-label="${esc(schema.titulo||'')}"><rect width="${largSvg}" height="${h}" fill="${T.fundo}"/>
    <text x="24" y="26" font-family="'JetBrains Mono',monospace" font-size="${TIPOGRAFIA_DIAGRAMA.apoio}" letter-spacing="1" fill="${T.tinta3}">HIERARQUIA</text>`;
  niveis.forEach((nivel,ni)=>{
    const y = 46 + ni*altNivel;
    const largTotal = nivel.length*(largCaixa+espH)-espH;
    const xIni = (largSvg-largTotal)/2;
    nivel.forEach((id,ii)=>{ pos[id] = {x:xIni+ii*(largCaixa+espH)+largCaixa/2, y:y+altCaixa/2, xL:xIni+ii*(largCaixa+espH), y0:y}; });
  });
  (schema.relacoes||[]).forEach(r=>{
    if(pos[r.de] && pos[r.para]) sv += `<line x1="${pos[r.de].x}" y1="${pos[r.de].y+altCaixa/2}" x2="${pos[r.para].x}" y2="${pos[r.para].y-altCaixa/2}" stroke="${T.linha}" stroke-width="2"/>`;
  });
  nos.forEach(no=>{
    const p = pos[no.id]; if(!p) return;
    const cor = corEnfase(no.enfase);
    sv += `<rect x="${p.xL}" y="${p.y0}" width="${largCaixa}" height="${altCaixa}" rx="8" fill="${cor.fill}" stroke="${cor.stroke}"/>`;
    quebrar(no.texto, 22).slice(0,2).forEach((l,k)=>{
      sv += `<text x="${p.x}" y="${p.y0+24+k*16}" text-anchor="middle" font-family="'Atkinson Hyperlegible',sans-serif" font-size="${TIPOGRAFIA_DIAGRAMA.no}" fill="${cor.ink}">${esc(l)}</text>`;
    });
  });
  return sv + '</svg>';
}
```

- [ ] **Step 3: `svgSchemaComparacao` — dois lados, divididos por alcançabilidade a partir de `nos[0]`**

```js
function svgSchemaComparacao(schema){
  const T = TOKENS_DIAGRAMA[temaAtivoDiagrama()];
  const nos = schema.nos;
  const grafo = {};
  (schema.relacoes||[]).forEach(r=>{ (grafo[r.de]=grafo[r.de]||[]).push(r.para); (grafo[r.para]=grafo[r.para]||[]).push(r.de); });
  const alcancaveis = new Set([nos[0].id]);
  const fila=[nos[0].id];
  while(fila.length){ const id=fila.shift(); (grafo[id]||[]).forEach(v=>{ if(!alcancaveis.has(v)){ alcancaveis.add(v); fila.push(v); } }); }
  const colunas = [nos.filter(n=>alcancaveis.has(n.id)), nos.filter(n=>!alcancaveis.has(n.id))];
  const largCol=270, altCaixa=56, espV=14, top=60;
  const maxLinhas = Math.max(colunas[0].length, colunas[1].length, 1);
  const h = top + maxLinhas*(altCaixa+espV) + 20;
  let sv = `<svg viewBox="0 0 600 ${h}" role="img" aria-label="${esc(schema.titulo||'')}"><rect width="600" height="${h}" fill="${T.fundo}"/>
    <text x="24" y="26" font-family="'JetBrains Mono',monospace" font-size="${TIPOGRAFIA_DIAGRAMA.apoio}" letter-spacing="1" fill="${T.tinta3}">COMPARAÇÃO</text>
    <line x1="300" y1="${top-10}" x2="300" y2="${h-10}" stroke="${T.linha}" stroke-dasharray="3 4"/>`;
  colunas.forEach((col,ci)=>{
    const x = ci===0 ? 24 : 306;
    col.forEach((no,ii)=>{
      const y = top + ii*(altCaixa+espV);
      const cor = corEnfase(no.enfase);
      sv += `<rect x="${x}" y="${y}" width="${largCol}" height="${altCaixa}" rx="8" fill="${cor.fill}" stroke="${cor.stroke}"/>`;
      quebrar(no.texto, 34).slice(0,2).forEach((l,k)=>{
        sv += `<text x="${x+12}" y="${y+22+k*16}" font-family="'Atkinson Hyperlegible',sans-serif" font-size="${TIPOGRAFIA_DIAGRAMA.no}" fill="${cor.ink}">${esc(l)}</text>`;
      });
    });
  });
  return sv + '</svg>';
}
```

- [ ] **Step 4: `svgSchemaCiclo` — nós num círculo, conectados em sequência fechada**

```js
function svgSchemaCiclo(schema){
  const T = TOKENS_DIAGRAMA[temaAtivoDiagrama()];
  const nos = schema.nos.slice(0,8);
  const cx=300, cy=280, raio=190, rBox=70, h=560;
  let sv = `<svg viewBox="0 0 600 ${h}" role="img" aria-label="${esc(schema.titulo||'')}"><rect width="600" height="${h}" fill="${T.fundo}"/>
    <defs><marker id="setaCiclo" markerWidth="8" markerHeight="8" refX="6" refY="4" orient="auto"><path d="M0,0 L8,4 L0,8 z" fill="${T.tinta3}"/></marker></defs>
    <text x="24" y="26" font-family="'JetBrains Mono',monospace" font-size="${TIPOGRAFIA_DIAGRAMA.apoio}" letter-spacing="1" fill="${T.tinta3}">CICLO</text>
    <text x="300" y="${cy+5}" text-anchor="middle" font-family="'Atkinson Hyperlegible',sans-serif" font-size="${TIPOGRAFIA_DIAGRAMA.titulo}" font-weight="700" fill="${T.tinta}">${esc(quebrar(schema.titulo||'',20)[0]||'')}</text>`;
  const pos = nos.map((no,i)=>{
    const ang = (i/nos.length)*2*Math.PI - Math.PI/2;
    return {no, x:cx+raio*Math.cos(ang), y:cy+raio*Math.sin(ang)};
  });
  pos.forEach((p,i)=>{
    const prox = pos[(i+1)%pos.length];
    sv += `<line x1="${p.x}" y1="${p.y}" x2="${prox.x}" y2="${prox.y}" stroke="${T.linha}" stroke-width="2" marker-end="url(#setaCiclo)"/>`;
  });
  pos.forEach(p=>{
    const cor = corEnfase(p.no.enfase);
    sv += `<rect x="${p.x-rBox/2}" y="${p.y-24}" width="${rBox}" height="48" rx="8" fill="${cor.fill}" stroke="${cor.stroke}"/>`;
    quebrar(p.no.texto, 14).slice(0,2).forEach((l,k)=>{
      sv += `<text x="${p.x}" y="${p.y-4+k*14}" text-anchor="middle" font-family="'Atkinson Hyperlegible',sans-serif" font-size="10" fill="${cor.ink}">${esc(l)}</text>`;
    });
  });
  return sv + '</svg>';
}
```

- [ ] **Step 5: `svgSchemaMapa` — nó central (`nos[0]`) com satélites (`nos[1..]`)**

```js
function svgSchemaMapa(schema){
  const T = TOKENS_DIAGRAMA[temaAtivoDiagrama()];
  const central = schema.nos[0];
  const satelites = schema.nos.slice(1,8);
  const alt=64, top=70;
  const h = Math.max(220, top + satelites.length*alt);
  const cy = h/2;
  let sv = `<svg viewBox="0 0 600 ${h}" role="img" aria-label="${esc(schema.titulo||'')}"><rect width="600" height="${h}" fill="${T.fundo}"/>
    <text x="24" y="28" font-family="'JetBrains Mono',monospace" font-size="${TIPOGRAFIA_DIAGRAMA.apoio}" letter-spacing="1" fill="${T.tinta3}">MAPA</text>`;
  const corCentral = corEnfase(central.enfase);
  sv += `<rect x="24" y="${cy-30}" width="150" height="60" rx="8" fill="${corCentral.stroke}"/>`;
  quebrar(central.texto,18).slice(0,3).forEach((l,i)=>{
    sv += `<text x="99" y="${cy-8+i*16}" text-anchor="middle" font-family="'Atkinson Hyperlegible',sans-serif" font-size="12" font-weight="700" fill="${T.fundo}">${esc(l)}</text>`;
  });
  satelites.forEach((no,i)=>{
    const y = top + i*alt - 14;
    const cor = corEnfase(no.enfase);
    sv += `<path d="M174 ${cy} C 230 ${cy}, 240 ${y+20}, 296 ${y+20}" stroke="${T.linha}" stroke-width="1.5" fill="none"/>
      <rect x="296" y="${y}" width="280" height="40" rx="6" fill="${cor.fill}" stroke="${cor.stroke}"/>`;
    quebrar(no.texto,36).slice(0,2).forEach((l,k)=>{
      sv += `<text x="310" y="${y+(no.texto.length>36?17:25)+k*14}" font-family="'Atkinson Hyperlegible',sans-serif" font-size="12" fill="${cor.ink}">${esc(l)}</text>`;
    });
  });
  return sv + '</svg>';
}
```

- [ ] **Step 6: Verificação manual — um schema de exemplo por layout**

No console do navegador, testar os 5 com o schema de exemplo abaixo (ajustando `layout`), confirmando visualmente (inserir o retorno num elemento com `.innerHTML`) que cada um desenha algo legível, sem nó cortado, com a cor certa por `enfase`:

```js
const exemplo = {
  layout: 'sequencia', titulo: 'Patrimônio e equação contábil',
  nos: [
    {id:'n1', texto:'Ativo = bens e direitos', enfase:'core'},
    {id:'n2', texto:'Passivo = obrigações', enfase:'core'},
    {id:'n3', texto:'Cuidado: nunca inverter o lado do Passivo', enfase:'alert'},
    {id:'n4', texto:'Patrimônio Líquido (PL)', enfase:'anchor'}
  ],
  relacoes: [{de:'n1',para:'n2'},{de:'n2',para:'n3'},{de:'n3',para:'n4'}]
};
document.body.insertAdjacentHTML('beforeend', '<div id="teste-svg" style="max-width:620px">'+renderDiagramaSVG(exemplo)+'</div>');
```

Repetir trocando `layout` para `hierarquia`, `comparacao`, `ciclo`, `mapa`, e trocar `S.tema` entre `claro`/`escuro` (`setTema('escuro')`) pra confirmar que as cores mudam mas o significado semântico (verde=core) permanece. Remover `#teste-svg` do DOM ao final.

- [ ] **Step 7: Commit**

```bash
git add "Programa/tutor-fiscal.html"
git commit -m "feat: 5 renderers do motor de composicao SVG (sequencia/hierarquia/comparacao/ciclo/mapa)"
```

---

### Task 3: Sincronizar mudanças com `tutor-fiscal-windows/index.html`

**Files:**
- Modify: `Programa/tutor-fiscal-windows/index.html`

**Interfaces:**
- Consumes: diffs exatos das Tasks 1-2
- Produces: nenhuma nova

- [ ] **Step 1: Replicar manualmente a seção `MOTOR DE COMPOSIÇÃO SVG` inteira em `Programa/tutor-fiscal-windows/index.html`**

- [ ] **Step 2: Verificação manual**

Repetir a verificação da Task 2 Step 6, abrindo `Programa/tutor-fiscal-windows/index.html`.

- [ ] **Step 3: Commit**

```bash
git add "Programa/tutor-fiscal-windows/index.html"
git commit -m "chore: sincronizar tutor-fiscal-windows/index.html com motor de composicao SVG"
```

---

## Ao final deste plano

- `renderDiagramaSVG(schema)` funcionando para os 5 tipos de layout, com tema claro/escuro.
- **Próximo:** Plano 5/5 — UI do card em 3 telas, juntando `gerarFichaIA`/`gerarProblemaIndependente` (Plano 3) com `renderDiagramaSVG` (este plano) na `tutor-fiscal.html`.
