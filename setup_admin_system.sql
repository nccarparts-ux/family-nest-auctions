-- ============================================================
-- Family Nest Auctions — Admin System Setup
-- Run this in Supabase SQL Editor to enable admin features
-- ============================================================

-- 1. ADD ADMIN COLUMN TO PROFILES TABLE
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS is_admin BOOLEAN DEFAULT false;

-- 2. ADD RLS POLICY FOR ADMINS TO ACCESS ALL DATA
DROP POLICY IF EXISTS "admin_full_access" ON profiles;
CREATE POLICY "admin_full_access" ON profiles
  FOR ALL USING (auth.uid() = id OR (SELECT is_admin FROM profiles WHERE id = auth.uid()))
  WITH CHECK (auth.uid() = id OR (SELECT is_admin FROM profiles WHERE id = auth.uid()));

-- 2.5 ENABLE RLS ON SELLERS TABLE IF NOT ALREADY ENABLED
ALTER TABLE sellers ENABLE ROW LEVEL SECURITY;

-- 2.6 ADD RLS POLICY FOR SELLERS TABLE (ADMIN ACCESS)
DROP POLICY IF EXISTS "sellers_admin_access" ON sellers;
CREATE POLICY "sellers_admin_access" ON sellers
  FOR ALL USING (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND is_admin = true))
  WITH CHECK (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND is_admin = true));

-- 2.7 ALLOW USERS TO INSERT THEIR OWN SELLER APPLICATIONS
DROP POLICY IF EXISTS "sellers_insert_own" ON sellers;
CREATE POLICY "sellers_insert_own" ON sellers
  FOR INSERT WITH CHECK (auth.uid() = user_id);

-- 2.8 ALLOW USERS TO SELECT THEIR OWN SELLER RECORDS
DROP POLICY IF EXISTS "sellers_select_own" ON sellers;
CREATE POLICY "sellers_select_own" ON sellers
  FOR SELECT USING (auth.uid() = user_id);

-- 3. UPDATE ADMIN APPROVE SELLER FUNCTIONALITY
-- Create a function that updates both sellers and profiles when approving a seller
CREATE OR REPLACE FUNCTION approve_seller_and_update_profile(seller_uuid UUID)
RETURNS void AS $$
BEGIN
  -- Update seller to verified and active
  UPDATE sellers
  SET is_verified = true, status = 'active'
  WHERE id = seller_uuid;

  -- Update corresponding user's profile to is_seller = true
  UPDATE profiles
  SET is_seller = true
  WHERE id = (SELECT user_id FROM sellers WHERE id = seller_uuid);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4. SET FIRST USER AS ADMIN (if needed)
-- Uncomment and update with your user ID to make yourself admin
-- UPDATE profiles SET is_admin = true WHERE id = 'your-user-id-here';

-- 6. ADD ADMIN POLICIES FOR OTHER TABLES USED IN ADMIN PANEL

-- Items table (listings)
ALTER TABLE items ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "items_admin_access" ON items;
CREATE POLICY "items_admin_access" ON items
  FOR ALL USING (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND is_admin = true))
  WITH CHECK (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND is_admin = true));

-- Bids table
ALTER TABLE bids ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "bids_admin_access" ON bids;
CREATE POLICY "bids_admin_access" ON bids
  FOR ALL USING (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND is_admin = true))
  WITH CHECK (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND is_admin = true));

-- Estate sales table
ALTER TABLE estate_sales ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "estate_sales_admin_access" ON estate_sales;
CREATE POLICY "estate_sales_admin_access" ON estate_sales
  FOR ALL USING (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND is_admin = true))
  WITH CHECK (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND is_admin = true));

-- 7. VERIFY SETUP
SELECT
  'Admin system setup complete.' AS status,
  'Run: UPDATE profiles SET is_admin = true WHERE id = (your-user-id)' AS next_step,
  'Then access admin-panel.html' AS note;