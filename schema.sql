-- ═══════════════════════════════════════════════════════════════
--  JIT GESTIONALE v2 — Schema Database Completo
--  Esegui nel SQL Editor di Supabase (New Query → Run)
--  ⚠️  Cancella e ricrea tutto da zero
-- ═══════════════════════════════════════════════════════════════

-- ── 1. DROP esistente (partenza pulita) ─────────────────────────
DROP TABLE IF EXISTS movimenti     CASCADE;
DROP TABLE IF EXISTS spedizioni    CASCADE;
DROP TABLE IF EXISTS ordine_items  CASCADE;
DROP TABLE IF EXISTS ordini        CASCADE;
DROP TABLE IF EXISTS prodotti      CASCADE;
DROP TABLE IF EXISTS operazioni_idempotenti CASCADE;
DROP FUNCTION IF EXISTS update_updated_at() CASCADE;
DROP FUNCTION IF EXISTS genera_ordine_id()  CASCADE;
DROP FUNCTION IF EXISTS rpc_spedizione_parziale(TEXT, INTEGER, TEXT, TEXT) CASCADE;
DROP FUNCTION IF EXISTS rpc_completa_ordine(TEXT, JSONB, TEXT) CASCADE;

-- ── 2. Trigger updated_at ────────────────────────────────────────
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN NEW.updated_at = NOW(); RETURN NEW; END;
$$ LANGUAGE plpgsql;

