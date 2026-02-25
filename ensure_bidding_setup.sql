-- ============================================================
-- Family Nest Auctions — Bidding System Setup Verification
-- Run this in Supabase SQL Editor to ensure bidding works
-- ============================================================

-- 1. VERIFY AND FIX BIDS TABLE SCHEMA
DO $$
DECLARE
  col_record RECORD;
  columns_to_check TEXT[] := ARRAY['id', 'item_id', 'user_id', 'amount', 'max_amount', 'is_winning', 'created_at'];
  col_name TEXT;
  col_def TEXT;
BEGIN
  FOREACH col_name IN ARRAY columns_to_check
  LOOP
    IF NOT EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'bids' AND column_name = col_name
    ) THEN
      CASE col_name
        WHEN 'id' THEN
          ALTER TABLE bids ADD COLUMN id UUID PRIMARY KEY DEFAULT gen_random_uuid();
        WHEN 'item_id' THEN
          ALTER TABLE bids ADD COLUMN item_id UUID REFERENCES items(id) ON DELETE CASCADE NOT NULL;
        WHEN 'user_id' THEN
          ALTER TABLE bids ADD COLUMN user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL;
        WHEN 'amount' THEN
          ALTER TABLE bids ADD COLUMN amount NUMERIC(10,2) NOT NULL;
        WHEN 'max_amount' THEN
          ALTER TABLE bids ADD COLUMN max_amount NUMERIC(10,2);
        WHEN 'is_winning' THEN
          ALTER TABLE bids ADD COLUMN is_winning BOOLEAN DEFAULT false;
        WHEN 'created_at' THEN
          ALTER TABLE bids ADD COLUMN created_at TIMESTAMPTZ DEFAULT NOW();
      END CASE;
      RAISE NOTICE 'Added % column to bids table', col_name;
    ELSE
      RAISE NOTICE '% column already exists in bids table', col_name;
    END IF;
  END LOOP;
END $$;

-- 2. VERIFY AND FIX ITEMS TABLE HAS CURRENT_BIDDER_ID
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'items' AND column_name = 'current_bidder_id'
  ) THEN
    ALTER TABLE items ADD COLUMN current_bidder_id UUID REFERENCES auth.users(id) ON DELETE SET NULL;
    RAISE NOTICE 'Added current_bidder_id column to items table';
  ELSE
    RAISE NOTICE 'current_bidder_id column already exists in items table';
  END IF;
END $$;

-- 3. ENABLE ROW LEVEL SECURITY ON BIDS IF NOT ENABLED
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_tables
    WHERE schemaname = 'public' AND tablename = 'bids' AND rowsecurity = true
  ) THEN
    ALTER TABLE bids ENABLE ROW LEVEL SECURITY;
    RAISE NOTICE 'Enabled RLS on bids table';
  ELSE
    RAISE NOTICE 'RLS already enabled on bids table';
  END IF;
END $$;

-- 4. ENSURE RLS POLICIES EXIST FOR BIDS TABLE
-- Drop and recreate policies to ensure they're correct
DROP POLICY IF EXISTS "bids_read" ON bids;
CREATE POLICY "bids_read" ON bids
  FOR SELECT USING (true);

DROP POLICY IF EXISTS "bids_insert" ON bids;
CREATE POLICY "bids_insert" ON bids
  FOR INSERT WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "bids_update" ON bids;
CREATE POLICY "bids_update" ON bids
  FOR UPDATE USING (auth.role() = 'authenticated');

-- 5. ENSURE RLS POLICIES EXIST FOR ITEMS TABLE (FOR BID UPDATES)
-- Check if items_bid_update policy exists, if not create it
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'items' AND policyname = 'items_bid_update'
  ) THEN
    DROP POLICY IF EXISTS "items_bid_update" ON items;
    CREATE POLICY "items_bid_update" ON items
      FOR UPDATE USING (auth.role() = 'authenticated');
    RAISE NOTICE 'Created items_bid_update policy';
  ELSE
    RAISE NOTICE 'items_bid_update policy already exists';
  END IF;
END $$;

-- 6. VERIFY AUTH.USERS REFERENCE (user_id column foreign key)
-- Check if user_id column references auth.users properly
DO $$
BEGIN
  -- Check foreign key constraint exists
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints tc
    JOIN information_schema.constraint_column_usage ccu
      ON tc.constraint_name = ccu.constraint_name
    WHERE tc.table_schema = 'public' AND tc.table_name = 'bids'
      AND tc.constraint_type = 'FOREIGN KEY'
      AND ccu.column_name = 'user_id'
      AND ccu.table_schema = 'auth' AND ccu.table_name = 'users'
  ) THEN
    -- Add foreign key constraint if missing
    ALTER TABLE bids
      ADD CONSTRAINT bids_user_id_fkey
      FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE SET NULL;
    RAISE NOTICE 'Added foreign key constraint from bids.user_id to auth.users.id';
  ELSE
    RAISE NOTICE 'Foreign key constraint already exists for bids.user_id';
  END IF;
END $$;

-- 7. REFRESH SCHEMA CACHE
NOTIFY pgrst, 'reload schema';

-- 8. DISPLAY CURRENT BIDS TABLE STRUCTURE
SELECT
  column_name,
  data_type,
  is_nullable,
  column_default
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'bids'
ORDER BY ordinal_position;

-- 9. DISPLAY CURRENT BIDS POLICIES
SELECT
  policyname,
  permissive,
  roles,
  cmd,
  qual,
  with_check
FROM pg_policies
WHERE schemaname = 'public' AND tablename = 'bids'
ORDER BY policyname;

-- 10. TEST QUERY TO VERIFY AUTH CONTEXT
-- This will show if auth.uid() is available in current session
SELECT
  current_user,
  current_setting('request.jwt.claims', true)::json->>'sub' as auth_uid,
  current_setting('role', true) as current_role;

-- 11. FINAL STATUS MESSAGE
SELECT 'Bidding system setup verification complete. Check output above for any issues.' AS status;