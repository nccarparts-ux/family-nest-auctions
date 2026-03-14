-- ============================================================
-- Set Yourself as Admin for BidYard
-- Run this in Supabase SQL Editor after logging in
-- ============================================================

-- 1. FIRST, FIND YOUR USER ID FROM THE PROFILES TABLE
SELECT id, email, full_name, created_at
FROM profiles
ORDER BY created_at DESC
LIMIT 10;

-- 2. COPY YOUR USER ID FROM THE RESULTS ABOVE (looks like: a290fc8a-f32e-4674-80ed-98cf2bcb6bbf)

-- 3. THEN UNCOMMENT AND RUN THIS LINE WITH YOUR USER ID:
-- UPDATE profiles SET is_admin = true WHERE id = 'YOUR-USER-ID-HERE';

-- 4. VERIFY YOU ARE ADMIN:
-- SELECT id, email, full_name, is_admin FROM profiles WHERE id = 'YOUR-USER-ID-HERE';

-- 5. AFTER SETTING IS_ADMIN = TRUE, REFRESH THE ADMIN PANEL PAGE
-- You should now have full access to all admin features.