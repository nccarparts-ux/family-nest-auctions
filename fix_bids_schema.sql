-- ============================================================
-- Fix bids table schema for Edge Function schema cache
-- Run this in Supabase SQL Editor to ensure all columns exist
-- ============================================================

-- Check and add missing columns based on create-test-seller.sql definition
DO $$
DECLARE
  col_record RECORD;
  columns_to_check TEXT[] := ARRAY['item_id', 'user_id', 'amount', 'max_amount', 'is_winning'];
  col_name TEXT;
BEGIN
  FOREACH col_name IN ARRAY columns_to_check
  LOOP
    IF NOT EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'bids' AND column_name = col_name
    ) THEN
      CASE col_name
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
      END CASE;
      RAISE NOTICE 'Added % column to bids table', col_name;
    ELSE
      RAISE NOTICE '% column already exists in bids table', col_name;
    END IF;
  END LOOP;
END $$;

-- Ensure items table has current_bidder_id column
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

-- Verify table structure
SELECT
  column_name,
  data_type,
  is_nullable,
  column_default
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'bids'
ORDER BY ordinal_position;

-- Refresh PostgREST schema cache (used by Supabase JS client)
NOTIFY pgrst, 'reload schema';

-- Add policy to allow authenticated users to update bid-related fields
DROP POLICY IF EXISTS "items_bid_update" ON items;
CREATE POLICY "items_bid_update" ON items FOR UPDATE USING (auth.role() = 'authenticated');

-- Add missing update policy for bids (needed for marking previous bids as non-winning)
DROP POLICY IF EXISTS "bids_update" ON bids;
CREATE POLICY "bids_update" ON bids FOR UPDATE USING (auth.role() = 'authenticated');

-- Note: Edge Functions may have separate schema cache; redeploy place-bid function if needed
SELECT 'Bids table schema check complete. If errors persist, redeploy Edge Functions.' AS status;