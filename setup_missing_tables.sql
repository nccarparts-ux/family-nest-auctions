-- ============================================================
-- Family Nest Auctions — Missing Tables & Schema Additions
-- Run this ONCE in Supabase SQL Editor
-- ============================================================

-- ── Add missing display columns to reviews table ──
ALTER TABLE reviews ADD COLUMN IF NOT EXISTS reviewer_name TEXT;
ALTER TABLE reviews ADD COLUMN IF NOT EXISTS title         TEXT;
ALTER TABLE reviews ADD COLUMN IF NOT EXISTS item_name     TEXT;

-- ── Add bio to profiles (for account profile page) ──
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS bio TEXT;

-- ── Add bank payout columns to sellers ──
ALTER TABLE sellers ADD COLUMN IF NOT EXISTS bank_account_holder TEXT;
ALTER TABLE sellers ADD COLUMN IF NOT EXISTS bank_routing_last4  TEXT;
ALTER TABLE sellers ADD COLUMN IF NOT EXISTS bank_account_last4  TEXT;
ALTER TABLE sellers ADD COLUMN IF NOT EXISTS bank_account_type   TEXT DEFAULT 'checking';
ALTER TABLE sellers ADD COLUMN IF NOT EXISTS bank_updated_at     TIMESTAMPTZ;

-- ── 1. MESSAGES TABLE ──────────────────────────────────────
CREATE TABLE IF NOT EXISTS messages (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  from_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  to_user_id   UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  body         TEXT NOT NULL,
  subject      TEXT,
  item_ref     TEXT,     -- item title / ID for context
  read_at      TIMESTAMPTZ,  -- NULL = unread
  created_at   TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE messages ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "messages_parties_read" ON messages;
CREATE POLICY "messages_parties_read" ON messages
  FOR SELECT USING (auth.uid() = from_user_id OR auth.uid() = to_user_id);

DROP POLICY IF EXISTS "messages_insert" ON messages;
CREATE POLICY "messages_insert" ON messages
  FOR INSERT WITH CHECK (auth.uid() = from_user_id);

DROP POLICY IF EXISTS "messages_mark_read" ON messages;
CREATE POLICY "messages_mark_read" ON messages
  FOR UPDATE USING (auth.uid() = to_user_id);

-- ── 2. PAYOUT REQUESTS TABLE ────────────────────────────────
CREATE TABLE IF NOT EXISTS payout_requests (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  seller_id    UUID REFERENCES sellers(id) ON DELETE CASCADE,
  amount       NUMERIC(10,2),
  status       TEXT DEFAULT 'pending',  -- pending | processing | paid | rejected
  note         TEXT,
  requested_at TIMESTAMPTZ DEFAULT NOW(),
  processed_at TIMESTAMPTZ
);

ALTER TABLE payout_requests ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "payout_requests_own" ON payout_requests;
CREATE POLICY "payout_requests_own" ON payout_requests
  FOR ALL
  USING (EXISTS (SELECT 1 FROM sellers s WHERE s.id = seller_id AND s.user_id = auth.uid()))
  WITH CHECK (EXISTS (SELECT 1 FROM sellers s WHERE s.id = seller_id AND s.user_id = auth.uid()));

-- ── 3. FRANCHISE LEADS TABLE ────────────────────────────────
CREATE TABLE IF NOT EXISTS franchise_leads (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id          UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  name             TEXT,
  email            TEXT,
  region           TEXT,
  years_experience INT DEFAULT 0,
  message          TEXT,
  submitted_at     TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE franchise_leads ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "franchise_leads_insert" ON franchise_leads;
CREATE POLICY "franchise_leads_insert" ON franchise_leads
  FOR INSERT WITH CHECK (true);

DROP POLICY IF EXISTS "franchise_leads_own_read" ON franchise_leads;
CREATE POLICY "franchise_leads_own_read" ON franchise_leads
  FOR SELECT USING (auth.uid() = user_id);

-- ── 4. REALTIME ─────────────────────────────────────────────
-- Enable realtime on live-data tables
-- (safe to run even if already added)
DO $$
BEGIN
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE bids;
  EXCEPTION WHEN duplicate_object THEN NULL;
  END;
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE messages;
  EXCEPTION WHEN duplicate_object THEN NULL;
  END;
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE notifications;
  EXCEPTION WHEN duplicate_object THEN NULL;
  END;
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE items;
  EXCEPTION WHEN duplicate_object THEN NULL;
  END;
END $$;

-- ── 5. STORAGE POLICIES ─────────────────────────────────────
-- Ensure buckets exist as public
INSERT INTO storage.buckets (id, name, public)
VALUES ('item-photos', 'item-photos', true)
ON CONFLICT (id) DO UPDATE SET public = true;

INSERT INTO storage.buckets (id, name, public)
VALUES ('avatars', 'avatars', true)
ON CONFLICT (id) DO UPDATE SET public = true;

-- item-photos: public read, authenticated upload/delete
DROP POLICY IF EXISTS "item_photos_public_read"  ON storage.objects;
CREATE POLICY "item_photos_public_read" ON storage.objects
  FOR SELECT USING (bucket_id = 'item-photos');

DROP POLICY IF EXISTS "item_photos_auth_upload"  ON storage.objects;
CREATE POLICY "item_photos_auth_upload" ON storage.objects
  FOR INSERT WITH CHECK (bucket_id = 'item-photos' AND auth.role() = 'authenticated');

DROP POLICY IF EXISTS "item_photos_owner_delete" ON storage.objects;
CREATE POLICY "item_photos_owner_delete" ON storage.objects
  FOR DELETE USING (bucket_id = 'item-photos' AND auth.uid()::text = (storage.foldername(name))[1]);

-- avatars: public read, authenticated upload/update
DROP POLICY IF EXISTS "avatars_public_read"   ON storage.objects;
CREATE POLICY "avatars_public_read" ON storage.objects
  FOR SELECT USING (bucket_id = 'avatars');

DROP POLICY IF EXISTS "avatars_auth_upload"   ON storage.objects;
CREATE POLICY "avatars_auth_upload" ON storage.objects
  FOR INSERT WITH CHECK (bucket_id = 'avatars' AND auth.role() = 'authenticated');

DROP POLICY IF EXISTS "avatars_owner_update"  ON storage.objects;
CREATE POLICY "avatars_owner_update" ON storage.objects
  FOR UPDATE USING (bucket_id = 'avatars' AND auth.uid()::text = (storage.foldername(name))[1]);

SELECT 'Family Nest Auctions — missing tables & schema additions applied!' AS status;
