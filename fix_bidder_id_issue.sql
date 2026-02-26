-- ============================================================
-- Family Nest Auctions — Fix bidder_id column issue
-- Run this AFTER ensure_bidding_setup.sql in Supabase SQL Editor
-- ============================================================

DO $$
DECLARE
    col_exists boolean;
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

    RAISE NOTICE 'user_id exists: %, bidder_id exists: %', user_id_exists, bidder_id_exists;

    -- Scenario 1: Both columns exist
    IF user_id_exists AND bidder_id_exists THEN
        RAISE NOTICE 'Both user_id and bidder_id columns exist. Fixing bidder_id NOT NULL constraint...';

        -- Check if bidder_id has NOT NULL constraint
        IF EXISTS (
            SELECT 1 FROM information_schema.columns
            WHERE table_schema = 'public' AND table_name = 'bids'
              AND column_name = 'bidder_id' AND is_nullable = 'NO'
        ) THEN
            -- Try to drop NOT NULL constraint
            BEGIN
                ALTER TABLE bids ALTER COLUMN bidder_id DROP NOT NULL;
                RAISE NOTICE 'Dropped NOT NULL constraint from bidder_id column';
            EXCEPTION WHEN others THEN
                RAISE NOTICE 'Could not drop NOT NULL from bidder_id: %', SQLERRM;
            END;
        END IF;

        -- Check if bidder_id has foreign key constraint
        SELECT tc.constraint_name INTO constraint_name
        FROM information_schema.table_constraints tc
        JOIN information_schema.constraint_column_usage ccu
            ON tc.constraint_name = ccu.constraint_name
        WHERE tc.table_schema = 'public' AND tc.table_name = 'bids'
            AND tc.constraint_type = 'FOREIGN KEY'
            AND ccu.column_name = 'bidder_id'
        LIMIT 1;

        IF constraint_name IS NOT NULL THEN
            EXECUTE 'ALTER TABLE bids DROP CONSTRAINT IF EXISTS ' || quote_ident(constraint_name);
            RAISE NOTICE 'Dropped foreign key constraint % from bidder_id', constraint_name;
        END IF;

        -- Check if bidder_id column is actually needed (compare to user_id)
        RAISE NOTICE 'Recommendation: If bidder_id is redundant, consider dropping it with: ALTER TABLE bids DROP COLUMN bidder_id;';

    -- Scenario 2: Only bidder_id exists, no user_id
    ELSIF bidder_id_exists AND NOT user_id_exists THEN
        RAISE NOTICE 'Only bidder_id exists. Renaming bidder_id to user_id...';

        -- Check foreign key constraint on bidder_id
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
            -- Foreign key exists to auth.users, just rename column
            ALTER TABLE bids RENAME COLUMN bidder_id TO user_id;
            RAISE NOTICE 'Renamed bidder_id to user_id (foreign key preserved)';
        ELSE
            -- No foreign key or points elsewhere, rename and add proper FK
            ALTER TABLE bids RENAME COLUMN bidder_id TO user_id;
            RAISE NOTICE 'Renamed bidder_id to user_id';

            -- Add foreign key to auth.users
            BEGIN
                ALTER TABLE bids
                    ADD CONSTRAINT bids_user_id_fkey
                    FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE SET NULL;
                RAISE NOTICE 'Added foreign key constraint from user_id to auth.users.id';
            EXCEPTION WHEN duplicate_object THEN
                RAISE NOTICE 'Foreign key constraint already exists';
            END;
        END IF;

    -- Scenario 3: Only user_id exists (ideal)
    ELSIF user_id_exists AND NOT bidder_id_exists THEN
        RAISE NOTICE 'Only user_id exists (ideal state). Nothing to fix.';

    -- Scenario 4: Neither column exists (should have been created by ensure_bidding_setup.sql)
    ELSE
        RAISE NOTICE 'Neither user_id nor bidder_id exists. Creating user_id column...';
        ALTER TABLE bids ADD COLUMN user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL;
        RAISE NOTICE 'Created user_id column with foreign key to auth.users';
    END IF;

    -- Ensure user_id column is nullable (matches original schema: ON DELETE SET NULL)
    IF user_id_exists OR (bidder_id_exists AND NOT user_id_exists) THEN
        IF EXISTS (
            SELECT 1 FROM information_schema.columns
            WHERE table_schema = 'public' AND table_name = 'bids'
              AND column_name = 'user_id' AND is_nullable = 'NO'
        ) THEN
            ALTER TABLE bids ALTER COLUMN user_id DROP NOT NULL;
            RAISE NOTICE 'Made user_id column nullable (was NOT NULL)';
        END IF;
    END IF;

    -- Final check: verify user_id column exists and is properly configured
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'bids' AND column_name = 'user_id'
    ) THEN
        RAISE NOTICE '✓ user_id column is properly configured';
    ELSE
        RAISE NOTICE '✗ user_id column still missing - something went wrong';
    END IF;
END $$;

-- Show final bids table structure
SELECT
    column_name,
    data_type,
    is_nullable,
    column_default
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'bids'
ORDER BY ordinal_position;

-- Refresh schema cache
NOTIFY pgrst, 'reload schema';

SELECT 'Bidder_id issue fix complete. Run diagnose_bids_schema.sql if problems persist.' AS status;