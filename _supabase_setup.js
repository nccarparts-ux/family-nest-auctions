/**
 * Family Nest Auctions — Supabase REST API Setup Script
 * Runs with: node _supabase_setup.js
 * Uses anon key only (safe for frontend) — no direct DB connection
 *
 * NOTE: Run setup_missing_tables.sql in Supabase SQL Editor BEFORE running this
 * script, so the reviews.reviewer_name / title / item_name columns exist.
 */

const SUPABASE_URL = 'https://hwsjgclteuezauveujit.supabase.co';
const SUPABASE_ANON_KEY = 'sb_publishable_3-tTloiwTqSEZCw4_m288w_FoR7OgxS';

const headers = {
  'Authorization': `Bearer ${SUPABASE_ANON_KEY}`,
  'apikey': SUPABASE_ANON_KEY,
  'Content-Type': 'application/json',
  'Prefer': 'return=representation'
};

async function rest(method, path, body) {
  const url = `${SUPABASE_URL}/rest/v1${path}`;
  const opts = { method, headers };
  if (body) opts.body = JSON.stringify(body);
  const res = await fetch(url, opts);
  let data;
  try { data = await res.json(); } catch { data = null; }
  return { status: res.status, ok: res.ok, data };
}

async function checkTable(name) {
  const r = await rest('GET', `/${name}?limit=1`);
  return { exists: r.ok, status: r.status, sample: r.data };
}

