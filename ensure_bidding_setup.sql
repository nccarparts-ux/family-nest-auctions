-- ============================================================
-- BidYard — Bidding System Setup Verification
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

-- 5a. FIX BIDDER_ID COLUMN ISSUE
-- Handle the case where bidder_id column exists with NOT NULL constraint
DO $$
DECLARE
    user_id_exists boolean;
    bidder_id_exists boolean;
    constraint_name text;
    fk_exists boolean;
BEGIN
    -- Check if columns exist
    SELECT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'bids' AND column_name = 'user_id'
    ) INTO user_id_exists;

    SELECT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'bids' AND column_name = 'bidder_id'
    ) INTO bidder_id_exists;

    RAISE NOTICE 'Checking columns: user_id exists=%, bidder_id exists=%', user_id_exists, bidder_id_exists;

    -- Scenario 1: Both columns exist - drop bidder_id if redundant
    IF user_id_exists AND bidder_id_exists THEN
        RAISE NOTICE 'Both columns exist. Checking if bidder_id is redundant...';

        -- Check if bidder_id has data
        IF EXISTS (SELECT 1 FROM bids WHERE bidder_id IS NOT NULL LIMIT 1) THEN
            RAISE NOTICE 'bidder_id has data, making nullable instead of dropping...';
            -- Make bidder_id nullable
            BEGIN
                ALTER TABLE bids ALTER COLUMN bidder_id DROP NOT NULL;
                RAISE NOTICE 'Made bidder_id nullable';
            EXCEPTION WHEN others THEN
                RAISE NOTICE 'Could not alter bidder_id: %', SQLERRM;
            END;
        ELSE
            RAISE NOTICE 'bidder_id has no data, dropping column...';
            -- Drop any constraints on bidder_id first
            SELECT constraint_name INTO constraint_name
            FROM information_schema.table_constraints
            WHERE table_schema = 'public' AND table_name = 'bids'
                AND constraint_type IN ('FOREIGN KEY', 'UNIQUE', 'PRIMARY KEY')
                AND constraint_name IN (
                    SELECT constraint_name
                    FROM information_schema.constraint_column_usage
                    WHERE table_schema = 'public' AND table_name = 'bids' AND column_name = 'bidder_id'
                )
            LIMIT 1;

            IF constraint_name IS NOT NULL THEN
                EXECUTE 'ALTER TABLE bids DROP CONSTRAINT ' || quote_ident(constraint_name);
                RAISE NOTICE 'Dropped constraint % from bidder_id', constraint_name;
            END IF;

            -- Drop the column
            BEGIN
                ALTER TABLE bids DROP COLUMN bidder_id;
                RAISE NOTICE 'Dropped redundant bidder_id column';
            EXCEPTION WHEN others THEN
                RAISE NOTICE 'Could not drop bidder_id: %', SQLERRM;
                -- Fallback: make it nullable
                BEGIN
                    ALTER TABLE bids ALTER COLUMN bidder_id DROP NOT NULL;
                    RAISE NOTICE 'Made bidder_id nullable as fallback';
                EXCEPTION WHEN others THEN
                    RAISE NOTICE 'Could not make bidder_id nullable: %', SQLERRM;
                END;
            END;
        END IF;

    -- Scenario 2: Only bidder_id exists, rename to user_id
    ELSIF bidder_id_exists AND NOT user_id_exists THEN
        RAISE NOTICE 'Only bidder_id exists, renaming to user_id...';

        -- Check if foreign key exists to auth.users
        SELECT EXISTS (
            SELECT 1 FROM information_schema.table_constraints tc
            JOIN information_schema.constraint_column_usage ccu
                ON tc.constraint_name = ccu.constraint_name
            WHERE tc.table_schema = 'public' AND tc.table_name = 'bids'
                AND tc.constraint_type = 'FOREIGN KEY'
                AND ccu.column_name = 'bidder_id'
                AND ccu.table_schema = 'auth' AND ccu.table_name = 'users'
        ) INTO fk_exists;

        IF fk_exists THEN
            -- Foreign key exists to auth.users, just rename
            ALTER TABLE bids RENAME COLUMN bidder_id TO user_id;
            RAISE NOTICE 'Renamed bidder_id to user_id (preserved foreign key)';
        ELSE
            -- No proper foreign key, rename and add correct one
            ALTER TABLE bids RENAME COLUMN bidder_id TO user_id;
            RAISE NOTICE 'Renamed bidder_id to user_id';

            -- Add foreign key to auth.users
            BEGIN
                ALTER TABLE bids
                    ADD CONSTRAINT bids_user_id_fkey
                    FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE SET NULL;
                RAISE NOTICE 'Added foreign key to auth.users';
            EXCEPTION WHEN duplicate_object THEN
                RAISE NOTICE 'Foreign key already exists';
            END;
        END IF;

    -- Scenario 3: Only user_id exists (ideal)
    ELSIF user_id_exists AND NOT bidder_id_exists THEN
        RAISE NOTICE 'Only user_id exists (ideal state)';

    -- Scenario 4: Neither exists (should have been created in section 1)
    ELSE
        RAISE NOTICE 'Creating user_id column...';
        ALTER TABLE bids ADD COLUMN user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL;
    END IF;

    -- Ensure user_id is nullable (matches ON DELETE SET NULL)
    IF user_id_exists OR (bidder_id_exists AND NOT user_id_exists) THEN
        IF EXISTS (
            SELECT 1 FROM information_schema.columns
            WHERE table_schema = 'public' AND table_name = 'bids'
                AND column_name = 'user_id' AND is_nullable = 'NO'
        ) THEN
            ALTER TABLE bids ALTER COLUMN user_id DROP NOT NULL;
            RAISE NOTICE 'Made user_id nullable';
        END IF;
    END IF;
