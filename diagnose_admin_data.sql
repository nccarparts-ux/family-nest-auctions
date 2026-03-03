-- ============================================================
-- Family Nest Auctions — Complete Admin Data Diagnostic
-- Checks table structures, data, and admin access
-- ============================================================

-- Create temporary table for results
CREATE TEMP TABLE IF NOT EXISTS admin_diagnostics (
    section TEXT,
    check_item TEXT,
    status TEXT,
    details TEXT,
    severity TEXT CHECK (severity IN ('CRITICAL', 'WARNING', 'OK', 'INFO'))
);

TRUNCATE TABLE admin_diagnostics;

-- SECTION 1: TABLE STRUCTURE CHECKS
INSERT INTO admin_diagnostics (section, check_item, status, details, severity)
SELECT
    '1. Table Structures',
    'profiles table columns',
    CASE
        WHEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'profiles' AND column_name = 'is_admin') THEN '✅ OK'
        ELSE '❌ MISSING is_admin column'
    END,
    (SELECT STRING_AGG(column_name || ' (' || data_type || ')', ', ' ORDER BY ordinal_position)
     FROM information_schema.columns WHERE table_name = 'profiles'),
    'INFO'
UNION ALL
SELECT
    '1. Table Structures',
    'sellers table columns',
    CASE
        WHEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'sellers' AND column_name = 'business_name')
         AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'sellers' AND column_name = 'city')
         AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'sellers' AND column_name = 'state')
         AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'sellers' AND column_name = 'is_verified')
         AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'sellers' AND column_name = 'status')
         AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'sellers' AND column_name = 'user_id')
        THEN '✅ OK'
        ELSE '⚠️ MISSING REQUIRED COLUMNS'
    END,
    (SELECT STRING_AGG(column_name || ' (' || data_type || ')', ', ' ORDER BY ordinal_position)
     FROM information_schema.columns WHERE table_name = 'sellers'),
    'CRITICAL'
UNION ALL
SELECT
    '1. Table Structures',
    'items table columns',
    CASE
        WHEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'items' AND column_name = 'status') THEN '✅ OK'
        ELSE '⚠️ MISSING status column'
    END,
    (SELECT STRING_AGG(column_name || ' (' || data_type || ')', ', ' ORDER BY ordinal_position)
     FROM information_schema.columns WHERE table_name = 'items'),
    'INFO'
UNION ALL
SELECT
    '1. Table Structures',
    'bids table columns',
    CASE
        WHEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'bids') THEN '✅ EXISTS'
        ELSE '❌ TABLE MISSING'
    END,
    (SELECT STRING_AGG(column_name || ' (' || data_type || ')', ', ' ORDER BY ordinal_position)
     FROM information_schema.columns WHERE table_name = 'bids'),
    'INFO'
UNION ALL
SELECT
    '1. Table Structures',
    'estate_sales table columns',
    CASE
        WHEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'estate_sales' AND column_name = 'status') THEN '✅ OK'
        ELSE '⚠️ MISSING status column'
    END,
    (SELECT STRING_AGG(column_name || ' (' || data_type || ')', ', ' ORDER BY ordinal_position)
     FROM information_schema.columns WHERE table_name = 'estate_sales'),
    'INFO';

-- SECTION 2: DATA COUNTS
INSERT INTO admin_diagnostics (section, check_item, status, details, severity)
SELECT
    '2. Data Counts',
    'profiles rows',
    CASE WHEN COUNT(*) > 0 THEN '✅ ' || COUNT(*)::text || ' rows' ELSE '⚠️ EMPTY' END,
    'Total user profiles',
    'INFO'
FROM profiles
UNION ALL
SELECT
    '2. Data Counts',
    'sellers rows',
    CASE WHEN COUNT(*) > 0 THEN '✅ ' || COUNT(*)::text || ' rows' ELSE '⚠️ EMPTY' END,
    'Verified: ' || COUNT(*) FILTER (WHERE is_verified)::text || ', Pending: ' || COUNT(*) FILTER (WHERE NOT is_verified)::text,
    'CRITICAL'
FROM sellers
UNION ALL
SELECT
    '2. Data Counts',
    'items rows (live)',
    CASE WHEN COUNT(*) > 0 THEN '✅ ' || COUNT(*)::text || ' live items' ELSE '⚠️ NO LIVE ITEMS' END,
    'Total items: ' || (SELECT COUNT(*) FROM items)::text,
    'INFO'
FROM items WHERE status = 'live'
UNION ALL
SELECT
    '2. Data Counts',
    'bids rows (today)',
    CASE WHEN COUNT(*) > 0 THEN '✅ ' || COUNT(*)::text || ' bids today' ELSE '⚠️ NO BIDS TODAY' END,
    'Total bids: ' || (SELECT COUNT(*) FROM bids)::text,
    'INFO'
FROM bids WHERE created_at >= CURRENT_DATE
UNION ALL
SELECT
    '2. Data Counts',
    'estate_sales rows (live/upcoming)',
    CASE WHEN COUNT(*) > 0 THEN '✅ ' || COUNT(*)::text || ' active sales' ELSE '⚠️ NO ACTIVE SALES' END,
    'Total estate sales: ' || (SELECT COUNT(*) FROM estate_sales)::text,
    'INFO'
FROM estate_sales WHERE status IN ('live', 'upcoming');

-- SECTION 3: ADMIN ACCESS POLICIES
INSERT INTO admin_diagnostics (section, check_item, status, details, severity)
SELECT
    '3. Admin Access Policies',
    'profiles table policies',
    CASE
        WHEN COUNT(*) > 0 THEN '✅ ' || COUNT(*)::text || ' policies'
        ELSE '❌ NO POLICIES'
    END,
    STRING_AGG(policyname || ' (' || cmd || ')', ', ' ORDER BY policyname),
    'CRITICAL'
