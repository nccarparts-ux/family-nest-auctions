-- ============================================================
-- Family Nest Auctions — Complete RLS Diagnostic (Single Result Set)
-- Run this in Supabase SQL Editor to see ALL diagnostic info
-- ============================================================

-- Create a temporary table to collect all diagnostic results
CREATE TEMP TABLE IF NOT EXISTS rls_diagnostics (
    section TEXT,
    item TEXT,
    value TEXT,
    details TEXT
);

-- Clear any existing data
TRUNCATE TABLE rls_diagnostics;

-- 1. CHECK IF is_admin COLUMN EXISTS
INSERT INTO rls_diagnostics (section, item, value, details)
SELECT
    '1. is_admin column',
    column_name,
    data_type,
    'Nullable: ' || is_nullable || ', Default: ' || COALESCE(column_default, 'none')
FROM information_schema.columns
WHERE table_name = 'profiles'
  AND column_name = 'is_admin';

-- 2. CHECK CURRENT RLS STATUS FOR PROFILES TABLE
INSERT INTO rls_diagnostics (section, item, value, details)
SELECT
    '2. RLS status for profiles',
    tablename,
    CASE WHEN rowsecurity THEN 'ENABLED' ELSE 'DISABLED' END,
    'Schema: ' || schemaname
FROM pg_tables
WHERE tablename = 'profiles';

-- 3. LIST ALL POLICIES ON PROFILES TABLE
INSERT INTO rls_diagnostics (section, item, value, details)
SELECT
    '3. Policies on profiles',
    policyname,
    cmd || ' (' || permissive || ')',
    'Roles: ' || COALESCE(roles::text, 'all') || ', Qual: ' || COALESCE(qual::text, 'none')
FROM pg_policies
WHERE tablename = 'profiles'
ORDER BY policyname;

-- 4. CHECK IF is_admin_user FUNCTION EXISTS
INSERT INTO rls_diagnostics (section, item, value, details)
SELECT
    '4. is_admin_user function',
    routine_name,
    routine_type || ' -> ' || data_type,
    'Definition length: ' || LENGTH(COALESCE(routine_definition, ''))::text
FROM information_schema.routines
WHERE routine_name = 'is_admin_user'
  AND routine_schema = 'public';

-- 5. CHECK YOUR USER'S ADMIN STATUS
INSERT INTO rls_diagnostics (section, item, value, details)
SELECT
    '5. Your admin status',
    email,
    CASE WHEN is_admin THEN 'ADMIN' ELSE 'NOT ADMIN' END,
    'User ID: ' || id || ', Created: ' || created_at::date
FROM profiles
WHERE id = 'a290fc8a-f32e-4674-80ed-98cf2bcb6bbf';

-- 6. CHECK FOR RECURSIVE POLICIES (look for subqueries to profiles table)
INSERT INTO rls_diagnostics (section, item, value, details)
SELECT
    '6. Recursive policies check',
    policyname,
    'RECURSIVE DETECTED',
    'Qual contains profiles ref: ' || COALESCE(qual::text, 'none')
FROM pg_policies
WHERE tablename = 'profiles'
  AND (qual::text LIKE '%profiles%' OR with_check::text LIKE '%profiles%');

-- 7. ADD COUNTS FOR EMPTY SECTIONS
INSERT INTO rls_diagnostics (section, item, value, details)
SELECT '0. Diagnostic summary', 'Total policies on profiles', COUNT(*)::text, ''
FROM pg_policies WHERE tablename = 'profiles';

INSERT INTO rls_diagnostics (section, item, value, details)
SELECT '0. Diagnostic summary', 'is_admin column exists',
    CASE WHEN EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'profiles' AND column_name = 'is_admin'
    ) THEN 'YES' ELSE 'NO' END, '';

INSERT INTO rls_diagnostics (section, item, value, details)
SELECT '0. Diagnostic summary', 'is_admin_user function exists',
    CASE WHEN EXISTS (
        SELECT 1 FROM information_schema.routines
        WHERE routine_name = 'is_admin_user' AND routine_schema = 'public'
    ) THEN 'YES' ELSE 'NO' END, '';

-- Display all results
SELECT section, item, value, details
FROM rls_diagnostics
ORDER BY
    CASE
        WHEN section LIKE '0.%' THEN 1
        WHEN section LIKE '1.%' THEN 2
        WHEN section LIKE '2.%' THEN 3
        WHEN section LIKE '3.%' THEN 4
        WHEN section LIKE '4.%' THEN 5
        WHEN section LIKE '5.%' THEN 6
        WHEN section LIKE '6.%' THEN 7
        ELSE 8
    END,
    item;

-- Clean up
DROP TABLE rls_diagnostics;