# BidYard

Online Garage & Estate Sale Auctions Platform

## Recent Updates (March 13, 2026)

### Complete Rebranding
- Successfully rebranded from "Family Nest Auctions" to "BidYard"
- Updated visual identity: Inter font, blue (#1E4ED8) and red (#E63946) color scheme
- White page backgrounds with blue/red accents for better readability
- Renamed main file to `index.html` and updated all internal references

### Login Functionality Fix
- Fixed "FNA is not defined" JavaScript error by replacing all `FNA.` references with `BY.`
- Created comprehensive console error detection tests with Playwright
- 41 of 45 tests passing (mobile viewport tests require selector adjustments)
- Deployed to production at [bidyard.vercel.app](https://bidyard.vercel.app)

### Admin System Enhancement
- Linked project to Supabase cloud and fixed RLS recursion issues
- Created comprehensive SQL migration for admin system (`20250313180000_admin_system_setup.sql`)
- Added `is_admin` column to profiles table and `status` column to sellers table

### Development Toolchain
- Set up Supabase CLI, Playwright Testing, Vercel CLI
- Created comprehensive skill documentation in `skills/` directory
- Configured local development server with `npm run dev`

## Key Technical Learnings

### Parallel Agent Efficiency
When faced with large-scale tasks (rebranding, search/replace operations), spin up multiple agents to work on different file types simultaneously. This dramatically improves completion time:

1. **Agent 1**: Update main HTML and branding
2. **Agent 2**: Update remaining HTML files in parallel
3. **Agent 3**: Update JavaScript and API files
4. **Agent 4**: Update test files
5. **Agent 5**: Update configuration files
6. **Agent 6**: Update SQL files and documentation
7. **Agent 7**: Update Vercel and deployment

### JavaScript Error Prevention
- After namespace changes (FNA → BY), systematically update ALL references across HTML files
- Create Playwright tests that capture console errors and page errors
- Use specific selectors that account for multiple element instances (desktop vs mobile)

## Quick Start

```bash
# Install dependencies
npm install

# Start local development server
npm run dev

# Run tests
npm test

# Deploy to production
vercel --prod
```

## Project Structure

- `index.html` - Main auction homepage
- `admin-panel.html` - Admin dashboard
- `seller-dashboard.html` - Seller management
- `account-dashboard.html` - User account
- `auction-browse.html` - Browse live auctions
- `auction-item-detail.html` - Individual auction detail
- `js/api.js` - JavaScript API (BY namespace)
- `tests/` - Playwright test suite
- `supabase/` - Database migrations and configuration
- `skills/` - Development tool documentation

## Testing

```bash
# Run all tests
npm test

# Run specific test file
npm test -- tests/console.spec.js

# Run with UI mode
npm run test:ui
```

## Deployment

Production: [https://bidyard.vercel.app](https://bidyard.vercel.app)

Aliases:
- `https://family-nest-auctions.vercel.app` (legacy)
- `https://bidyard.vercel.app` (primary)

## Database

Supabase project: `hwsjgclteuezauveujit`

Run admin setup:
```sql
-- In Supabase SQL Editor
\i supabase/migrations/20250313180000_admin_system_setup.sql
\i set_admin.sql -- Make yourself admin
```