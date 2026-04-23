// ═══════════════════════════════════════════════════════
//  JIT GESTIONALE v2 — Auth
// ═══════════════════════════════════════════════════════

const AUTH = {
  user: null,

  // Verifica sessione e redirect se non autenticato
  async require() {
    const { data: { session } } = await sb.auth.getSession();
    if (!session) { window.location.href = '/index.html'; return null; }
    this.user = session.user;
    return this.user;
  },

  async logout() {
    await sb.auth.signOut();
    window.location.href = '/index.html';
  },

  initNav() {
    const el = document.getElementById('nav-user-email');
    if (el && this.user) {
      el.textContent = this.user.email;
      const av = document.getElementById('nav-user-avatar');
      if (av) av.textContent = (this.user.email[0] || 'U').toUpperCase();
    }
  }
};
