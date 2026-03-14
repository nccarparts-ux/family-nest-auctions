-- ============================================================
-- Add status column to sellers table and set initial values
-- Run this in Supabase SQL Editor
-- ============================================================

-- 1. Add status column if not exists
ALTER TABLE sellers ADD COLUMN IF NOT EXISTS status TEXT DEFAULT 'pending';

-- 2. Update existing sellers: set status based on is_verified
UPDATE sellers
SET status = CASE
    WHEN is_verified = true THEN 'active'
    ELSE 'pending'
END
WHERE status IS NULL OR status = 'pending';

-- 3. Verify the update
SELECT
    business_name,
    city || ', ' || state as location,
    is_verified,
    status,
    created_at::date as created
FROM sellers
ORDER BY created_at DESC;

-- 4. Show summary
SELECT
    'Seller status update complete' as message,
    COUNT(*) as total_sellers,
    COUNT(*) FILTER (WHERE is_verified = true) as verified,
    COUNT(*) FILTER (WHERE status = 'active') as active,
    COUNT(*) FILTER (WHERE status = 'pending') as pending
FROM sellers;