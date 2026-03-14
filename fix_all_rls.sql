-- ============================================================
-- BidYard — Complete RLS Fix for All Tables
-- Run this in Supabase SQL Editor to fix RLS recursion everywhere
-- ============================================================

-- Helper function to drop all policies on a table
CREATE OR REPLACE FUNCTION drop_all_policies_on_table(target_table TEXT)
RETURNS void AS $$
DECLARE
  policy_record RECORD;
BEGIN
  FOR policy_record IN
    SELECT policyname
    FROM pg_policies
    WHERE tablename = target_table
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON %I', policy_record.policyname, target_table);
    RAISE NOTICE 'Dropped policy: % on table %', policy_record.policyname, target_table;
  END LOOP;
END;
$$ LANGUAGE plpgsql;

-- 0. DISABLE RLS ON PROFILES TABLE FIRST
ALTER TABLE profiles DISABLE ROW LEVEL SECURITY;

-- 1. DROP ALL POLICIES ON PROFILES TABLE
SELECT drop_all_policies_on_table('profiles');

-- 2. ADD ADMIN COLUMN IF NOT EXISTS
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS is_admin BOOLEAN DEFAULT false;

-- 3. CREATE SECURITY DEFINER FUNCTION TO CHECK ADMIN STATUS
CREATE OR REPLACE FUNCTION is_admin_user(user_id UUID)
RETURNS BOOLEAN AS $$
DECLARE
  admin_status BOOLEAN;
BEGIN
  SELECT is_admin INTO admin_status
  FROM profiles
  WHERE id = user_id;

  RETURN COALESCE(admin_status, false);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4. ENABLE RLS WITH MINIMAL, NON-RECURSIVE POLICIES FOR PROFILES
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

-- Users can select their own profile
CREATE POLICY "profiles_select_own" ON profiles
  FOR SELECT USING (auth.uid() = id);

-- Users can update their own profile
CREATE POLICY "profiles_update_own" ON profiles
  FOR UPDATE USING (auth.uid() = id);

-- Users can insert their own profile (for initial signup)
CREATE POLICY "profiles_insert_own" ON profiles
  FOR INSERT WITH CHECK (auth.uid() = id);

-- Admins can do everything (using the non-recursive function)
CREATE POLICY "profiles_admin_all" ON profiles
  FOR ALL USING (is_admin_user(auth.uid()));

-- 5. FIX POLICIES FOR OTHER TABLES

-- Sellers table
ALTER TABLE sellers ENABLE ROW LEVEL SECURITY;
SELECT drop_all_policies_on_table('sellers');
CREATE POLICY "sellers_admin_access" ON sellers
  FOR ALL USING (is_admin_user(auth.uid()))
  WITH CHECK (is_admin_user(auth.uid()));
CREATE POLICY "sellers_insert_own" ON sellers
  FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "sellers_select_own" ON sellers
  FOR SELECT USING (auth.uid() = user_id);

-- Items table
ALTER TABLE items ENABLE ROW LEVEL SECURITY;
SELECT drop_all_policies_on_table('items');
CREATE POLICY "items_admin_access" ON items
  FOR ALL USING (is_admin_user(auth.uid()))
  WITH CHECK (is_admin_user(auth.uid()));

-- Bids table
ALTER TABLE bids ENABLE ROW LEVEL SECURITY;
SELECT drop_all_policies_on_table('bids');
CREATE POLICY "bids_admin_access" ON bids
  FOR ALL USING (is_admin_user(auth.uid()))
  WITH CHECK (is_admin_user(auth.uid()));

-- Estate sales table
ALTER TABLE estate_sales ENABLE ROW LEVEL SECURITY;
SELECT drop_all_policies_on_table('estate_sales');
CREATE POLICY "estate_sales_admin_access" ON estate_sales
  FOR ALL USING (is_admin_user(auth.uid()))
  WITH CHECK (is_admin_user(auth.uid()));

-- 6. MAKE YOURSELF ADMIN
UPDATE profiles SET is_admin = true WHERE id = 'a290fc8a-f32e-4674-80ed-98cf2bcb6bbf';

-- 7. VERIFICATION
SELECT 'Complete RLS fix applied to all tables' AS status;

-- Check profile policies
SELECT tablename, policyname, cmd, qual
FROM pg_policies
WHERE tablename IN ('profiles', 'sellers', 'items', 'bids', 'estate_sales')
ORDER BY tablename, policyname;

-- Check your admin status
SELECT
  id,
  email,
  is_admin,
  'You are now admin' AS status
FROM profiles
WHERE id = 'a290fc8a-f32e-4674-80ed-98cf2bcb6bbf';

-- Test query that should work without recursion
SELECT 'Test query successful' AS result
FROM profiles
WHERE id = 'a290fc8a-f32e-4674-80ed-98cf2bcb6bbf' AND is_admin = true;

-- Clean up helper function
DROP FUNCTION drop_all_policies_on_table(TEXT);