END $$;

-- 6. VERIFY AUTH.USERS REFERENCE (user_id column foreign key)
-- Drop and recreate to ensure consistent naming and behavior
DO $$
DECLARE
  constraint_rec record;
BEGIN
  -- First drop our specifically named constraint if it exists
  BEGIN
    ALTER TABLE bids DROP CONSTRAINT IF EXISTS bids_user_id_fkey;
    RAISE NOTICE 'Dropped bids_user_id_fkey constraint if it existed';
  EXCEPTION WHEN others THEN
    RAISE NOTICE 'Could not drop bids_user_id_fkey: %', SQLERRM;
  END;

  -- Drop any other foreign key constraints on bids.user_id referencing auth.users
  FOR constraint_rec IN
    SELECT tc.constraint_name
    FROM information_schema.table_constraints tc
    JOIN information_schema.constraint_column_usage ccu
      ON tc.constraint_name = ccu.constraint_name
    WHERE tc.table_schema = 'public' AND tc.table_name = 'bids'
      AND tc.constraint_type = 'FOREIGN KEY'
      AND ccu.column_name = 'user_id'
      AND ccu.table_schema = 'auth' AND ccu.table_name = 'users'
  LOOP
    BEGIN
      EXECUTE 'ALTER TABLE bids DROP CONSTRAINT ' || quote_ident(constraint_rec.constraint_name);
      RAISE NOTICE 'Dropped foreign key constraint % on bids.user_id', constraint_rec.constraint_name;
    EXCEPTION WHEN others THEN
      RAISE NOTICE 'Could not drop constraint %: %', constraint_rec.constraint_name, SQLERRM;
    END;
  END LOOP;

  -- Add our properly named constraint
  BEGIN
    ALTER TABLE bids
      ADD CONSTRAINT bids_user_id_fkey
      FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE SET NULL;
    RAISE NOTICE 'Added foreign key constraint from bids.user_id to auth.users.id';
  EXCEPTION WHEN duplicate_object THEN
    RAISE NOTICE 'Foreign key constraint bids_user_id_fkey already exists (should not happen)';
  END;
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