FROM pg_policies WHERE tablename = 'profiles'
UNION ALL
SELECT
    '3. Admin Access Policies',
    'sellers table policies',
    CASE
        WHEN COUNT(*) > 0 THEN '✅ ' || COUNT(*)::text || ' policies'
        ELSE '❌ NO POLICIES'
    END,
    COALESCE(STRING_AGG(policyname || ' (' || cmd || ')', ', ' ORDER BY policyname), 'No policies found'),
    'CRITICAL'
FROM pg_policies WHERE tablename = 'sellers'
UNION ALL
SELECT
    '3. Admin Access Policies',
    'items table policies',
    CASE
        WHEN COUNT(*) > 0 THEN '✅ ' || COUNT(*)::text || ' policies'
        ELSE '❌ NO POLICIES'
    END,
    COALESCE(STRING_AGG(policyname || ' (' || cmd || ')', ', ' ORDER BY policyname), 'No policies found'),
    'CRITICAL'
FROM pg_policies WHERE tablename = 'items'
UNION ALL
SELECT
    '3. Admin Access Policies',
    'bids table policies',
    CASE
        WHEN COUNT(*) > 0 THEN '✅ ' || COUNT(*)::text || ' policies'
        ELSE '❌ NO POLICIES'
    END,
    COALESCE(STRING_AGG(policyname || ' (' || cmd || ')', ', ' ORDER BY policyname), 'No policies found'),
    'CRITICAL'
FROM pg_policies WHERE tablename = 'bids'
UNION ALL
SELECT
    '3. Admin Access Policies',
    'estate_sales table policies',
    CASE
        WHEN COUNT(*) > 0 THEN '✅ ' || COUNT(*)::text || ' policies'
        ELSE '❌ NO POLICIES'
    END,
    COALESCE(STRING_AGG(policyname || ' (' || cmd || ')', ', ' ORDER BY policyname), 'No policies found'),
    'CRITICAL'
FROM pg_policies WHERE tablename = 'estate_sales';

-- SECTION 4: ACTUAL SELLER DATA SAMPLES (for debugging)
INSERT INTO admin_diagnostics (section, check_item, status, details, severity)
SELECT
    '4. Seller Data Samples',
    'Pending sellers (first 5)',
    CASE
        WHEN COUNT(*) > 0 THEN '✅ ' || COUNT(*)::text || ' pending'
        ELSE '⚠️ NO PENDING SELLERS'
    END,
    STRING_AGG(
        COALESCE(business_name, 'NO BUSINESS NAME') ||
        ' (' || COALESCE(city || ', ' || state, 'NO LOCATION') || ')',
        ' | ' ORDER BY created_at DESC
    ),
    'INFO'
FROM sellers
WHERE NOT is_verified
LIMIT 5;

-- SECTION 5: FUNCTIONALITY CHECKS
INSERT INTO admin_diagnostics (section, check_item, status, details, severity)
SELECT
    '5. Functionality',
    'is_admin_user function',
    CASE
        WHEN EXISTS (SELECT 1 FROM information_schema.routines
                     WHERE routine_name = 'is_admin_user' AND routine_schema = 'public')
        THEN '✅ EXISTS'
        ELSE '❌ MISSING'
    END,
    (SELECT routine_definition FROM information_schema.routines
     WHERE routine_name = 'is_admin_user' AND routine_schema = 'public' LIMIT 1),
    'CRITICAL'
UNION ALL
SELECT
    '5. Functionality',
    'Your admin status',
    CASE
        WHEN EXISTS (SELECT 1 FROM profiles
                     WHERE id = 'a290fc8a-f32e-4674-80ed-98cf2bcb6bbf'
                     AND is_admin = true)
        THEN '✅ ADMIN'
        ELSE '❌ NOT ADMIN'
    END,
    (SELECT email || ' - ' || COALESCE(full_name, 'no name') FROM profiles
     WHERE id = 'a290fc8a-f32e-4674-80ed-98cf2bcb6bbf'),
    'CRITICAL';

-- Display all results in organized sections
SELECT
    section,
    check_item,
    status,
    details,
    CASE severity
        WHEN 'CRITICAL' THEN '🔴'
        WHEN 'WARNING' THEN '🟡'
        WHEN 'OK' THEN '🟢'
        ELSE '🔵'
    END || ' ' || severity as priority
FROM admin_diagnostics
ORDER BY
    CASE severity
        WHEN 'CRITICAL' THEN 1
        WHEN 'WARNING' THEN 2
        WHEN 'OK' THEN 3
        ELSE 4
    END,
    section,
    check_item;

-- Additional detailed seller info (if sellers exist)
DO $$
DECLARE
    seller_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO seller_count FROM sellers;
    IF seller_count > 0 THEN
        RAISE NOTICE '=== DETAILED SELLER INFO (first 10) ===';
        RAISE NOTICE 'ID | Business Name | City, State | Verified | Status | Created';
        RAISE NOTICE '---|---------------|-------------|----------|--------|---------';
        FOR rec IN (
            SELECT id, business_name, city, state, is_verified, status, created_at::date as created
            FROM sellers
            ORDER BY created_at DESC
            LIMIT 10
        ) LOOP
            RAISE NOTICE '% | % | %, % | % | % | %',
                LEFT(rec.id::text, 8) || '...',
                COALESCE(rec.business_name, 'NULL'),
                COALESCE(rec.city, 'NULL'),
                COALESCE(rec.state, 'NULL'),
                CASE WHEN rec.is_verified THEN 'YES' ELSE 'NO' END,
                COALESCE(rec.status, 'NULL'),
                rec.created;
        END LOOP;
    END IF;
END $$;

-- Clean up
DROP TABLE admin_diagnostics;