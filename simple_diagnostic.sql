-- ============================================================
-- BidYard — Simple Diagnostic (No PL/pgSQL errors)
-- Run this in Supabase SQL Editor
-- ============================================================

-- 1. TABLE STRUCTURES
SELECT '1. TABLE STRUCTURES' as section;
SELECT
    table_name,
    STRING_AGG(column_name || ' (' || data_type || ')', ', ' ORDER BY ordinal_position) as columns
FROM information_schema.columns
WHERE table_name IN ('profiles', 'sellers', 'items', 'bids', 'estate_sales')
GROUP BY table_name
ORDER BY table_name;

-- 2. DATA COUNTS
SELECT '2. DATA COUNTS' as section;
SELECT 'profiles' as table_name, COUNT(*) as row_count FROM profiles
UNION ALL
SELECT 'sellers', COUNT(*) FROM sellers
UNION ALL
SELECT 'items', COUNT(*) FROM items
UNION ALL
SELECT 'bids', COUNT(*) FROM bids
UNION ALL
SELECT 'estate_sales', COUNT(*) FROM estate_sales;

-- 3. SELLER DETAILS
SELECT '3. SELLER DETAILS' as section;
SELECT
    business_name,
    city || ', ' || state as location,
    is_verified,
    status,
    created_at::date as created
FROM sellers
ORDER BY created_at DESC;

-- 4. SELLER VERIFICATION STATUS
SELECT '4. SELLER VERIFICATION STATUS' as section;
SELECT
    CASE WHEN is_verified THEN 'Verified' ELSE 'Pending' END as status,
    COUNT(*) as count
FROM sellers
GROUP BY is_verified;

-- 5. ADMIN POLICIES CHECK
SELECT '5. ADMIN POLICIES' as section;
SELECT
    tablename,
    COUNT(*) as policy_count,
    STRING_AGG(policyname || ' (' || cmd || ')', ', ' ORDER BY policyname) as policies
FROM pg_policies
WHERE tablename IN ('profiles', 'sellers', 'items', 'bids', 'estate_sales')
GROUP BY tablename
ORDER BY tablename;

-- 6. YOUR ADMIN STATUS
SELECT '6. YOUR ADMIN STATUS' as section;
SELECT
    email,
    is_admin,
    CASE WHEN is_admin THEN '✅ ADMIN' ELSE '❌ NOT ADMIN' END as status
FROM profiles
WHERE id = 'a290fc8a-f32e-4674-80ed-98cf2bcb6bbf';

-- 7. FUNCTION CHECK
SELECT '7. FUNCTION CHECK' as section;
SELECT
    routine_name,
    CASE WHEN routine_name = 'is_admin_user' THEN '✅ EXISTS' ELSE '❌ MISSING' END as status
FROM information_schema.routines
WHERE routine_name = 'is_admin_user' AND routine_schema = 'public';