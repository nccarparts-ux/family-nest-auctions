-- ============================================================
-- BidYard — Aggressive RLS Recursion Fix
-- Run this in Supabase SQL Editor to COMPLETELY fix RLS recursion
-- ============================================================

-- 0. DISABLE RLS ON PROFILES TABLE
ALTER TABLE profiles DISABLE ROW LEVEL SECURITY;

-- 1. DROP ALL POLICIES ON PROFILES TABLE (regardless of name)
DO $$
DECLARE
  policy_record RECORD;
BEGIN
  FOR policy_record IN
    SELECT policyname
    FROM pg_policies
    WHERE tablename = 'profiles'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON profiles', policy_record.policyname);
    RAISE NOTICE 'Dropped policy: %', policy_record.policyname;
  END LOOP;
END $$;

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

-- 4. ENABLE RLS WITH MINIMAL, NON-RECURSIVE POLICIES
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

-- 5. MAKE YOURSELF ADMIN
UPDATE profiles SET is_admin = true WHERE id = 'a290fc8a-f32e-4674-80ed-98cf2bcb6bbf';

-- 6. VERIFICATION QUERIES
SELECT 'RLS recursion fix applied' AS status;

-- Check policies
SELECT COUNT(*) AS policies_count FROM pg_policies WHERE tablename = 'profiles';

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