// ── MAIN ──────────────────────────────────────────────────────
async function main() {
  console.log('═══════════════════════════════════════════════');
  console.log(' Family Nest Auctions — Supabase Setup Script');
  console.log('═══════════════════════════════════════════════\n');

  // 1. Check which tables exist
  console.log('── Step 1: Checking existing tables ──');
  const tables = ['profiles','sellers','items','bids','item_photos','watchlist',
                  'messages','notifications','estate_sales','payout_requests',
                  'franchise_leads','reviews'];
  const tableStatus = {};
  for (const t of tables) {
    const r = await checkTable(t);
    tableStatus[t] = r.exists;
    const icon = r.exists ? '✅' : '❌';
    console.log(`  ${icon} ${t.padEnd(20)} ${r.exists ? 'exists' : 'missing (run setup_missing_tables.sql)'}` );
  }
  console.log('');

  // 2. Verify storage buckets
  console.log('── Step 2: Verifying storage buckets ──');
  const bucketsRes = await fetch(`${SUPABASE_URL}/storage/v1/bucket`, {
    headers: { 'Authorization': `Bearer ${SUPABASE_ANON_KEY}` }
  });
  const buckets = await bucketsRes.json();
  const bucketNames = Array.isArray(buckets) ? buckets.map(b => b.name) : [];
  for (const bkt of ['item-photos', 'avatars']) {
    const found = bucketNames.includes(bkt);
    const isPublic = found && buckets.find(b => b.name === bkt)?.public;
    console.log(`  ${found && isPublic ? '✅' : '⚠️ '} ${bkt.padEnd(20)} ${found ? (isPublic ? 'public ✓' : 'exists but NOT public') : 'MISSING'}`);
  }
  console.log('');

  // 3. Seed data — only if tables exist
  console.log('── Step 3: Seeding data via REST API ──');

  // Use the existing seeded seller from the DB
  // Seller: id=00000000-0000-0000-0000-000000000010, "Morris Estate", Nashville TN
  const SELLER_ID = '00000000-0000-0000-0000-000000000010';

  // Verify existing seller is present
  const sellerCheck = await rest('GET', `/sellers?id=eq.${SELLER_ID}&limit=1`);
  if (sellerCheck.ok && Array.isArray(sellerCheck.data) && sellerCheck.data.length > 0) {
    console.log(`  ✅ Using existing seller: ${sellerCheck.data[0].business_name} (${SELLER_ID})`);
  } else {
    // Create a placeholder seller with correct column names
    if (tableStatus['sellers']) {
      const r = await rest('POST', '/sellers', [{
        id: SELLER_ID,
        business_name: 'Henderson Estate Sales',
        city: 'Atlanta',
        state: 'GA',
        is_verified: true,
        is_active: true
      }]);
      console.log(`  ${r.ok ? '✅' : '❌'} Seeded placeholder seller — status ${r.status}`);
      if (!r.ok) console.log('     Error:', JSON.stringify(r.data));
    }
  }

  // Seed 3 sample reviews (requires setup_missing_tables.sql to have been run first)
  if (tableStatus['reviews']) {
    // Check if the reviewer_name column exists by trying to select it
    const colCheck = await rest('GET', '/reviews?select=reviewer_name&limit=1');
    if (!colCheck.ok && JSON.stringify(colCheck.data).includes('reviewer_name')) {
      console.log('  ⚠️  reviews.reviewer_name column missing — run setup_missing_tables.sql first');
    } else {
      const existCheck = await rest('GET', '/reviews?reviewer_name=eq.Jennifer%20M.&limit=1');
      const alreadyExists = existCheck.ok && Array.isArray(existCheck.data) && existCheck.data.length > 0;
      if (!alreadyExists) {
        const reviewSeeds = [
          {
            reviewer_name: 'Jennifer M.',
            item_name: 'Victorian Carved Mahogany Armchair',
            rating: 5,
            title: 'Absolutely stunning — exactly as described',
            body: 'Beautiful piece arrived exactly as described, packed incredibly well. The condition photos were spot-on, no surprises. The seller communicated throughout. Will definitely buy from this estate again!',
            seller_id: SELLER_ID
          },
          {
            reviewer_name: 'Robert P.',
            item_name: 'Sterling Silver Tea Service',
            rating: 5,
            title: "Best estate auction experience I've had",
            body: "Fast shipping, extremely well packaged, item exactly as described. The price transparency upfront is a huge plus — no surprises at checkout. Family Nest sets the standard for online estate auctions.",
            seller_id: SELLER_ID
          },
          {
            reviewer_name: 'Sarah K.',
            item_name: 'Persian Wool Rug 8×10',
            rating: 4,
            title: 'Great item, proactive communication',
            body: 'Item was in great condition. Shipping took a couple extra days beyond the stated window, but seller communicated proactively. Very happy with the purchase overall.',
            seller_id: SELLER_ID
          }
        ];
        const r = await rest('POST', '/reviews', reviewSeeds);
        console.log(`  ${r.ok ? '✅' : '❌'} Seeded 3 sample reviews — status ${r.status}`);
        if (!r.ok) console.log('     Error:', JSON.stringify(r.data));
      } else {
        console.log('  ✅ Sample reviews already seeded — skipped');
      }
    }
  } else {
    console.log('  ⏭️  reviews table missing — skipping review seed');
  }

  // Check/seed items (existing item: Mid-Century Walnut Sofa Set, item_number FNA-0001-0001)
  if (tableStatus['items']) {
    const existCheck = await rest('GET', '/items?title=eq.Victorian+Carved+Mahogany+Armchair&limit=1');
    const alreadyExists = existCheck.ok && Array.isArray(existCheck.data) && existCheck.data.length > 0;
    if (!alreadyExists) {
      const now = new Date().toISOString();
      const inSevenDays = new Date(Date.now() + 7*86400000).toISOString();
      const inTwoDays   = new Date(Date.now() + 2*86400000).toISOString();
      const inFourDays  = new Date(Date.now() + 4*86400000).toISOString();
      const sampleItems = [
        {
          seller_id: SELLER_ID,
          estate_sale_id: '00000000-0000-0000-0000-000000000020',
          title: 'Victorian Carved Mahogany Armchair',
          description: 'A magnificent example of late Victorian craftsmanship, this hand-carved mahogany armchair dates to approximately 1890. Features intricate floral and foliate carvings along the crest rail.',
          category: 'Furniture',
          condition: 'good',
          period: 'Victorian',
          item_number: 'FNA-0001-0002',
          starting_bid: 100,
          current_bid: 187,
          bid_count: 18,
          status: 'live',
          starts_at: now,
          ends_at: inTwoDays
        },
        {
          seller_id: SELLER_ID,
          estate_sale_id: '00000000-0000-0000-0000-000000000020',
          title: 'Art Deco Diamond Brooch, 1920s',
          description: 'Stunning platinum and diamond brooch in the Art Deco style, circa 1925. Features geometric motifs set with old European cut diamonds totaling approximately 2.1 carats.',
          category: 'Jewelry',
          condition: 'excellent',
          period: 'Art Deco',
          item_number: 'FNA-0001-0003',
          starting_bid: 500,
          current_bid: 1250,
          bid_count: 55,
          status: 'live',
          starts_at: now,
          ends_at: inFourDays
        },
        {
          seller_id: SELLER_ID,
          estate_sale_id: '00000000-0000-0000-0000-000000000020',
          title: 'Signed Impressionist Oil Painting',
          description: 'A beautiful impressionist landscape in oils, signed lower right. The work depicts a sun-dappled garden scene with confident, energetic brushwork. Provenance: Private Savannah collection.',
          category: 'Art',
          condition: 'excellent',
          period: 'Early 20th Century',
          item_number: 'FNA-0001-0004',
          starting_bid: 800,
          current_bid: 2800,
          bid_count: 68,
          status: 'live',
          starts_at: now,
          ends_at: inSevenDays
        }
      ];
      let seeded = 0;
      for (const item of sampleItems) {
        const r = await rest('POST', '/items', [item]);
        if (r.ok) { seeded++; }
        else if (r.status === 409) { console.log(`  ⏭️  Item "${item.title}" already exists — skipped`); }
        else { console.log(`  ❌ Failed to seed "${item.title}": ${JSON.stringify(r.data)}`); }
      }
      if (seeded > 0) console.log(`  ✅ Seeded ${seeded} additional live auction items`);
    } else {
      console.log('  ✅ Sample auction items already exist — skipped');
    }
  } else {
    console.log('  ⏭️  items table missing — skipping item seed');
  }

  console.log('');

  // 4. Summary
  const missing = Object.entries(tableStatus).filter(([,v]) => !v).map(([k]) => k);
  console.log('── Summary ─────────────────────────────────');
  if (missing.length === 0) {
    console.log('  ✅ All tables exist. Setup via REST complete!');
    console.log('  ✅ Storage buckets: item-photos + avatars (public)');
    console.log('  📋 If not done: run setup_missing_tables.sql for realtime + storage policies');
  } else {
    console.log(`  ❌ ${missing.length} tables missing: ${missing.join(', ')}`);
    console.log('  👉 Run setup_missing_tables.sql in Supabase SQL Editor, then re-run this script');
  }
  console.log('');
}

main().catch(console.error);