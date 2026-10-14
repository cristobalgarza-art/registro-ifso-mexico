// Gráficas en SVG puro para el Registro Bariátrico México. Sin librerías externas.
// Uso: Graficas.barras(el, {...}), Graficas.dona(el, {...}), Graficas.porcentajes(el, {...})
(function(){
  const NS = 'http://www.w3.org/2000/svg';
  const el = (tag, attrs, parent) => { const n = document.createElementNS(NS, tag); for (const k in attrs) n.setAttribute(k, attrs[k]); if (parent) parent.appendChild(n); return n; };
  const esc = s => String(s ?? '').replace(/[&<>"]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));
  const fmt = v => Number.isInteger(v) ? String(v) : Number(v).toFixed(1);

  // ---- tooltip único ----
  let tip = null;
  function getTip(){ if (!tip) { tip = document.createElement('div'); tip.className = 'gtip'; tip.hidden = true; document.body.appendChild(tip); } return tip; }
  function hover(node, html){
    const show = ev => { const t = getTip(); t.innerHTML = html; t.hidden = false; const p = ev.touches ? ev.touches[0] : ev; mueve(p); };
    const mueve = p => { const t = getTip(); const w = t.offsetWidth, h = t.offsetHeight; let x = p.clientX + 14, y = p.clientY - h - 10; if (x + w > innerWidth - 8) x = p.clientX - w - 14; if (y < 8) y = p.clientY + 16; t.style.left = x + 'px'; t.style.top = y + 'px'; };
    const hide = () => { if (tip) tip.hidden = true; };
    node.addEventListener('pointerenter', show); node.addEventListener('pointermove', mueve); node.addEventListener('pointerleave', hide);
    node.addEventListener('click', ev => { const t = getTip(); if (!t.hidden && t.innerHTML === html) hide(); else show(ev); ev.stopPropagation(); });
  }
  document.addEventListener('click', () => { if (tip) tip.hidden = true; });

  function vacio(root, msg){ root.innerHTML = `<p class="gvacio">${esc(msg || 'Sin datos en este periodo')}</p>`; }
  function nice(max){ if (max <= 0) return 1; const p = Math.pow(10, Math.floor(Math.log10(max))); const n = max / p; const m = n <= 1 ? 1 : n <= 2 ? 2 : n <= 5 ? 5 : 10; return m * p; }

  // ---- barras verticales (series temporal) ----
  // cats: [{label, value, sub?, dim?}]  dim=true pinta la barra atenuada (fuera del periodo elegido)
  function barras(root, { cats, color = 'var(--g1)', unidad = 'pacientes', alto = 220 }){
    root.innerHTML = '';
    if (!cats.length || !cats.some(c => c.value > 0)) return vacio(root);
    const W = Math.max(320, root.clientWidth || 600), H = alto, m = { t: 14, r: 8, b: 30, l: 34 };
    const iw = W - m.l - m.r, ih = H - m.t - m.b;
    const max = nice(Math.max(...cats.map(c => c.value)));
    const svg = el('svg', { viewBox: `0 0 ${W} ${H}`, width: '100%', height: H, class: 'gsvg', role: 'img' }, root);
    const ticks = max < 4 ? Math.max(1, Math.round(max)) : 4;
    for (let i = 0; i <= ticks; i++) { const v = max * i / ticks, y = m.t + ih - ih * i / ticks; el('line', { x1: m.l, x2: W - m.r, y1: y, y2: y, class: 'ggrid' }, svg); const t = el('text', { x: m.l - 6, y: y + 4, class: 'gtick', 'text-anchor': 'end' }, svg); t.textContent = fmt(v); }
    const n = cats.length, slot = iw / n, bw = Math.min(40, slot * 0.62);
    const every = n > 14 ? Math.ceil(n / 12) : 1;
    cats.forEach((c, i) => {
      const x = m.l + slot * i + (slot - bw) / 2, h = c.value > 0 ? Math.max(3, ih * c.value / max) : 0, y = m.t + ih - h;
      const g = el('g', { class: 'gmark' + (c.dim ? ' dim' : '') }, svg);
      el('rect', { x: m.l + slot * i, y: m.t, width: slot, height: ih, fill: 'transparent' }, g);
      if (h > 0) el('path', { d: `M${x},${y + h} V${y + 4} a4,4 0 0 1 4,-4 h${bw - 8} a4,4 0 0 1 4,4 V${y + h} Z`, fill: color }, g);
      if (c.value > 0 && n <= 14) { const t = el('text', { x: x + bw / 2, y: y - 4, class: 'glabel', 'text-anchor': 'middle' }, g); t.textContent = fmt(c.value); }
      if (i % every === 0) { const t = el('text', { x: m.l + slot * i + slot / 2, y: H - 10, class: 'gtick', 'text-anchor': 'middle' }, svg); t.textContent = c.label; }
      hover(g, `<b>${esc(c.sub || c.label)}</b><br>${fmt(c.value)} ${esc(unidad)}`);
    });
  }

  // ---- barras horizontales (categorías) ----
  function barrasH(root, { cats, color = 'var(--g1)', unidad = 'pacientes', total }){
    root.innerHTML = '';
    if (!cats.length || !cats.some(c => c.value > 0)) return vacio(root);
    const W = Math.max(320, root.clientWidth || 600), rowH = 30, m = { t: 6, r: 56, b: 6, l: 150 };
    const H = m.t + m.b + rowH * cats.length, iw = W - m.l - m.r;
    const max = Math.max(...cats.map(c => c.value)) || 1;
    const svg = el('svg', { viewBox: `0 0 ${W} ${H}`, width: '100%', height: H, class: 'gsvg', role: 'img' }, root);
    cats.forEach((c, i) => {
      const y = m.t + rowH * i, bh = 18, w = c.value > 0 ? Math.max(4, iw * c.value / max) : 0;
      const g = el('g', { class: 'gmark' }, svg);
      el('rect', { x: 0, y, width: W, height: rowH, fill: 'transparent' }, g);
      const lab = el('text', { x: m.l - 10, y: y + rowH / 2 + 4, class: 'gcat', 'text-anchor': 'end' }, g); lab.textContent = c.label.length > 22 ? c.label.slice(0, 21) + '…' : c.label;
      if (w > 0) el('path', { d: `M${m.l},${y + 6} h${w - 4} a4,4 0 0 1 4,4 v${bh - 8} a4,4 0 0 1 -4,4 h${-(w - 4)} Z`, fill: color }, g);
      else el('line', { x1: m.l, x2: m.l + 4, y1: y + rowH / 2, y2: y + rowH / 2, class: 'ggrid' }, g);
      const v = el('text', { x: m.l + w + 8, y: y + rowH / 2 + 4, class: 'glabel' }, g); v.textContent = fmt(c.value) + (total ? ` (${(100 * c.value / total).toFixed(0)}%)` : '');
      hover(g, `<b>${esc(c.label)}</b><br>${fmt(c.value)} ${esc(unidad)}${total ? ` · ${(100 * c.value / total).toFixed(1)}%` : ''}`);
    });
  }

  // ---- dona con leyenda y etiquetas directas ----
  function dona(root, { items, unidad = 'pacientes', titulo }){
    root.innerHTML = '';
    const total = items.reduce((s, i) => s + i.value, 0);
    if (!total) return vacio(root);
    const S = 160, cx = S / 2, cy = S / 2, R = 70, r = 46;
    const wrap = document.createElement('div'); wrap.className = 'gdona'; root.appendChild(wrap);
    const svg = el('svg', { viewBox: `0 0 ${S} ${S}`, width: S, height: S, class: 'gsvg', role: 'img' }, wrap);
    let a0 = -Math.PI / 2;
    const vivos = items.filter(i => i.value > 0);
    vivos.forEach(it => {
      const a1 = a0 + 2 * Math.PI * it.value / total;
      let d;
      if (vivos.length === 1) d = `M${cx},${cy - R} A${R},${R} 0 1 1 ${cx - 0.01},${cy - R} Z M${cx},${cy - r} A${r},${r} 0 1 0 ${cx + 0.01},${cy - r} Z`;
      else {
        const p = (ang, rad) => [cx + rad * Math.cos(ang), cy + rad * Math.sin(ang)];
        const [x0, y0] = p(a0, R), [x1, y1] = p(a1, R), [x2, y2] = p(a1, r), [x3, y3] = p(a0, r), big = a1 - a0 > Math.PI ? 1 : 0;
        d = `M${x0},${y0} A${R},${R} 0 ${big} 1 ${x1},${y1} L${x2},${y2} A${r},${r} 0 ${big} 0 ${x3},${y3} Z`;
      }
      const g = el('g', { class: 'gmark' }, svg);
      el('path', { d, fill: it.color, stroke: 'var(--surface)', 'stroke-width': 2, 'fill-rule': 'evenodd' }, g);
      hover(g, `<b>${esc(it.label)}</b><br>${fmt(it.value)} ${esc(unidad)} · ${(100 * it.value / total).toFixed(1)}%`);
      a0 = a1;
    });
    const t1 = el('text', { x: cx, y: cy + 2, class: 'gcentro', 'text-anchor': 'middle' }, svg); t1.textContent = fmt(total);
    const t2 = el('text', { x: cx, y: cy + 18, class: 'gtick', 'text-anchor': 'middle' }, svg); t2.textContent = titulo || unidad;
    const leg = document.createElement('ul'); leg.className = 'gleyenda'; wrap.appendChild(leg);
    items.forEach(it => { const li = document.createElement('li'); li.innerHTML = `<i style="background:${it.color}"></i><span>${esc(it.label)}</span><b>${fmt(it.value)} <small>(${total ? (100 * it.value / total).toFixed(0) : 0}%)</small></b>`; leg.appendChild(li); });
  }

  // ---- barras de porcentaje (n de d) ----
  function porcentajes(root, { items, color = 'var(--g1)' }){
    root.innerHTML = '';
    if (!items.length || !items.some(i => i.d > 0)) return vacio(root);
    const W = Math.max(320, root.clientWidth || 600), rowH = 32, m = { t: 6, r: 70, b: 6, l: 170 };
    const H = m.t + m.b + rowH * items.length, iw = W - m.l - m.r;
    const svg = el('svg', { viewBox: `0 0 ${W} ${H}`, width: '100%', height: H, class: 'gsvg', role: 'img' }, root);
    items.forEach((it, i) => {
      const y = m.t + rowH * i, bh = 14, p = it.d ? it.n / it.d : 0, w = p > 0 ? Math.max(4, iw * p) : 0;
      const g = el('g', { class: 'gmark' }, svg);
      el('rect', { x: 0, y, width: W, height: rowH, fill: 'transparent' }, g);
      const lab = el('text', { x: m.l - 10, y: y + rowH / 2 + 4, class: 'gcat', 'text-anchor': 'end' }, g); lab.textContent = it.label;
      el('rect', { x: m.l, y: y + (rowH - bh) / 2, width: iw, height: bh, rx: 4, class: 'gpista' }, g);
      if (w > 0) el('rect', { x: m.l, y: y + (rowH - bh) / 2, width: w, height: bh, rx: 4, fill: color }, g);
      const v = el('text', { x: m.l + iw + 8, y: y + rowH / 2 + 4, class: 'glabel' }, g); v.textContent = `${(100 * p).toFixed(0)}%`;
      hover(g, `<b>${esc(it.label)}</b><br>${it.n} de ${it.d} · ${(100 * p).toFixed(1)}%`);
    });
  }

  // ---- panel completo (comparten app principal y bitácora de residentes) ----
  const MESES = ['Ene','Feb','Mar','Abr','May','Jun','Jul','Ago','Sep','Oct','Nov','Dic'];
  const $ = s => document.querySelector(s);
  const med = a => { if (!a.length) return null; const s = [...a].map(Number).sort((x, y) => x - y); const m = s.length >> 1; return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2; };
  // rows: [{anio, mes, sexo, edad, imc, dm2, has, dislip, glp1, origen, sector, tipo, proc, abordaje, estancia}]
  // anio: '2026' o '' (todos); mes: 1-12 o 0; etiquetas: {proc:{...}, abordaje:{...}}
  function pintarPanel({ rows, anio, mes, etiquetas }){
    const years = [...new Set(rows.map(r => r.anio).filter(Boolean))].sort();
    const porMes = y => MESES.map((m, i) => ({ label: m, sub: `${m} ${y}`, value: rows.filter(r => r.anio === y && r.mes === i + 1).length, dim: !!mes && mes !== i + 1 }));
    let cats, titulo;
    if (anio) { cats = porMes(Number(anio)); titulo = 'Pacientes por mes · ' + anio; }
    else if (years.length > 1) { cats = years.map(y => ({ label: String(y), value: rows.filter(r => r.anio === y).length })); titulo = 'Pacientes por año'; }
    else { const y = years[0] || new Date().getFullYear(); cats = porMes(y); titulo = 'Pacientes por mes · ' + y; }
    $('#g-mes-t').textContent = titulo;
    barras($('#g-mes'), { cats });

    const rs = mes ? rows.filter(r => r.mes === mes) : rows;
    const n = rs.length, M = rs.filter(r => r.sexo === 'M').length;
    const f1 = v => v == null ? '—' : (Number.isInteger(v) ? String(v) : v.toFixed(1));
    $('#kpis-panel').innerHTML = [
      [n, 'pacientes'], [n ? Math.round(100 * M / n) + '%' : '—', 'mujeres'],
      [f1(med(rs.map(r => r.imc))), 'IMC mediano'], [f1(med(rs.map(r => r.estancia))), 'días de estancia (mediana)']
    ].map(([v, l]) => `<div class="kpi g"><b>${v}</b><span>${l}</span></div>`).join('');

    const cnt = (k, v) => rs.filter(r => r[k] === v).length;
    const procs = Object.keys(etiquetas.proc).map(k => ({ label: etiquetas.proc[k], value: cnt('proc', k) })).filter(c => c.value > 0).sort((a, b) => b.value - a.value);
    barrasH($('#g-proc'), { cats: procs, total: n });

    porcentajes($('#g-perfil'), { items: [
      { label: 'Mujeres', n: M, d: n }, { label: 'DM2', n: rs.filter(r => r.dm2).length, d: n }, { label: 'Hipertensión', n: rs.filter(r => r.has).length, d: n },
      { label: 'Dislipidemia', n: rs.filter(r => r.dislip).length, d: n }, { label: 'GLP-1 previo', n: rs.filter(r => r.glp1).length, d: n },
      { label: 'Internacionales', n: cnt('origen', 'internacional'), d: n }, { label: 'Atención privada', n: cnt('sector', 'privado'), d: n }
    ].filter(() => n > 0) });

    dona($('#g-tipo'), { items: [{ label: 'Primaria', value: cnt('tipo', 'primaria'), color: 'var(--g1)' }, { label: 'Revisional', value: cnt('tipo', 'revisional'), color: 'var(--g2)' }], titulo: 'cirugías' });
    const AB = [['laparoscopica', 'Laparoscópico', 'var(--g1)'], ['robotica', 'Robótico', 'var(--g2)'], ['abierta', 'Abierto', 'var(--g3)'], ['endoscopica', 'Endoscópico', 'var(--g4)']];
    dona($('#g-abord'), { items: AB.map(([k, l, c]) => ({ label: l, value: cnt('abordaje', k), color: c })), titulo: 'cirugías' });

    const bins = (vals, edges, fmtBin) => edges.map((e, i) => { const hi = edges[i + 1]; const v = vals.filter(x => x >= e && (hi == null || x < hi)).length; return { label: fmtBin(e, hi), value: v }; });
    barras($('#g-edad'), { cats: bins(rs.map(r => Number(r.edad)), [10, 20, 30, 40, 50, 60, 70], (a, b) => b == null ? `${a}+` : `${a}–${b - 1}`), alto: 180 });
    barras($('#g-imc'), { cats: bins(rs.map(r => Number(r.imc)), [0, 30, 35, 40, 45, 50, 60], (a, b) => a === 0 ? '<30' : b == null ? `${a}+` : `${a}–${b - 0.1}`), alto: 180 });
    return rs;
  }

  window.Graficas = { barras, barrasH, dona, porcentajes, pintarPanel, MESES };
})();
