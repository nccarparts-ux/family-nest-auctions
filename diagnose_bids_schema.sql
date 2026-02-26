-- ============================================================
-- Family Nest Auctions — Diagnose Bids Table Schema
-- Run this in Supabase SQL Editor to see actual schema
-- ============================================================

-- 1. SHOW BIDS TABLE COLUMNS AND CONSTRAINTS
SELECT
    c.column_name,
    c.data_type,
    c.is_nullable,
    c.column_default,
    tc.constraint_type,
    tc.constraint_name,
    ccu.table_schema AS foreign_table_schema,
    ccu.table_name AS foreign_table_name,
    ccu.column_name AS foreign_column_name
FROM information_schema.columns c
LEFT JOIN information_schema.constraint_column_usage ccu_join
    ON c.table_schema = ccu_join.table_schema
    AND c.table_name = ccu_join.table_name
    AND c.column_name = ccu_join.column_name
LEFT JOIN information_schema.table_constraints tc
    ON ccu_join.constraint_name = tc.constraint_name
    AND tc.table_schema = c.table_schema
    AND tc.table_name = c.table_name
LEFT JOIN information_schema.constraint_column_usage ccu
    ON tc.constraint_name = ccu.constraint_name
WHERE c.table_schema = 'public'
    AND c.table_name = 'bids'
ORDER BY c.ordinal_position;

-- 2. SHOW NOT NULL CONSTRAINTS ON BIDS
SELECT
    c.column_name,
    c.is_nullable
FROM information_schema.columns c
WHERE c.table_schema = 'public'
    AND c.table_name = 'bids'
    AND c.is_nullable = 'NO'
ORDER BY c.column_name;

-- 3. SHOW CHECK CONSTRAINTS ON BIDS
SELECT
    tc.constraint_name,
    cc.check_clause
FROM information_schema.table_constraints tc
JOIN information_schema.check_constraints cc
    ON tc.constraint_name = cc.constraint_name
WHERE tc.table_schema = 'public'
    AND tc.table_name = 'bids'
    AND tc.constraint_type = 'CHECK';

-- 4. SHOW FOREIGN KEY CONSTRAINTS ON BIDS
SELECT
    tc.constraint_name,
    kcu.column_name,
    ccu.table_schema AS foreign_table_schema,
    ccu.table_name AS foreign_table_name,
    ccu.column_name AS foreign_column_name
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu
    ON tc.constraint_name = kcu.constraint_name
    AND tc.table_schema = kcu.table_schema
JOIN information_schema.constraint_column_usage ccu
    ON ccu.constraint_name = tc.constraint_name
WHERE tc.constraint_type = 'FOREIGN KEY'
    AND tc.table_schema = 'public'
    AND tc.table_name = 'bids';

-- 5. SHOW DEFAULT VALUES FOR BIDS COLUMNS
SELECT
    column_name,
    column_default
FROM information_schema.columns
WHERE table_schema = 'public'
    AND table_name = 'bids'
    AND column_default IS NOT NULL;

-- 6. SHOW TRIGGERS ON BIDS TABLE
SELECT
    trigger_name,
    event_manipulation,
    action_statement,
    action_timing
FROM information_schema.triggers
WHERE event_object_schema = 'public'
    AND event_object_table = 'bids';

-- 7. SHOW INDEXES ON BIDS TABLE
SELECT
    indexname,
    indexdef
FROM pg_indexes
WHERE schemaname = 'public'
    AND tablename = 'bids';

-- 8. TEST INSERT TO SEE WHAT COLUMNS ARE REQUIRED
-- (This will fail but show the exact error)
DO $$
BEGIN
    RAISE NOTICE 'Testing insert...';
    INSERT INTO bids (item_id, user_id, amount, is_winning)
    VALUES ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 100.00, true);
EXCEPTION WHEN others THEN
    RAISE NOTICE 'Insert error: %', SQLERRM;
END $$;

-- 9. SHOW RECENT BIDS (IF ANY EXIST)
SELECT
    id,
    item_id,
    user_id,
    bidder_id,
    amount,
    max_amount,
    is_winning,
    created_at
FROM bids
ORDER BY created_at DESC
LIMIT 5;

-- 10. FINAL DIAGNOSIS
SELECT
    'Bids table diagnosis complete. Check output above.' AS status,
    'Look for bidder_id column and NOT NULL constraints.' AS note;