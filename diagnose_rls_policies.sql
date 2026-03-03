-- ============================================================
-- Family Nest Auctions — RLS Policy Diagnostic
-- Run this in Supabase SQL Editor to check current RLS state
-- ============================================================

-- 1. CHECK IF is_admin COLUMN EXISTS
SELECT
  column_name,
  data_type,
  is_nullable,
  column_default
FROM information_schema.columns
WHERE table_name = 'profiles'
  AND column_name = 'is_admin';

-- 2. CHECK CURRENT RLS STATUS FOR PROFILES TABLE
SELECT
  schemaname,
  tablename,
  rowsecurity
FROM pg_tables
WHERE tablename = 'profiles';

-- 3. LIST ALL POLICIES ON PROFILES TABLE
SELECT
  schemaname,
  tablename,
  policyname,
  permissive,
  roles,
  cmd,
  qual,
  with_check
FROM pg_policies
WHERE tablename = 'profiles'
ORDER BY policyname;

-- 4. CHECK IF is_admin_user FUNCTION EXISTS
SELECT
  routine_name,
  routine_type,
  data_type,
  routine_definition
FROM information_schema.routines
WHERE routine_name = 'is_admin_user'
  AND routine_schema = 'public';

-- 5. CHECK YOUR USER'S ADMIN STATUS
SELECT
  id,
  email,
  is_admin,
  created_at
FROM profiles
WHERE id = 'a290fc8a-f32e-4674-80ed-98cf2bcb6bbf';

-- 6. CHECK FOR RECURSIVE POLICIES (look for subqueries to profiles table)
SELECT
  policyname,
  qual,
  with_check
FROM pg_policies
WHERE tablename = 'profiles'
  AND (qual::text LIKE '%profiles%' OR with_check::text LIKE '%profiles%');

-- 7. SIMPLE TEST QUERY (should work if RLS is configured correctly)
-- This should return your user's is_admin status
SELECT is_admin FROM profiles WHERE id = 'a290fc8a-f32e-4674-80ed-98cf2bcb6bbf';