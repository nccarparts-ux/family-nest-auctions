-- ============================================================
-- BidYard — Complete Admin System Setup Migration
-- This migration sets up all tables, columns, and RLS policies needed for the admin panel
-- Run via: supabase db push
-- ============================================================

-- 0. DISABLE RLS TEMPORARILY TO FIX RECURSION (re-enabled at the end)
ALTER TABLE IF EXISTS profiles DISABLE ROW LEVEL SECURITY;

-- 1. ADD ADMIN COLUMN TO PROFILES TABLE
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS is_admin BOOLEAN DEFAULT false;

-- 2. CREATE SECURITY DEFINER FUNCTION TO CHECK ADMIN STATUS
-- This function bypasses RLS to avoid infinite recursion
CREATE OR REPLACE FUNCTION is_admin_user(user_id UUID)
RETURNS BOOLEAN AS $$
DECLARE
  admin_status BOOLEAN;
BEGIN
  SELECT is_admin INTO admin_status
  FROM profiles
  WHERE id = user_id;

  RETURN COALESCE(admin_status, false);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3. ADD NON-RECURSIVE RLS POLICIES FOR PROFILES TABLE
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

-- Drop generic Supabase auto-generated policies if they exist
DROP POLICY IF EXISTS "Enable read access for all users" ON profiles;
DROP POLICY IF EXISTS "Enable insert for authenticated users only" ON profiles;
DROP POLICY IF EXISTS "Enable update for users based on user_id" ON profiles;
DROP POLICY IF EXISTS "Enable delete for users based on user_id" ON profiles;

-- Drop all existing policies on profiles to start fresh
DROP POLICY IF EXISTS "profiles_select_own" ON profiles;
DROP POLICY IF EXISTS "profiles_update_own" ON profiles;
DROP POLICY IF EXISTS "profiles_insert_own" ON profiles;
DROP POLICY IF EXISTS "profiles_admin_all" ON profiles;
DROP POLICY IF EXISTS "users_can_view_own_profile" ON profiles;
DROP POLICY IF EXISTS "users_can_update_own_profile" ON profiles;
DROP POLICY IF EXISTS "admin_full_access" ON profiles;
DROP POLICY IF EXISTS "profiles_admin_access" ON profiles;

-- Users can select their own profile
CREATE POLICY "profiles_select_own" ON profiles
  FOR SELECT USING (auth.uid() = id);

-- Users can update their own profile
CREATE POLICY "profiles_update_own" ON profiles
  FOR UPDATE USING (auth.uid() = id);

-- Users can insert their own profile (for initial signup)
CREATE POLICY "profiles_insert_own" ON profiles
  FOR INSERT WITH CHECK (auth.uid() = id);

-- Admins can do everything (using the non-recursive function)
CREATE POLICY "profiles_admin_all" ON profiles
  FOR ALL USING (is_admin_user(auth.uid()));

-- 4. SELLERS TABLE SETUP
-- Ensure sellers table exists (basic structure - adjust as needed)
-- Note: sellers table should already exist from main app setup
-- Add status column if missing
ALTER TABLE sellers ADD COLUMN IF NOT EXISTS status TEXT DEFAULT 'pending';

-- Update existing sellers: set status based on is_verified
UPDATE sellers
SET status = CASE
    WHEN is_verified = true THEN 'active'
    ELSE 'pending'
END
WHERE status IS NULL OR status = 'pending';

-- Enable RLS on sellers if not already enabled
ALTER TABLE sellers ENABLE ROW LEVEL SECURITY;

-- Drop generic Supabase auto-generated policies if they exist
DROP POLICY IF EXISTS "Enable read access for all users" ON sellers;
DROP POLICY IF EXISTS "Enable insert for authenticated users only" ON sellers;
DROP POLICY IF EXISTS "Enable update for users based on user_id" ON sellers;
DROP POLICY IF EXISTS "Enable delete for users based on user_id" ON sellers;

-- Drop existing custom policies
DROP POLICY IF EXISTS "sellers_admin_access" ON sellers;
DROP POLICY IF EXISTS "sellers_insert_own" ON sellers;
DROP POLICY IF EXISTS "sellers_select_own" ON sellers;

-- Admin access policy
CREATE POLICY "sellers_admin_access" ON sellers
  FOR ALL USING (is_admin_user(auth.uid()))
  WITH CHECK (is_admin_user(auth.uid()));

