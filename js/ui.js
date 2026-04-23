// ═══════════════════════════════════════════════════════
//  JIT GESTIONALE v2 — UI Utilities
// ═══════════════════════════════════════════════════════

/* ── Toast ────────────────────────────────────────── */
function toast(msg, type = '') {
  const root = document.getElementById('toast-root');
  if (!root) return;
  const el = document.createElement('div');
  el.className = 'toast' + (type ? ' ' + type : '');
  el.textContent = msg;
  root.appendChild(el);
  setTimeout(() => el.remove(), 3200);
}

/* ── Modal helpers ────────────────────────────────── */
function openModal(id) {
  const el = document.getElementById(id);
  if (el) { el.classList.add('open'); document.body.style.overflow = 'hidden'; }
}
function closeModal(id) {
  const el = document.getElementById(id);
  if (el) { el.classList.remove('open'); document.body.style.overflow = ''; }
}

// Chiudi modal con Esc
document.addEventListener('keydown', e => {
  if (e.key === 'Escape') {
    document.querySelectorAll('.overlay.open, .modal-overlay.open').forEach(o => {
      o.classList.remove('open');
      document.body.style.overflow = '';
    });
  }
});

// Chiudi modal cliccando overlay
document.addEventListener('click', e => {
  if (e.target.classList.contains('overlay') || e.target.classList.contains('modal-overlay')) {
    e.target.classList.remove('open');
    document.body.style.overflow = '';
  }
});

/* ── Helpers ──────────────────────────────────────── */
function fmtDate(iso, opts = { day: '2-digit', month: '2-digit', year: 'numeric' }) {
  if (!iso) return '—';
  return new Date(iso).toLocaleDateString('it-IT', opts);
}

function fmtDateTime(iso) {
  if (!iso) return '—';
  return new Date(iso).toLocaleString('it-IT', {
    day: '2-digit', month: '2-digit', year: 'numeric',
    hour: '2-digit', minute: '2-digit'
  });
}

function fmtQty(n) {
  return (n ?? 0).toLocaleString('it-IT');
}

function statoBadge(stato) {
  const map = {
    aperto:        'bdg-aperto',
    in_lavorazione:'bdg-lavorazione',
    completato:    'bdg-completato',
    annullato:     'bdg-annullato',
  };
  const labels = {
    aperto: 'Aperto',
    in_lavorazione: 'In lavorazione',
    completato: 'Completato',
    annullato: 'Annullato',
  };
  return `<span class="badge ${map[stato] || ''}">${labels[stato] || stato}</span>`;
}

function prioritaBadge(p) {
  const map = { urgente: 'bdg-urgente', alta: 'bdg-alta', normale: 'bdg-normale', bassa: 'bdg-bassa' };
  return `<span class="badge ${map[p] || 'bdg-normale'}">${p}</span>`;
}

function qtyClass(quantita, scorta_min) {
  if (quantita === 0) return 'qty-out';
  if (quantita <= scorta_min) return 'qty-low';
  return 'qty-ok';
}

// Debounce per search
function debounce(fn, ms = 280) {
  let t;
  return (...args) => { clearTimeout(t); t = setTimeout(() => fn(...args), ms); };
}

// Aggiorna badge stock nella sidebar
function updateAlertPill(prodotti) {
  const sotto = prodotti.filter(p => p.quantita <= p.scorta_min);
  const pill = document.getElementById('nav-stock-alert');
  if (!pill) return;
  if (sotto.length > 0) {
    pill.textContent = `⚠ ${sotto.length} scorte basse`;
    pill.classList.remove('hidden');
  } else {
    pill.classList.add('hidden');
  }
}

// Aggiorna badge ordini aperti nella sidebar
function updateNavBadge(ordini) {
  const el = document.getElementById('nav-badge-ordini');
  if (!el) return;
  const n = ordini.filter(o => o.stato === 'aperto' || o.stato === 'in_lavorazione').length;
  el.textContent = n > 0 ? n : '';
  el.style.display = n > 0 ? '' : 'none';
}
