-- ============================================================
-- Family Nest Auctions — Admin Access Check for All Tables
-- Run this to verify admin can access all tables
-- ============================================================

-- Create temporary table for results
CREATE TEMP TABLE IF NOT EXISTS admin_access_check (
    table_name TEXT,
    has_admin_policy BOOLEAN,
    row_count INTEGER,
    can_select BOOLEAN,
    can_insert BOOLEAN,
    can_update BOOLEAN,
    can_delete BOOLEAN,
    error_message TEXT
);

TRUNCATE TABLE admin_access_check;

-- Check profiles table
INSERT INTO admin_access_check (table_name, has_admin_policy, row_count, can_select)
SELECT
    'profiles',
    EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'profiles'
        AND (qual::text LIKE '%is_admin_user%' OR qual::text LIKE '%auth.uid()%')
    ),
    (SELECT COUNT(*) FROM profiles),
    TRUE; -- Already verified

-- Check sellers table
INSERT INTO admin_access_check (table_name, has_admin_policy, row_count)
SELECT
    'sellers',
    EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'sellers'
        AND (qual::text LIKE '%is_admin_user%' OR qual::text LIKE '%auth.uid()%')
    ),
    (SELECT COUNT(*) FROM sellers);

-- Check items table
INSERT INTO admin_access_check (table_name, has_admin_policy, row_count)
SELECT
    'items',
    EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'items'
        AND (qual::text LIKE '%is_admin_user%' OR qual::text LIKE '%auth.uid()%')
    ),
    (SELECT COUNT(*) FROM items);

-- Check bids table
INSERT INTO admin_access_check (table_name, has_admin_policy, row_count)
SELECT
    'bids',
    EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'bids'
        AND (qual::text LIKE '%is_admin_user%' OR qual::text LIKE '%auth.uid()%')
    ),
    (SELECT COUNT(*) FROM bids);

-- Check estate_sales table
INSERT INTO admin_access_check (table_name, has_admin_policy, row_count)
SELECT
    'estate_sales',
    EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'estate_sales'
        AND (qual::text LIKE '%is_admin_user%' OR qual::text LIKE '%auth.uid()%')
    ),
    (SELECT COUNT(*) FROM estate_sales);

-- Test actual queries as admin user
-- Note: This runs in the context of the SQL editor (admin), not as your user
-- But it shows if admin policies exist

-- Display results
SELECT
    table_name,
    CASE WHEN has_admin_policy THEN '✅ YES' ELSE '❌ NO' END AS admin_policy_exists,
    row_count,
    CASE
        WHEN row_count > 0 THEN '✅ HAS DATA'
        WHEN row_count = 0 THEN '⚠️ EMPTY'
        ELSE '❌ ERROR'
    END AS data_status,
    CASE
        WHEN table_name = 'profiles' AND row_count > 0 THEN '✅ VERIFIED'
        WHEN table_name = 'sellers' AND row_count > 0 AND has_admin_policy THEN '✅ SHOULD WORK'
        WHEN table_name = 'sellers' AND row_count > 0 AND NOT has_admin_policy THEN '❌ NEEDS POLICY'
        WHEN table_name = 'sellers' AND row_count = 0 THEN '⚠️ NO DATA'
        ELSE 'CHECK'
    END AS admin_access_status
FROM admin_access_check
ORDER BY
    CASE table_name
        WHEN 'profiles' THEN 1
        WHEN 'sellers' THEN 2
        WHEN 'items' THEN 3
        WHEN 'bids' THEN 4
        WHEN 'estate_sales' THEN 5
        ELSE 6
    END;

-- Show seller details for debugging
SELECT '=== SELLER DETAILS ===' as info;
SELECT
    id,
    business_name,
    city || ', ' || state as location,
    is_verified,
    status,
    created_at::date as created
FROM sellers
ORDER BY created_at DESC
LIMIT 10;

-- Show what columns exist in sellers table
SELECT '=== SELLERS TABLE COLUMNS ===' as info;
SELECT
    column_name,
    data_type,
    is_nullable,
    column_default
FROM information_schema.columns
WHERE table_name = 'sellers'
ORDER BY ordinal_position;

-- Clean up
DROP TABLE admin_access_check;