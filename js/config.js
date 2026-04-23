// ═══════════════════════════════════════════════════════
//  JIT GESTIONALE v2 — Configurazione Supabase
//  ⚠️  Sostituisci con le tue credenziali
//  Le trovi in: Supabase → Settings → API
// ═══════════════════════════════════════════════════════

const SUPABASE_URL  = 'https://bwxabwmwjcjsndyscrpg.supabase.co';
const SUPABASE_ANON = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJ3eGFid213amNqc25keXNjcnBnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzY5Mjk2NTksImV4cCI6MjA5MjUwNTY1OX0.Npy78JrLRAXDT8VI5Kn1pl75usI5cSeJVSVys3atwnE';

// Inizializza client Supabase (caricato via CDN)
const sb = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON);
