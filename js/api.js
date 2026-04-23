// ═══════════════════════════════════════════════════════
//  JIT GESTIONALE v2 — API Layer
//  Cache locale per evitare query ridondanti a Supabase
// ═══════════════════════════════════════════════════════

// ── Stato globale ────────────────────────────────────
const S = {
  prodotti:   [],
  ordini:     [],
  items:      {},   // { ordine_id: [item,...] }
  spedizioni: {},   // { ordine_id: [sped,...] }
  _dirty:     {},   // { key: true } — da ricaricare
};

// ── API ──────────────────────────────────────────────
const API = {

  /* ──────────────────── PRODOTTI ──────────────────── */

  async loadProdotti(force = false) {
    if (!force && S.prodotti.length && !S._dirty.prodotti) return S.prodotti;
    const { data, error } = await sb
      .from('prodotti')
      .select('id,codice_jit,descrizione,categoria,quantita,scorta_min,unita,note')
      .order('categoria').order('codice_jit');
    if (error) throw error;
    S.prodotti = data ?? [];
    delete S._dirty.prodotti;
    return S.prodotti;
  },

  getProdotto(codice) {
    return S.prodotti.find(p => p.codice_jit === codice) ?? null;
  },

  async createProdotto(data) {
    const { error } = await sb.from('prodotti').insert(data);
    if (error) throw error;
    S._dirty.prodotti = true;
  },

  async updateProdotto(id, data) {
    const { error } = await sb.from('prodotti').update(data).eq('id', id);
    if (error) throw error;
    // Aggiorna cache locale immediatamente
    const i = S.prodotti.findIndex(p => p.id === id);
    if (i >= 0) Object.assign(S.prodotti[i], data);
  },

  async deleteProdotto(id) {
    const { error } = await sb.from('prodotti').delete().eq('id', id);
    if (error) throw error;
    S.prodotti = S.prodotti.filter(p => p.id !== id);
  },

  async addMovimento(codice_jit, tipo, qty, causale, ordine_id = null) {
    await sb.from('movimenti').insert({ codice_jit, tipo, qty, causale, ordine_id });
  },

  async loadMovimentiProdotto(codice_jit) {
    const { data } = await sb
      .from('movimenti')
      .select('*')
      .eq('codice_jit', codice_jit)
      .order('created_at', { ascending: false })
      .limit(50);
    return data ?? [];
  },

  /* ──────────────────── ORDINI ─────────────────────── */

  async loadOrdini(stati = null, force = false) {
    const key = `ordini_${(stati||[]).join('_') || 'all'}`;
    if (!force && S.ordini.length && !S._dirty[key]) return S.ordini;

    let q = sb
      .from('ordini')
      .select('id,numero_oda,cliente,stato,fase,priorita,data_consegna,note,created_at,completed_at')
      .order('created_at', { ascending: false });

    if (stati && stati.length) q = q.in('stato', stati);
    const { data, error } = await q;
    if (error) throw error;
    S.ordini = data ?? [];
    delete S._dirty[key];
    return S.ordini;
  },

  async loadOrdineItems(ordine_id, force = false) {
    if (!force && S.items[ordine_id]) return S.items[ordine_id];
    const { data } = await sb
      .from('ordine_items')
      .select('id,codice_jit,descrizione,qty')
      .eq('ordine_id', ordine_id)
      .order('created_at');
    S.items[ordine_id] = data ?? [];
    return S.items[ordine_id];
  },

  async loadSpedizioni(ordine_id, force = false) {
    if (!force && S.spedizioni[ordine_id]) return S.spedizioni[ordine_id];
    const { data } = await sb
      .from('spedizioni')
      .select('id,qty,note,created_at')
      .eq('ordine_id', ordine_id)
      .order('created_at');
    S.spedizioni[ordine_id] = data ?? [];
    return S.spedizioni[ordine_id];
  },

  // Genera ID ordine via RPC
  async newOrdineId() {
    const { data } = await sb.rpc('genera_ordine_id');
    return data;
  },

  async createOrdine(ordineData, items) {
    const id = await this.newOrdineId();
    const { error: e1 } = await sb.from('ordini').insert({ id, ...ordineData });
    if (e1) throw e1;

    if (items && items.length) {
      const rows = items.map(it => ({
        ordine_id:  id,
        codice_jit: it.codice_jit,
        descrizione: it.descrizione || null,
        qty:        it.qty,
      }));
      const { error: e2 } = await sb.from('ordine_items').insert(rows);
      if (e2) throw e2;
    }

    // Log
    await sb.from('movimenti').insert({
      codice_jit: '',
      tipo: 'nota',
      qty: 0,
      causale: `Ordine ${id} creato`,
      ordine_id: id,
    });

    S._dirty['ordini_all'] = true;
    S._dirty['ordini_aperto_in_lavorazione'] = true;
    return id;
  },

  async updateOrdine(id, data) {
    const { error } = await sb.from('ordini').update(data).eq('id', id);
    if (error) throw error;
    const i = S.ordini.findIndex(o => o.id === id);
    if (i >= 0) Object.assign(S.ordini[i], data);
  },

  async setFase(id, fase) {
    const stato = S.ordini.find(o => o.id === id)?.stato;
    const updates = { fase, stato: stato === 'aperto' ? 'in_lavorazione' : stato };
    await this.updateOrdine(id, updates);
    await sb.from('movimenti').insert({
      codice_jit: '',
      tipo: 'fase',
      qty: 0,
      causale: `Fase → ${fase}`,
      ordine_id: id,
    });
  },

  async spedizioneParziale(ordine_id, qty, note) {
    // Salva spedizione
    const { error } = await sb.from('spedizioni').insert({ ordine_id, qty, note });
    if (error) throw error;

    // Scarica stock proporzionale
    const items = await this.loadOrdineItems(ordine_id);
    const totItems = items.reduce((s, it) => s + it.qty, 0);
    if (totItems > 0) {
      for (const it of items) {
        const p = this.getProdotto(it.codice_jit);
        if (!p) continue;
        const quota = Math.round(qty * (it.qty / totItems));
        if (quota <= 0) continue;
        const newQ = Math.max(0, p.quantita - quota);
        await this.updateProdotto(p.id, { quantita: newQ });
        await this.addMovimento(it.codice_jit, 'parziale', -quota, `Spedizione parziale ${ordine_id}`, ordine_id);
      }
    }

    delete S.spedizioni[ordine_id];
  },

  async completaOrdine(ordine_id, scarti) {
    const items    = await this.loadOrdineItems(ordine_id);
    const sped     = await this.loadSpedizioni(ordine_id);
    const totSped  = sped.reduce((s, sp) => s + sp.qty, 0);
    const totItems = items.reduce((s, it) => s + it.qty, 0);
    const residuo  = totItems - totSped;

    // Aggiorna stato ordine
    await this.updateOrdine(ordine_id, {
      stato: 'completato',
      fase:  'Spedizione',
      completed_at: new Date().toISOString(),
    });

    // Scarica residuo dallo stock
    if (residuo > 0) {
      for (const it of items) {
        const p = this.getProdotto(it.codice_jit);
        if (!p) continue;
        const quota = Math.round(residuo * (it.qty / totItems));
        if (quota <= 0) continue;
        let scartoItem = scarti?.find(s => s.codice_jit === it.codice_jit);
        let scartoQty  = scartoItem?.qty || 0;
        const spedQty  = Math.max(0, quota - scartoQty);
        if (spedQty > 0) {
          const newQ = Math.max(0, p.quantita - spedQty);
          await this.updateProdotto(p.id, { quantita: newQ });
          await this.addMovimento(it.codice_jit, 'ordine', -spedQty, `Completamento ${ordine_id}`, ordine_id);
        }
        if (scartoQty > 0) {
          await this.addMovimento(it.codice_jit, 'scarto', -scartoQty, `Scarti completamento ${ordine_id}`, ordine_id);
        }
      }
    }

    delete S.spedizioni[ordine_id];
    delete S.items[ordine_id];
  },

  async annullaOrdine(ordine_id) {
    await this.updateOrdine(ordine_id, { stato: 'annullato' });
    await sb.from('movimenti').insert({
      codice_jit: '',
      tipo: 'nota',
      qty: 0,
      causale: `Ordine ${ordine_id} annullato`,
      ordine_id,
    });
  },

  async eliminaOrdine(ordine_id) {
    await sb.from('movimenti').delete().eq('ordine_id', ordine_id);
    const { error } = await sb.from('ordini').delete().eq('id', ordine_id);
    if (error) throw error;
    S.ordini = S.ordini.filter(o => o.id !== ordine_id);
    delete S.items[ordine_id];
    delete S.spedizioni[ordine_id];
  },

  async loadMovimentiOrdine(ordine_id) {
    const { data } = await sb
      .from('movimenti')
      .select('*')
      .eq('ordine_id', ordine_id)
      .order('created_at');
    return data ?? [];
  },

  /* ──────────────────── DASHBOARD ─────────────────── */
  async getDashStats() {
    const [{ count: aperti }, { count: lavorazione }, { count: completati }] = await Promise.all([
      sb.from('ordini').select('*', { count: 'exact', head: true }).eq('stato', 'aperto'),
      sb.from('ordini').select('*', { count: 'exact', head: true }).eq('stato', 'in_lavorazione'),
      sb.from('ordini').select('*', { count: 'exact', head: true }).eq('stato', 'completato'),
    ]);
    const sottoScorta = S.prodotti.filter(p => p.quantita <= p.scorta_min).length;
    return { aperti, lavorazione, completati, sottoScorta };
  },
};
