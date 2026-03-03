-- ============================================================
-- Family Nest Auctions — Fix RLS Recursion NOW
-- Run this ONE script in Supabase SQL Editor to fix everything
-- ============================================================

-- First, disable RLS on profiles table to break recursion
ALTER TABLE profiles DISABLE ROW LEVEL SECURITY;

-- Drop ALL policies on profiles table (one by one)
DO $$
DECLARE
    policy_name TEXT;
BEGIN
    FOR policy_name IN
        SELECT policyname
        FROM pg_policies
        WHERE tablename = 'profiles'
    LOOP
        EXECUTE 'DROP POLICY IF EXISTS "' || policy_name || '" ON profiles';
        RAISE NOTICE 'Dropped policy: %', policy_name;
    END LOOP;
END $$;

-- Ensure is_admin column exists
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS is_admin BOOLEAN DEFAULT false;

-- Create or replace the SECURITY DEFINER function
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

-- Re-enable RLS with NON-RECURSIVE policies
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

-- Policy 1: Users can select their own profile
CREATE POLICY "profiles_select_own" ON profiles
    FOR SELECT USING (auth.uid() = id);

-- Policy 2: Users can update their own profile
CREATE POLICY "profiles_update_own" ON profiles
    FOR UPDATE USING (auth.uid() = id);

-- Policy 3: Users can insert their own profile
CREATE POLICY "profiles_insert_own" ON profiles
    FOR INSERT WITH CHECK (auth.uid() = id);

-- Policy 4: Admins can do everything (uses SECURITY DEFINER function)
CREATE POLICY "profiles_admin_all" ON profiles
    FOR ALL USING (is_admin_user(auth.uid()));

-- Make yourself ADMIN
UPDATE profiles SET is_admin = true WHERE id = 'a290fc8a-f32e-4674-80ed-98cf2bcb6bbf';

-- ============================================================
-- VERIFICATION SECTION - This will show if the fix worked
-- ============================================================

-- Check 1: Show your admin status
SELECT '1. Your admin status' AS check,
       id AS user_id,
       email,
       CASE WHEN is_admin THEN '✅ ADMIN' ELSE '❌ NOT ADMIN' END AS status
FROM profiles
WHERE id = 'a290fc8a-f32e-4674-80ed-98cf2bcb6bbf';

-- Check 2: List all policies on profiles table
SELECT '2. Policies on profiles' AS check,
       policyname,
       cmd,
       CASE
           WHEN qual::text LIKE '%profiles%' THEN '⚠️ RECURSIVE'
           WHEN qual::text LIKE '%is_admin_user%' THEN '✅ SAFE (uses function)'
           ELSE '✅ OK'
       END AS recursion_check
FROM pg_policies
WHERE tablename = 'profiles'
ORDER BY policyname;

-- Check 3: Test query that should work without recursion
SELECT '3. Test query result' AS check,
       CASE
           WHEN EXISTS (
               SELECT 1 FROM profiles
               WHERE id = 'a290fc8a-f32e-4674-80ed-98cf2bcb6bbf'
               AND is_admin = true
           ) THEN '✅ Query successful - no recursion'
           ELSE '❌ Query failed or user not admin'
       END AS result;

-- Check 4: Show RLS status
SELECT '4. RLS status' AS check,
       tablename,
       CASE WHEN rowsecurity THEN '✅ ENABLED' ELSE '❌ DISABLED' END AS status
FROM pg_tables
WHERE tablename = 'profiles';

-- Final message
SELECT '========================================' AS " ";
SELECT 'FIX COMPLETE' AS " ";
SELECT '========================================' AS " ";
SELECT 'If you see "✅ SAFE (uses function)" for all policies,' AS " ";
SELECT 'and "✅ Query successful - no recursion", then the fix worked.' AS " ";
SELECT ' ' AS " ";
SELECT 'Refresh the admin panel page to test.' AS " ";