// ═══════════════════════════════════════════════════════
//  JIT GESTIONALE v2 — Navigation Component
// ═══════════════════════════════════════════════════════

function initNav(activePage) {
  const placeholder = document.getElementById('nav');
  if (!placeholder) return;

  const pages = [
    {
      id: 'dashboard',
      href: '/dashboard.html',
      label: 'Dashboard',
      icon: `<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="3" width="7" height="7"/><rect x="14" y="3" width="7" height="7"/><rect x="14" y="14" width="7" height="7"/><rect x="3" y="14" width="7" height="7"/></svg>`,
    },
    {
      id: 'ordini',
      href: '/ordini.html',
      label: 'Ordini',
      badge: true,
      icon: `<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><polyline points="14,2 14,8 20,8"/><line x1="16" y1="13" x2="8" y2="13"/><line x1="16" y1="17" x2="8" y2="17"/><polyline points="10,9 9,9 8,9"/></svg>`,
    },
    {
      id: 'magazzino',
      href: '/magazzino.html',
      label: 'Magazzino',
      icon: `<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 16V8a2 2 0 0 0-1-1.73l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8a2 2 0 0 0 1 1.73l7 4a2 2 0 0 0 2 0l7-4A2 2 0 0 0 21 16z"/></svg>`,
    },
    {
      id: 'archivio',
      href: '/archivio.html',
      label: 'Archivio',
      icon: `<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="21 8 21 21 3 21 3 8"/><rect x="1" y="3" width="22" height="5"/><line x1="10" y1="12" x2="14" y2="12"/></svg>`,
    },
  ];

  placeholder.innerHTML = `
    <div class="sidebar-logo">
      <div class="sidebar-logo-mark">
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><polygon points="13 2 3 14 12 14 11 22 21 10 12 10 13 2"/></svg>
      </div>
      <div class="sidebar-logo-text">JIT <b>Pro</b></div>
      <div class="sidebar-logo-version">v2</div>
    </div>

    <div class="sidebar-section">
      <div class="sidebar-section-label">Navigazione</div>
      <nav class="sidebar-nav">
        ${pages.map(p => `
          <a href="${p.href}" class="${p.id === activePage ? 'active' : ''}">
            ${p.icon}
            ${p.label}
            ${p.badge ? `<span class="nav-badge hidden" id="nav-badge-ordini"></span>` : ''}
          </a>
        `).join('')}
      </nav>
    </div>

    <div class="sidebar-divider"></div>

    <div class="sidebar-section">
      <div id="nav-stock-alert" class="alert-pill hidden" onclick="window.location.href='/magazzino.html'">
        <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><path d="M10.29 3.86L1.82 18a2 2 0 001.71 3h16.94a2 2 0 001.71-3L13.71 3.86a2 2 0 00-3.42 0z"/><line x1="12" y1="9" x2="12" y2="13"/><line x1="12" y1="17" x2="12.01" y2="17"/></svg>
        <span id="nav-stock-alert-txt"></span>
      </div>
    </div>

    <div class="sidebar-footer">
      <div class="sidebar-user">
        <div class="user-avatar" id="nav-user-avatar">U</div>
        <div class="user-email" id="nav-user-email"></div>
      </div>
      <button class="btn-logout" onclick="AUTH.logout()">
        <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/><polyline points="16 17 21 12 16 7"/><line x1="21" y1="12" x2="9" y2="12"/></svg>
        Esci
      </button>
    </div>
  `;

  // Aggiorna alert pill
  function refreshAlertPill() {
    if (!S?.prodotti) return;
    const sotto = S.prodotti.filter(p => p.quantita <= p.scorta_min);
    const pill = document.getElementById('nav-stock-alert');
    const txt  = document.getElementById('nav-stock-alert-txt');
    if (!pill) return;
    if (sotto.length > 0) {
      if (txt) txt.textContent = `${sotto.length} scorte basse`;
      pill.classList.remove('hidden');
    } else {
      pill.classList.add('hidden');
    }
  }

  // Aggiorna badge ordini
  function refreshBadge() {
    if (!S?.ordini) return;
    const n = S.ordini.filter(o => ['aperto','in_lavorazione'].includes(o.stato)).length;
    const el = document.getElementById('nav-badge-ordini');
    if (!el) return;
    el.textContent = n > 0 ? n : '';
    el.style.display = n > 0 ? '' : 'none';
  }

  // Expose per update esterno
  window.refreshNavBadges = () => { refreshAlertPill(); refreshBadge(); };
}