-- Allow users to insert their own seller applications
CREATE POLICY "sellers_insert_own" ON sellers
  FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Allow users to select their own seller records
CREATE POLICY "sellers_select_own" ON sellers
  FOR SELECT USING (auth.uid() = user_id);

-- 5. ITEMS TABLE POLICIES
ALTER TABLE items ENABLE ROW LEVEL SECURITY;

-- Drop generic Supabase auto-generated policies if they exist
DROP POLICY IF EXISTS "Enable read access for all users" ON items;
DROP POLICY IF EXISTS "Enable insert for authenticated users only" ON items;
DROP POLICY IF EXISTS "Enable update for users based on user_id" ON items;
DROP POLICY IF EXISTS "Enable delete for users based on user_id" ON items;
DROP POLICY IF EXISTS "items_admin_access" ON items;

-- Admin access policy for items
CREATE POLICY "items_admin_access" ON items
  FOR ALL USING (is_admin_user(auth.uid()))
  WITH CHECK (is_admin_user(auth.uid()));

-- 6. BIDS TABLE POLICIES
ALTER TABLE bids ENABLE ROW LEVEL SECURITY;

-- Drop generic Supabase auto-generated policies if they exist
DROP POLICY IF EXISTS "Enable read access for all users" ON bids;
DROP POLICY IF EXISTS "Enable insert for authenticated users only" ON bids;
DROP POLICY IF EXISTS "Enable update for users based on user_id" ON bids;
DROP POLICY IF EXISTS "Enable delete for users based on user_id" ON bids;
DROP POLICY IF EXISTS "bids_admin_access" ON bids;

-- Admin access policy for bids
CREATE POLICY "bids_admin_access" ON bids
  FOR ALL USING (is_admin_user(auth.uid()))
  WITH CHECK (is_admin_user(auth.uid()));

-- 7. ESTATE_SALES TABLE POLICIES
ALTER TABLE estate_sales ENABLE ROW LEVEL SECURITY;

-- Drop generic Supabase auto-generated policies if they exist
DROP POLICY IF EXISTS "Enable read access for all users" ON estate_sales;
DROP POLICY IF EXISTS "Enable insert for authenticated users only" ON estate_sales;
DROP POLICY IF EXISTS "Enable update for users based on user_id" ON estate_sales;
DROP POLICY IF EXISTS "Enable delete for users based on user_id" ON estate_sales;
DROP POLICY IF EXISTS "estate_sales_admin_access" ON estate_sales;

-- Admin access policy for estate_sales
CREATE POLICY "estate_sales_admin_access" ON estate_sales
  FOR ALL USING (is_admin_user(auth.uid()))
  WITH CHECK (is_admin_user(auth.uid()));

-- 8. ADDITIONAL COLUMNS FOR ADMIN PANEL
-- Add bio to profiles (for account profile page)
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS bio TEXT;

-- Add missing display columns to reviews table if it exists
DO $$ BEGIN
  IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'reviews') THEN
    ALTER TABLE reviews ADD COLUMN IF NOT EXISTS reviewer_name TEXT;
    ALTER TABLE reviews ADD COLUMN IF NOT EXISTS title TEXT;
    ALTER TABLE reviews ADD COLUMN IF NOT EXISTS item_name TEXT;
  END IF;
END $$;

-- 9. CREATE ADMIN APPROVE SELLER FUNCTIONALITY
CREATE OR REPLACE FUNCTION approve_seller_and_update_profile(seller_uuid UUID)
RETURNS void AS $$
BEGIN
  -- Update seller to verified and active
  UPDATE sellers
  SET is_verified = true, status = 'active'
  WHERE id = seller_uuid;

  -- Update corresponding user's profile to is_seller = true
  UPDATE profiles
  SET is_seller = true
  WHERE id = (SELECT user_id FROM sellers WHERE id = seller_uuid);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 10. VERIFICATION QUERY
SELECT
  'Admin system migration applied successfully' AS message,
  (SELECT COUNT(*) FROM profiles) AS total_profiles,
  (SELECT COUNT(*) FROM profiles WHERE is_admin = true) AS admin_users,
  (SELECT COUNT(*) FROM sellers) AS total_sellers,
  (SELECT COUNT(*) FROM sellers WHERE is_verified = true) AS verified_sellers,
  (SELECT COUNT(*) FROM sellers WHERE status = 'pending') AS pending_sellers;