-- ── 3. PRODOTTI ──────────────────────────────────────────────────
CREATE TABLE prodotti (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  codice_jit  VARCHAR(30) UNIQUE NOT NULL,
  descrizione TEXT        NOT NULL,
  categoria   VARCHAR(50) NOT NULL DEFAULT 'Generale',
  quantita    INTEGER     NOT NULL DEFAULT 0 CHECK (quantita >= 0),
  scorta_min  INTEGER     NOT NULL DEFAULT 0,
  unita       VARCHAR(10) NOT NULL DEFAULT 'pz',
  note        TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER trg_prodotti_upd
  BEFORE UPDATE ON prodotti
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE INDEX idx_prodotti_codice    ON prodotti(codice_jit);
CREATE INDEX idx_prodotti_categoria ON prodotti(categoria);
CREATE INDEX idx_prodotti_qty       ON prodotti(quantita);

-- ── 4. ORDINI ────────────────────────────────────────────────────
CREATE TABLE ordini (
  id            VARCHAR(25)  PRIMARY KEY,
  numero_oda    VARCHAR(100),                        -- N° ODA del cliente ← NUOVO
  cliente       VARCHAR(200) NOT NULL,
  stato         VARCHAR(20)  NOT NULL DEFAULT 'aperto'
                CHECK (stato IN ('aperto','in_lavorazione','completato','annullato')),
  fase          VARCHAR(50)  NOT NULL DEFAULT 'Ricevimento'
                CHECK (fase IN ('Ricevimento','Embedding','Personalizzazione','Controllo QC','Spedizione')),
  priorita      VARCHAR(10)  NOT NULL DEFAULT 'normale'
                CHECK (priorita IN ('bassa','normale','alta','urgente')),
  data_consegna DATE,
  note          TEXT,
  created_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  completed_at  TIMESTAMPTZ
);

CREATE TRIGGER trg_ordini_upd
  BEFORE UPDATE ON ordini
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE INDEX idx_ordini_stato   ON ordini(stato);
CREATE INDEX idx_ordini_cliente ON ordini(cliente);
CREATE INDEX idx_ordini_created ON ordini(created_at DESC);
CREATE INDEX idx_ordini_oda     ON ordini(numero_oda);

-- ── 5. ORDINE ITEMS ──────────────────────────────────────────────
CREATE TABLE ordine_items (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  ordine_id   VARCHAR(25) NOT NULL REFERENCES ordini(id) ON DELETE CASCADE,
  codice_jit  VARCHAR(30) NOT NULL,
  descrizione TEXT,
  qty         INTEGER     NOT NULL CHECK (qty > 0),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_items_ordine ON ordine_items(ordine_id);
CREATE INDEX idx_items_codice ON ordine_items(codice_jit);

-- ── 6. SPEDIZIONI ────────────────────────────────────────────────
CREATE TABLE spedizioni (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  ordine_id   VARCHAR(25) NOT NULL REFERENCES ordini(id) ON DELETE CASCADE,
  qty         INTEGER     NOT NULL CHECK (qty > 0),
  note        TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_sped_ordine ON spedizioni(ordine_id);

-- ── 7. MOVIMENTI STOCK ───────────────────────────────────────────
CREATE TABLE movimenti (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  codice_jit  VARCHAR(30) NOT NULL DEFAULT '',
  tipo        VARCHAR(20) NOT NULL
              -- 'nota' è mantenuto solo per retrocompatibilità con record legacy;
              -- il codice applicativo deve scrivere esclusivamente 'note'
              CHECK (tipo IN ('carico','scarico','ordine','parziale','scarto','rettifica','fase','note','nota')),
  qty         INTEGER     NOT NULL,
  causale     TEXT,
  ordine_id   VARCHAR(25),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_mov_codice  ON movimenti(codice_jit);
CREATE INDEX idx_mov_ordine  ON movimenti(ordine_id);
CREATE INDEX idx_mov_created ON movimenti(created_at DESC);

-- ── 8. IDEMPOTENZA OPERAZIONI CRITICHE ───────────────────────────
CREATE TABLE operazioni_idempotenti (
  idempotency_key TEXT        PRIMARY KEY,
  ordine_id       VARCHAR(25) NOT NULL,
  tipo_operazione VARCHAR(20) NOT NULL CHECK (tipo_operazione IN ('parziale','completamento')),
  result_json     JSONB       NOT NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (idempotency_key)
);

-- ── 9. RLS (sicurezza) ───────────────────────────────────────────
ALTER TABLE prodotti     ENABLE ROW LEVEL SECURITY;
ALTER TABLE ordini       ENABLE ROW LEVEL SECURITY;
ALTER TABLE ordine_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE spedizioni   ENABLE ROW LEVEL SECURITY;
ALTER TABLE movimenti    ENABLE ROW LEVEL SECURITY;
ALTER TABLE operazioni_idempotenti ENABLE ROW LEVEL SECURITY;

CREATE POLICY auth_all ON prodotti     FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY auth_all ON ordini       FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY auth_all ON ordine_items FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY auth_all ON spedizioni   FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY auth_all ON movimenti    FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY auth_all ON operazioni_idempotenti FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- ── 10. Funzione genera ID ordine ────────────────────────────────
-- Formato: JIT-AAMM-NNNN  (es. JIT-2604-0001)
CREATE OR REPLACE FUNCTION genera_ordine_id()
RETURNS TEXT AS $$
DECLARE
  prefix TEXT := 'JIT-' || TO_CHAR(NOW(), 'YYMM') || '-';
  seq    INTEGER;
BEGIN
  SELECT COALESCE(MAX(CAST(SUBSTRING(id FROM LENGTH(prefix)+1) AS INTEGER)), 0) + 1
  INTO seq
  FROM ordini
  WHERE id LIKE prefix || '%';
  RETURN prefix || LPAD(seq::TEXT, 4, '0');
END;
$$ LANGUAGE plpgsql;

-- ── 11. RPC: spedizione parziale atomica/idempotente ─────────────
CREATE OR REPLACE FUNCTION rpc_spedizione_parziale(
  p_ordine_id TEXT,
  p_qty INTEGER,
  p_note TEXT,
  p_idempotency_key TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
  v_actor UUID := auth.uid();
  v_stato TEXT;
  v_tot_items INTEGER := 0;
  v_spedito INTEGER := 0;
  v_residuo INTEGER := 0;
  v_rem INTEGER := 0;
  v_idx INTEGER := 0;
  v_tot_righe INTEGER := 0;
  v_quota INTEGER := 0;
  v_result JSONB;
  r RECORD;
BEGIN
  IF p_idempotency_key IS NULL OR btrim(p_idempotency_key) = '' THEN
    RAISE EXCEPTION 'idempotency_key obbligatoria';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtext(p_idempotency_key));
  IF p_qty IS NULL OR p_qty <= 0 THEN
    RAISE EXCEPTION 'Quantità spedizione non valida';
  END IF;

  SELECT result_json INTO v_result
  FROM operazioni_idempotenti
  WHERE idempotency_key = p_idempotency_key;
  IF FOUND THEN
    RETURN v_result;
  END IF;

  SELECT stato INTO v_stato
  FROM ordini
  WHERE id = p_ordine_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Ordine % non trovato', p_ordine_id;
  END IF;
  IF v_stato IN ('annullato','completato') THEN
    RAISE EXCEPTION 'Ordine % non spedibile (stato=%)', p_ordine_id, v_stato;
  END IF;

  SELECT COALESCE(SUM(qty),0) INTO v_tot_items FROM ordine_items WHERE ordine_id = p_ordine_id;
  SELECT COALESCE(SUM(qty),0) INTO v_spedito   FROM spedizioni   WHERE ordine_id = p_ordine_id;
  v_residuo := v_tot_items - v_spedito;
  IF v_residuo <= 0 THEN
    RAISE EXCEPTION 'Nessun residuo da spedire per ordine %', p_ordine_id;
  END IF;
  IF p_qty > v_residuo THEN
    RAISE EXCEPTION 'Quantità richiesta (%) superiore al residuo (%)', p_qty, v_residuo;
  END IF;

  SELECT COUNT(*) INTO v_tot_righe FROM ordine_items WHERE ordine_id = p_ordine_id;
  v_rem := p_qty;

  FOR r IN
    SELECT oi.codice_jit, oi.qty
    FROM ordine_items oi
    WHERE oi.ordine_id = p_ordine_id
    ORDER BY oi.codice_jit
  LOOP
    v_idx := v_idx + 1;
    IF v_idx < v_tot_righe THEN
      v_quota := FLOOR((p_qty::NUMERIC * r.qty::NUMERIC) / NULLIF(v_tot_items,0));
    ELSE
      v_quota := v_rem;
    END IF;
    IF v_quota < 0 THEN v_quota := 0; END IF;
    IF v_quota > v_rem THEN v_quota := v_rem; END IF;
    v_rem := v_rem - v_quota;

    IF v_quota > 0 THEN
      UPDATE prodotti
      SET quantita = quantita - v_quota
      WHERE codice_jit = r.codice_jit
        AND quantita >= v_quota;
      IF NOT FOUND THEN
        RAISE EXCEPTION 'Stock insufficiente per % (quota=%)', r.codice_jit, v_quota;
      END IF;

      INSERT INTO movimenti(codice_jit, tipo, qty, causale, ordine_id)
      VALUES (
        r.codice_jit,
        'parziale',
        -v_quota,
        format('Spedizione parziale %s%s', p_ordine_id, CASE WHEN v_actor IS NOT NULL THEN format(' (actor=%s)', v_actor) ELSE '' END),
        p_ordine_id
      );
    END IF;
  END LOOP;

  INSERT INTO spedizioni(ordine_id, qty, note) VALUES (p_ordine_id, p_qty, p_note);

  v_result := jsonb_build_object(
    'ordine_id', p_ordine_id,
    'operazione', 'parziale',
    'spedito_qty', p_qty,
    'residuo_qty', v_residuo - p_qty
  );

  INSERT INTO operazioni_idempotenti(idempotency_key, ordine_id, tipo_operazione, result_json)
  VALUES (p_idempotency_key, p_ordine_id, 'parziale', v_result);

  RETURN v_result;
END;
$$;

-- ── 12. RPC: completamento ordine atomico/idempotente ────────────
CREATE OR REPLACE FUNCTION rpc_completa_ordine(
  p_ordine_id TEXT,
  p_scarti JSONB,
  p_idempotency_key TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
  v_actor UUID := auth.uid();
  v_stato TEXT;
  v_tot_items INTEGER := 0;
  v_spedito INTEGER := 0;
  v_residuo INTEGER := 0;
  v_rem INTEGER := 0;
  v_idx INTEGER := 0;
  v_tot_righe INTEGER := 0;
  v_quota INTEGER := 0;
  v_scarto INTEGER := 0;
  v_ship INTEGER := 0;
  v_result JSONB;
  r RECORD;
BEGIN
  IF p_idempotency_key IS NULL OR btrim(p_idempotency_key) = '' THEN
    RAISE EXCEPTION 'idempotency_key obbligatoria';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtext(p_idempotency_key));

  SELECT result_json INTO v_result
  FROM operazioni_idempotenti
  WHERE idempotency_key = p_idempotency_key;
  IF FOUND THEN
    RETURN v_result;
  END IF;

  SELECT stato INTO v_stato
  FROM ordini
  WHERE id = p_ordine_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Ordine % non trovato', p_ordine_id;
  END IF;
  IF v_stato = 'annullato' THEN
    RAISE EXCEPTION 'Ordine % annullato, non completabile', p_ordine_id;
  END IF;
  IF v_stato = 'completato' THEN
    RAISE EXCEPTION 'Ordine % già completato', p_ordine_id;
  END IF;

  SELECT COALESCE(SUM(qty),0) INTO v_tot_items FROM ordine_items WHERE ordine_id = p_ordine_id;
  SELECT COALESCE(SUM(qty),0) INTO v_spedito   FROM spedizioni   WHERE ordine_id = p_ordine_id;
  v_residuo := v_tot_items - v_spedito;
  IF v_residuo < 0 THEN
    RAISE EXCEPTION 'Residuo negativo per ordine %', p_ordine_id;
  END IF;

  SELECT COUNT(*) INTO v_tot_righe FROM ordine_items WHERE ordine_id = p_ordine_id;
  v_rem := v_residuo;

  FOR r IN
    SELECT oi.codice_jit, oi.qty
    FROM ordine_items oi
    WHERE oi.ordine_id = p_ordine_id
    ORDER BY oi.codice_jit
  LOOP
    v_idx := v_idx + 1;
    IF v_idx < v_tot_righe THEN
      v_quota := FLOOR((v_residuo::NUMERIC * r.qty::NUMERIC) / NULLIF(v_tot_items,0));
    ELSE
      v_quota := v_rem;
    END IF;
    IF v_quota < 0 THEN v_quota := 0; END IF;
    IF v_quota > v_rem THEN v_quota := v_rem; END IF;
    v_rem := v_rem - v_quota;

    v_scarto := COALESCE((
      SELECT (e->>'qty')::INTEGER
      FROM jsonb_array_elements(COALESCE(p_scarti, '[]'::JSONB)) e
      WHERE e->>'codice_jit' = r.codice_jit
      LIMIT 1
    ), 0);
    IF v_scarto < 0 THEN
      RAISE EXCEPTION 'Scarto negativo non valido per %', r.codice_jit;
    END IF;
    IF v_scarto > v_quota THEN
      RAISE EXCEPTION 'Scarto (%) superiore alla quota (%) per %', v_scarto, v_quota, r.codice_jit;
    END IF;
    v_ship := v_quota - v_scarto;

    IF v_ship > 0 THEN
      UPDATE prodotti
      SET quantita = quantita - v_ship
      WHERE codice_jit = r.codice_jit
        AND quantita >= v_ship;
      IF NOT FOUND THEN
        RAISE EXCEPTION 'Stock insufficiente per % (qty=%)', r.codice_jit, v_ship;
      END IF;

      INSERT INTO movimenti(codice_jit, tipo, qty, causale, ordine_id)
      VALUES (
        r.codice_jit,
        'ordine',
        -v_ship,
        format('Completamento %s%s', p_ordine_id, CASE WHEN v_actor IS NOT NULL THEN format(' (actor=%s)', v_actor) ELSE '' END),
        p_ordine_id
      );
    END IF;

    IF v_scarto > 0 THEN
      INSERT INTO movimenti(codice_jit, tipo, qty, causale, ordine_id)
      VALUES (
        r.codice_jit,
        'scarto',
        -v_scarto,
        format('Scarti completamento %s%s', p_ordine_id, CASE WHEN v_actor IS NOT NULL THEN format(' (actor=%s)', v_actor) ELSE '' END),
        p_ordine_id
      );
    END IF;
  END LOOP;

  UPDATE ordini
  SET stato = 'completato',
      fase = 'Spedizione',
      completed_at = NOW()
  WHERE id = p_ordine_id;

  v_result := jsonb_build_object(
    'ordine_id', p_ordine_id,
    'operazione', 'completamento',
    'residuo_pre', v_residuo,
    'completed_at', NOW()
  );

  INSERT INTO operazioni_idempotenti(idempotency_key, ordine_id, tipo_operazione, result_json)
  VALUES (p_idempotency_key, p_ordine_id, 'completamento', v_result);

  RETURN v_result;
END;
$$;

-- ── 13. Dati iniziali: Prodotti ──────────────────────────────────
INSERT INTO prodotti (codice_jit, descrizione, categoria, quantita, scorta_min) VALUES
-- Chip
('JIT-CHIP-0001', 'Chip MIFARE Classic 1K',       'Chip',      15000, 2000),
('JIT-CHIP-0002', 'Chip MIFARE DESFire EV2',       'Chip',       8000, 1000),
('JIT-CHIP-0003', 'Chip NTAG213',                  'Chip',      12000, 2000),
('JIT-CHIP-0004', 'Chip NTAG215',                  'Chip',       6000, 1000),
('JIT-CHIP-0005', 'Chip ICODE SLIX',               'Chip',       4500,  500),
('JIT-CHIP-0006', 'Chip EM4200',                   'Chip',       9000, 1500),
-- SIM
('JIT-SIMS-0001', 'SIM Card 2FF Standard',         'SIM',        5000,  500),
('JIT-SIMS-0002', 'SIM Card 3FF Micro',            'SIM',        3000,  300),
('JIT-SIMS-0003', 'SIM Card 4FF Nano',             'SIM',        2500,  300),
-- Inlay
('JIT-INLY-0001', 'Inlay Wet UHF 860-960MHz',      'Inlay',     20000, 3000),
('JIT-INLY-0002', 'Inlay Dry UHF',                 'Inlay',     15000, 2000),
('JIT-INLY-0003', 'Inlay HF 13.56MHz',             'Inlay',     10000, 1500),
-- PVC
('JIT-PVCB-0001', 'Corpo PVC Bianco CR80 0.76mm',  'PVC',       25000, 5000),
('JIT-PVCB-0002', 'Corpo PVC Trasparente CR80',    'PVC',       10000, 2000),
('JIT-PVCB-0003', 'Corpo PVC Bianco CR80 0.5mm',   'PVC',        8000, 1000),
('JIT-PVCB-0004', 'Overlay PVC Lucido 0.1mm',      'PVC',       20000, 3000),
('JIT-PVCB-0005', 'Overlay PVC Opaco 0.1mm',       'PVC',       15000, 2000),
-- Ribbon
('JIT-RBBN-0001', 'Ribbon YMCKO 250 imp',          'Ribbon',       50,   10),
('JIT-RBBN-0002', 'Ribbon YMCKK 200 imp',          'Ribbon',       30,    5),
('JIT-RBBN-0003', 'Ribbon K solo nero 1000 imp',   'Ribbon',       40,   10),
('JIT-RBBN-0004', 'Ribbon KO 500 imp',             'Ribbon',       35,    8),
-- Antenna
('JIT-ANTN-0001', 'Antenna Copper HF Ø30mm',       'Antenna',    8000, 1000),
('JIT-ANTN-0002', 'Antenna Copper HF 54x86mm',     'Antenna',    5000,  500),
('JIT-ANTN-0003', 'Antenna Aluminum UHF Dipole',   'Antenna',   12000, 2000),
-- Keyfob
('JIT-EPOX-0001', 'Keyfob Epossidico MIFARE Bianco','Keyfob',    2000,  200),
('JIT-EPOX-0002', 'Keyfob Epossidico MIFARE Nero', 'Keyfob',    1500,  200),
('JIT-EPOX-0003', 'Disco Epossidico 25mm',         'Keyfob',    3000,  300),
-- Nastro
('JIT-NSTR-0001', 'Nastro TT 110x300',             'Nastro',     200,   20),
('JIT-NSTR-0002', 'Nastro TD 57x40mm',             'Nastro',     150,   15),
-- Etichette
('JIT-ETIQ-0001', 'Etichetta NFC NTAG213 Ø30mm',   'Etichetta', 10000, 1000),
('JIT-ETIQ-0002', 'Etichetta UHF 100x50mm',        'Etichetta',  8000, 1000),
('JIT-ETIQ-0003', 'Etichetta HF 50x50mm',          'Etichetta',  6000,  500),
-- Consumabili
('JIT-CONS-0001', 'Colla epossidica 1kg',          'Consumabile',  20,    3),
('JIT-CONS-0002', 'Solvente testine 500ml',        'Consumabile',  15,    3),
('JIT-CONS-0003', 'Guanti antistatici S',          'Consumabile', 100,   20),
('JIT-CONS-0004', 'Guanti antistatici M',          'Consumabile',  80,   20),
('JIT-CONS-0005', 'Film laminazione',              'Consumabile',  30,    5),
-- Packaging
('JIT-PACK-0001', 'Busta antistatica 90x130mm',    'Packaging',  5000,  500),
('JIT-PACK-0002', 'Scatola 250x180x60mm',          'Packaging',   300,   50),
('JIT-PACK-0003', 'DDT blocchi 50ff',              'Packaging',    20,    3);

-- ═══════════════════════════════════════════════════════════════
--  FATTO! Ora crea gli utenti in Supabase:
--  Authentication → Users → Add user
-- ═══════════════════════════════════════════════════════════════
