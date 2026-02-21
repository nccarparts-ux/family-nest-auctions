-- ============================================================
-- Family Nest Auctions — Database Setup & Test Data Script
-- Run this in your Supabase SQL Editor (supabase.co > SQL Editor)
-- ============================================================

-- ── 1. PROFILES TABLE ──────────────────────────────────────
CREATE TABLE IF NOT EXISTS profiles (
  id          UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name   TEXT,
  display_name TEXT,
  email       TEXT,
  phone       TEXT,
  city        TEXT,
  state       TEXT,
  zip         TEXT,
  bio         TEXT,
  avatar_url  TEXT,
  is_seller   BOOLEAN DEFAULT false,
  status      TEXT DEFAULT 'active',  -- active | suspended | banned
  notification_prefs JSONB DEFAULT '{}',
  created_at  TIMESTAMPTZ DEFAULT NOW(),
  updated_at  TIMESTAMPTZ DEFAULT NOW()
);

-- Auto-create profile on signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name, email, created_at)
  VALUES (
    NEW.id,
    NEW.raw_user_meta_data->>'full_name',
    NEW.email,
    NOW()
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- ── 2. SELLERS TABLE ───────────────────────────────────────
CREATE TABLE IF NOT EXISTS sellers (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  business_name   TEXT NOT NULL,
  contact_name    TEXT,
  contact_email   TEXT,
  phone           TEXT,
  city            TEXT,
  state           TEXT,
  years_in_business INT DEFAULT 0,
  bio             TEXT,
  is_verified     BOOLEAN DEFAULT false,
  status          TEXT DEFAULT 'pending',  -- pending | active | suspended
  bank_account_holder TEXT,
  bank_routing_last4  TEXT,
  bank_account_last4  TEXT,
  bank_account_type   TEXT DEFAULT 'checking',
  bank_updated_at     TIMESTAMPTZ,
  created_at      TIMESTAMPTZ DEFAULT NOW()
);

-- ── 3. ITEMS TABLE ─────────────────────────────────────────
CREATE TABLE IF NOT EXISTS items (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  seller_id       UUID REFERENCES sellers(id) ON DELETE CASCADE,
  title           TEXT NOT NULL,
  description     TEXT,
  category        TEXT,
  condition       TEXT,   -- excellent | good | fair | poor
  condition_notes TEXT,
  period          TEXT,
  starting_bid    NUMERIC(10,2) DEFAULT 1.00,
  reserve_price   NUMERIC(10,2),
  current_bid     NUMERIC(10,2),
  bid_count       INT DEFAULT 0,
  status          TEXT DEFAULT 'draft',  -- draft | live | ended | sold
  estate_sale_id  UUID,
  starts_at       TIMESTAMPTZ,
  ends_at         TIMESTAMPTZ,
  created_at      TIMESTAMPTZ DEFAULT NOW()
);

-- ── 4. BIDS TABLE ──────────────────────────────────────────
CREATE TABLE IF NOT EXISTS bids (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  item_id    UUID REFERENCES items(id) ON DELETE CASCADE NOT NULL,
  user_id    UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  amount     NUMERIC(10,2) NOT NULL,
  max_amount NUMERIC(10,2),   -- proxy bid ceiling
  is_winning BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ── 5. ITEM PHOTOS TABLE ───────────────────────────────────
CREATE TABLE IF NOT EXISTS item_photos (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  item_id    UUID REFERENCES items(id) ON DELETE CASCADE,
  url        TEXT NOT NULL,
  is_primary BOOLEAN DEFAULT false,
  sort_order INT DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ── 6. WATCHLIST TABLE ─────────────────────────────────────
CREATE TABLE IF NOT EXISTS watchlist (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  item_id    UUID REFERENCES items(id) ON DELETE CASCADE NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(user_id, item_id)
);

-- ── 7. MESSAGES TABLE ──────────────────────────────────────
CREATE TABLE IF NOT EXISTS messages (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  from_user_id   UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  to_user_id     UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  body           TEXT NOT NULL,
  item_ref       TEXT,   -- item title or ID for context
  read_at        TIMESTAMPTZ,
  created_at     TIMESTAMPTZ DEFAULT NOW()
);

-- ── 8. NOTIFICATIONS TABLE ─────────────────────────────────
CREATE TABLE IF NOT EXISTS notifications (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  type       TEXT,   -- outbid | won | shipped | new_listing | system
  title      TEXT,
  body       TEXT,
  item_id    UUID REFERENCES items(id) ON DELETE SET NULL,
  read_at    TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ── 9. ESTATE SALES TABLE ──────────────────────────────────
CREATE TABLE IF NOT EXISTS estate_sales (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  seller_id   UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  name        TEXT NOT NULL,
  location    TEXT,
  description TEXT,
  starts_at   DATE,
  ends_at     DATE,
  status      TEXT DEFAULT 'upcoming',  -- upcoming | live | completed
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

-- ── 10. PAYOUT REQUESTS TABLE ──────────────────────────────
CREATE TABLE IF NOT EXISTS payout_requests (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  seller_id    UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  amount       NUMERIC(10,2),
  status       TEXT DEFAULT 'pending',  -- pending | processing | paid | rejected
  note         TEXT,
  requested_at TIMESTAMPTZ DEFAULT NOW(),
  processed_at TIMESTAMPTZ
);

-- ── 11. FRANCHISE LEADS TABLE ──────────────────────────────
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

-- ── 12. REVIEWS TABLE ──────────────────────────────────────
CREATE TABLE IF NOT EXISTS reviews (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  reviewer_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  seller_id   UUID REFERENCES sellers(id) ON DELETE CASCADE,
  item_id     UUID REFERENCES items(id) ON DELETE SET NULL,
  rating      INT CHECK (rating BETWEEN 1 AND 5),
  reviewer_name TEXT,
  title       TEXT,
  body        TEXT,
  item_name   TEXT,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- ROW LEVEL SECURITY
-- ============================================================

ALTER TABLE profiles       ENABLE ROW LEVEL SECURITY;
ALTER TABLE sellers        ENABLE ROW LEVEL SECURITY;
ALTER TABLE items          ENABLE ROW LEVEL SECURITY;
ALTER TABLE bids           ENABLE ROW LEVEL SECURITY;
ALTER TABLE item_photos    ENABLE ROW LEVEL SECURITY;
ALTER TABLE watchlist      ENABLE ROW LEVEL SECURITY;
ALTER TABLE messages       ENABLE ROW LEVEL SECURITY;
ALTER TABLE notifications  ENABLE ROW LEVEL SECURITY;
ALTER TABLE estate_sales   ENABLE ROW LEVEL SECURITY;
ALTER TABLE payout_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE franchise_leads ENABLE ROW LEVEL SECURITY;
ALTER TABLE reviews        ENABLE ROW LEVEL SECURITY;

-- Profiles: own row full access; others can read
DROP POLICY IF EXISTS "profiles_own_access" ON profiles;
CREATE POLICY "profiles_own_access" ON profiles FOR ALL USING (auth.uid() = id) WITH CHECK (auth.uid() = id);
DROP POLICY IF EXISTS "profiles_public_read" ON profiles;
CREATE POLICY "profiles_public_read" ON profiles FOR SELECT USING (true);

-- Sellers: public read; own/admin write
DROP POLICY IF EXISTS "sellers_public_read" ON sellers;
CREATE POLICY "sellers_public_read" ON sellers FOR SELECT USING (true);
DROP POLICY IF EXISTS "sellers_own_insert" ON sellers;
CREATE POLICY "sellers_own_insert" ON sellers FOR INSERT WITH CHECK (auth.uid() = user_id OR user_id IS NULL);
DROP POLICY IF EXISTS "sellers_own_update" ON sellers;
CREATE POLICY "sellers_own_update" ON sellers FOR UPDATE USING (auth.uid() = user_id OR user_id IS NULL);

-- Items: public read; seller can insert/update own
DROP POLICY IF EXISTS "items_public_read" ON items;
CREATE POLICY "items_public_read" ON items FOR SELECT USING (true);
DROP POLICY IF EXISTS "items_seller_write" ON items;
CREATE POLICY "items_seller_write" ON items FOR INSERT WITH CHECK (
  EXISTS (SELECT 1 FROM sellers s WHERE s.id = seller_id AND s.user_id = auth.uid())
);
DROP POLICY IF EXISTS "items_seller_update" ON items;
CREATE POLICY "items_seller_update" ON items FOR UPDATE USING (
  EXISTS (SELECT 1 FROM sellers s WHERE s.id = seller_id AND s.user_id = auth.uid())
);

-- Bids: any authenticated user can bid; read own + item bids
DROP POLICY IF EXISTS "bids_read" ON bids;
CREATE POLICY "bids_read" ON bids FOR SELECT USING (true);
DROP POLICY IF EXISTS "bids_insert" ON bids;
CREATE POLICY "bids_insert" ON bids FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Watchlist: own rows only
DROP POLICY IF EXISTS "watchlist_own" ON watchlist;
CREATE POLICY "watchlist_own" ON watchlist FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

-- Messages: parties can read/write
DROP POLICY IF EXISTS "messages_parties" ON messages;
CREATE POLICY "messages_parties" ON messages FOR SELECT USING (auth.uid() = from_user_id OR auth.uid() = to_user_id);
DROP POLICY IF EXISTS "messages_insert" ON messages;
CREATE POLICY "messages_insert" ON messages FOR INSERT WITH CHECK (auth.uid() = from_user_id);
DROP POLICY IF EXISTS "messages_read_update" ON messages;
CREATE POLICY "messages_read_update" ON messages FOR UPDATE USING (auth.uid() = to_user_id);

-- Notifications: own only
DROP POLICY IF EXISTS "notifications_own" ON notifications;
CREATE POLICY "notifications_own" ON notifications FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

-- Estate sales: public read; seller write
DROP POLICY IF EXISTS "estate_sales_read" ON estate_sales;
CREATE POLICY "estate_sales_read" ON estate_sales FOR SELECT USING (true);
DROP POLICY IF EXISTS "estate_sales_write" ON estate_sales;
CREATE POLICY "estate_sales_write" ON estate_sales FOR INSERT WITH CHECK (auth.uid() = seller_id);

-- Payout requests: seller own
DROP POLICY IF EXISTS "payout_requests_own" ON payout_requests;
CREATE POLICY "payout_requests_own" ON payout_requests FOR ALL USING (auth.uid() = seller_id) WITH CHECK (auth.uid() = seller_id);

-- Franchise leads: insert open, read own
DROP POLICY IF EXISTS "franchise_leads_insert" ON franchise_leads;
CREATE POLICY "franchise_leads_insert" ON franchise_leads FOR INSERT WITH CHECK (true);
DROP POLICY IF EXISTS "franchise_leads_own_read" ON franchise_leads;
CREATE POLICY "franchise_leads_own_read" ON franchise_leads FOR SELECT USING (auth.uid() = user_id);

-- Reviews: public read; authenticated insert
DROP POLICY IF EXISTS "reviews_public_read" ON reviews;
CREATE POLICY "reviews_public_read" ON reviews FOR SELECT USING (true);
DROP POLICY IF EXISTS "reviews_auth_insert" ON reviews;
CREATE POLICY "reviews_auth_insert" ON reviews FOR INSERT WITH CHECK (auth.uid() = reviewer_id);

-- Item photos: public read
DROP POLICY IF EXISTS "item_photos_read" ON item_photos;
CREATE POLICY "item_photos_read" ON item_photos FOR SELECT USING (true);

-- ============================================================
-- SEED DATA — 3 Sample Reviews (for homepage reviews section)
-- ============================================================

-- First, create a placeholder seller for seeded reviews:
INSERT INTO sellers (id, business_name, city, state, is_verified, status)
VALUES ('00000000-0000-0000-0000-000000000001', 'Henderson Estate Sales', 'Atlanta', 'GA', true, 'active')
ON CONFLICT (id) DO NOTHING;

INSERT INTO reviews (reviewer_name, item_name, rating, title, body, seller_id, created_at)
VALUES
  (
    'Jennifer M.',
    'Victorian Carved Mahogany Armchair',
    5,
    'Absolutely stunning — exactly as described',
    'Beautiful piece arrived exactly as described, packed incredibly well. The condition photos were spot-on, no surprises. The seller communicated throughout the process. Will definitely buy from this estate again!',
    '00000000-0000-0000-0000-000000000001',
    NOW() - INTERVAL '3 days'
  ),
  (
    'Robert P.',
    'Sterling Silver Tea Service',
    5,
    'Best estate auction experience I have had',
    'Fast shipping, extremely well packaged, item exactly as described. The price transparency upfront is a huge plus — no surprises at checkout. Family Nest sets the standard for online estate auctions.',
    '00000000-0000-0000-0000-000000000001',
    NOW() - INTERVAL '5 days'
  ),
  (
    'Sarah K.',
    'Persian Wool Rug 8x10',
    4,
    'Great item, proactive communication',
    'Item was in great condition. Shipping took a couple extra days beyond the stated window, but the seller communicated proactively about the delay. Very happy with the purchase overall.',
    '00000000-0000-0000-0000-000000000001',
    NOW() - INTERVAL '7 days'
  )
ON CONFLICT DO NOTHING;

-- ============================================================
-- HOW TO PROMOTE A USER TO SELLER STATUS
-- ============================================================
-- After a user signs up at family-nest-auctions.html, run:
--
--   UPDATE profiles SET is_seller = true WHERE email = 'seller@example.com';
--
--   INSERT INTO sellers (user_id, business_name, city, state, is_verified, status)
--   SELECT id, 'My Estate Sales', 'Atlanta', 'GA', true, 'active'
--   FROM auth.users WHERE email = 'seller@example.com'
--   ON CONFLICT DO NOTHING;
--
-- The seller can then log in and access seller-dashboard.html
-- ============================================================

-- ============================================================
-- STORAGE BUCKETS (run in Supabase Dashboard > Storage, or via CLI)
-- ============================================================
-- Create bucket: "item-photos"  (public)
-- Create bucket: "avatars"      (public)
--
-- Or via SQL (requires storage extension):
-- INSERT INTO storage.buckets (id, name, public)
-- VALUES ('item-photos', 'item-photos', true), ('avatars', 'avatars', true)
-- ON CONFLICT (id) DO NOTHING;
--
-- Storage RLS policies for item-photos:
-- SELECT: public
-- INSERT: auth.role() = 'authenticated'
-- ============================================================

-- ============================================================
-- REALTIME SUBSCRIPTIONS
-- Enable realtime on these tables in Supabase Dashboard:
--   Database > Replication > Supabase Realtime > Enable for:
--     bids, messages, notifications, items
-- ============================================================

SELECT 'Family Nest Auctions database setup complete!' AS status;
