-- ============================================================
-- Family Nest Auctions — Quick Admin Fix
-- Run this in Supabase SQL Editor to temporarily fix admin access
-- WARNING: This disables RLS on profiles - only for development!
-- ============================================================

-- 1. DISABLE RLS ON PROFILES TABLE (temporary fix)
ALTER TABLE profiles DISABLE ROW LEVEL SECURITY;

-- 2. ADD is_admin COLUMN IF NOT EXISTS
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS is_admin BOOLEAN DEFAULT false;

-- 3. MAKE YOURSELF ADMIN
UPDATE profiles SET is_admin = true WHERE id = 'a290fc8a-f32e-4674-80ed-98cf2bcb6bbf';

-- 4. VERIFY
SELECT
  'RLS disabled on profiles table' as status,
  id,
  email,
  is_admin
FROM profiles
WHERE id = 'a290fc8a-f32e-4674-80ed-98cf2bcb6bbf';

-- 5. ENABLE ADMIN ACCESS TO OTHER TABLES (simplified)
-- Sellers table
ALTER TABLE sellers ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "sellers_admin_access" ON sellers;
CREATE POLICY "sellers_admin_access" ON sellers
  FOR ALL USING (true);

-- Items table
ALTER TABLE items ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "items_admin_access" ON items;
CREATE POLICY "items_admin_access" ON items
  FOR ALL USING (true);

-- Bids table
ALTER TABLE bids ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "bids_admin_access" ON bids;
CREATE POLICY "bids_admin_access" ON bids
  FOR ALL USING (true);

-- Estate sales table
ALTER TABLE estate_sales ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "estate_sales_admin_access" ON estate_sales;
CREATE POLICY "estate_sales_admin_access" ON estate_sales
  FOR ALL USING (true);

SELECT 'Quick fix applied. Admin panel should now work.' as message;