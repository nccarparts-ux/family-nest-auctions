# BidYard — Admin Panel Setup Complete

## ✅ What Has Been Done

1. **Project Linked**: Local Supabase project linked to cloud project `hwsjgclteuezauveujit`
2. **Database Schema Updated**: Migration `20250313180000_admin_system_setup.sql` applied to remote database
   - Added missing columns (`profiles.is_admin`, `sellers.status`, etc.)
   - Created non-recursive RLS policies for admin access
   - Set up `is_admin_user()` SECURITY DEFINER function to prevent RLS recursion
   - Added admin policies for all tables: profiles, sellers, items, bids, estate_sales
3. **Security Fixed**: Service role key removed from `.env`, personal access token configured
4. **Tests Passed**: 30 Playwright tests passing
5. **Deployment Live**: Site deployed to https://bidyard.vercel.app

## 🔧 Remaining Setup Steps

### 1. Set Yourself as Admin
Run in **Supabase SQL Editor**:
```sql
-- Find your user ID
SELECT id, email, full_name, created_at
FROM profiles
ORDER BY created_at DESC
LIMIT 10;

-- Copy your ID (looks like: a290fc8a-f32e-4674-80ed-98cf2bcb6bbf)
-- Then run:
UPDATE profiles SET is_admin = true WHERE id = 'YOUR-USER-ID-HERE';
```

Or run the provided script: `set_admin.sql`

### 2. Verify Database Setup
Run diagnostic script in **Supabase SQL Editor**:
```sql
-- Copy content from diagnose_admin_data.sql
-- Or run the file directly
```
Expected results:
- ✅ All table structures should be OK
- ✅ Admin access policies should exist
- ✅ Your admin status should show "ADMIN" after step 1

### 3. Test Admin Panel
1. Log in to your application
2. Navigate to `/admin-panel.html`
3. Check each tab:
   - **Dashboard**: Stats should load (or show -- if no data)
   - **Seller Management**: Should show pending/verified sellers
   - **User Management**: Should list all users
   - **Live Auctions/Listings**: Should show real items data

## 🐛 Common Issues & Fixes

### ❌ "No sellers in database yet"
- This is expected if no seller applications exist
- To test, create a seller application via the main site

### ❌ "Permission denied" or RLS recursion errors
- Run `setup_admin_system.sql` in Supabase SQL Editor
- Or re-run the migration: `npx supabase db push`

### ❌ "Missing status column" in sellers table
- Already fixed by migration, but if still appears:
- Run `add_seller_status.sql` in Supabase SQL Editor

### ❌ Admin panel shows demo data
- Demo data was removed on 2026-03-03
- If you see hardcoded numbers, clear browser cache (Ctrl+F5)

## 📊 Database Schema Overview

**Tables required for admin panel:**
- `profiles` (with `is_admin` column)
- `sellers` (with `status` column: 'pending', 'active', 'suspended')
- `items` (with `status` column)
- `bids`
- `estate_sales`

**RLS Policies:**
- Admins have `FOR ALL` access via `is_admin_user()` function
- Users can only access their own profiles/seller applications
- All policies are idempotent (safe to re-run)

## 🔍 Testing

Run the test suite:
```bash
npm test
```

Test includes:
- Main page loads
- Admin panel redirects when not authenticated
- Seller dashboard redirects when not authenticated
- Key pages accessible

## 🚀 Deployment

Your site is live at: https://bidyard.vercel.app

To redeploy:
```bash
vercel --prod --yes
```

## 📁 Useful Files

| File | Purpose |
|------|---------|
| `setup_admin_system.sql` | Complete admin system setup |
| `add_seller_status.sql` | Add status column to sellers |
| `diagnose_admin_data.sql` | Check database health |
| `set_admin.sql` | Instructions to become admin |
| `admin-panel.html` | Admin interface |

## ⚠️ Security Notes

- **Never commit** `.env` file (already in `.gitignore`)
- **Service role key** (`sb_secret_...`) should only be used server-side
- **Personal access token** (`sbp_...`) is for CLI operations
- **Publishable key** (`sb_publishable_...`) is safe for client-side use

## 📞 Support

If issues persist:
1. Check browser console for errors
2. Run diagnostic SQL script
3. Review Supabase logs in dashboard
4. Check `CLAUDE.md` for previous fixes