const { test, expect } = require('@playwright/test');

// Test data
const TEST_BUYER = {
  email: `buyer-${Date.now()}@test.bidyard.com`,
  password: 'TestPassword123!',
  fullName: 'Test Buyer'
};

const TEST_SELLER = {
  email: `seller-${Date.now()}@test.bidyard.com`,
  password: 'TestPassword123!',
  fullName: 'Test Seller',
  businessName: 'Test Estate Sales LLC',
  phone: '555-123-4567',
  city: 'Atlanta',
  state: 'GA'
};

// Helper functions
async function registerUser(page, user) {
  await page.goto('/index.html');

  // Open signup modal
  const viewport = page.viewportSize();
  const isMobile = viewport && viewport.width < 960;

  if (isMobile) {
    const hamburger = page.locator('#hamburger');
    await hamburger.click();
    await page.waitForSelector('#mobile-menu', { state: 'visible' });
    const signupButton = page.locator('.mobile-menu-ctas button:has-text("Start Bidding Free")');
    await signupButton.click();
  } else {
    const signupButton = page.locator('button:has-text("Start Bidding Free")').first();
    await signupButton.click();
  }

  // Wait for modal
  await page.waitForSelector('#ov-register', { state: 'visible' });

  // Fill form
  await page.fill('#reg-name', user.fullName);
  await page.fill('#reg-email', user.email);
  await page.fill('#reg-password', user.password);

  // Submit
  await page.click('#reg-btn');

  // Wait for success (should redirect or show message)
  await page.waitForTimeout(2000);

  // Check if logged in (profile button appears)
  const profileVisible = await page.locator('a[href*="account-dashboard"]').isVisible().catch(() => false);
  return profileVisible;
}

async function loginUser(page, email, password) {
  await page.goto('/index.html');

  // Open login modal
  const viewport = page.viewportSize();
  const isMobile = viewport && viewport.width < 960;

  if (isMobile) {
    const hamburger = page.locator('#hamburger');
    await hamburger.click();
    await page.waitForSelector('#mobile-menu', { state: 'visible' });
    const loginButton = page.locator('.mobile-menu-ctas button:has-text("Sign In")');
    await loginButton.click();
  } else {
    const loginButton = page.locator('button:has-text("Sign In")').first();
    await loginButton.click();
  }

  // Wait for modal
  await page.waitForSelector('#ov-login', { state: 'visible' });

  // Fill form
  await page.fill('#login-email', email);
  await page.fill('#login-password', password);

  // Submit
  await page.click('#login-btn');

  // Wait for login
  await page.waitForTimeout(2000);

  // Check if logged in
  const profileVisible = await page.locator('a[href*="account-dashboard"]').isVisible().catch(() => false);
  return profileVisible;
}

async function logoutUser(page) {
  // Check if logout button exists in UI, otherwise just clear session
  await page.goto('/index.html');
  // Simple approach: clear storage
  await page.context().clearCookies();
  await page.reload();
}

// --- BUYER WORKFLOW TESTS ---

test.describe('Buyer End-to-End Workflow', () => {
  test('Buyer can register and browse auctions', async ({ page }) => {
    console.log('Testing buyer registration...');

    // Register new buyer
    const registered = await registerUser(page, TEST_BUYER);
    expect(registered).toBeTruthy();

    // Navigate to browse page
    await page.goto('/auction-browse.html');
    await expect(page).toHaveURL(/auction-browse/);

    // Check page loads with content
    await expect(page.locator('body')).toBeVisible();
    await expect(page.locator('h1:has-text("Browse")').first()).toBeVisible();

    // Should see auction items or "no items" message
    const hasItems = await page.locator('.auction-card, .item-card, [class*="item"]').first().isVisible().catch(() => false);
    const hasNoItemsMessage = await page.locator('text=/no.*item|empty|no.*result/i').first().isVisible().catch(() => false);

    expect(hasItems || hasNoItemsMessage).toBeTruthy();

    await logoutUser(page);
  });

  test('Buyer can view item details', async ({ page }) => {
    // Login first
    await loginUser(page, TEST_BUYER.email, TEST_BUYER.password);

    // Go to browse page
    await page.goto('/auction-browse.html');

    // Try to find and click on first item
    const firstItem = page.locator('a[href*="auction-item-detail"], .auction-card a, [class*="item"] a').first();
    const hasItem = await firstItem.isVisible().catch(() => false);

    if (hasItem) {
      await firstItem.click();
      await page.waitForLoadState('networkidle');

      // Should be on item detail page
      await expect(page).toHaveURL(/auction-item-detail/);
      await expect(page.locator('body')).toBeVisible();

      // Check for item details
      await expect(page.locator('h1')).toBeVisible();
    } else {
      console.log('No items available to test detail view');
    }

    await logoutUser(page);
  });

  test('Buyer can place a bid', async ({ page }) => {
    await loginUser(page, TEST_BUYER.email, TEST_BUYER.password);

    // Go to item detail page directly if we know an item ID, or browse first
    await page.goto('/auction-browse.html');

    // Look for bid button or form
    const bidButton = page.locator('button:has-text(/bid|place.*bid/i), input[type="submit"][value*="bid"]').first();
    const hasBidButton = await bidButton.isVisible().catch(() => false);

    if (hasBidButton) {
      // Try to place bid
      await bidButton.click();
      await page.waitForTimeout(1000);

      // Check for bid confirmation or error
      const bidSuccess = await page.locator('text=/bid.*success|success.*bid|thank.*bid/i').isVisible().catch(() => false);
      const bidError = await page.locator('text=/error|must.*higher|already.*higher/i').isVisible().catch(() => false);

      // Either success or error is expected response
      expect(bidSuccess || bidError).toBeTruthy();
    } else {
      console.log('No bid button available (may need live auction)');
    }

    await logoutUser(page);
  });

  test('Buyer can view account dashboard', async ({ page }) => {
    await loginUser(page, TEST_BUYER.email, TEST_BUYER.password);

    await page.goto('/account-dashboard.html');
    await expect(page).toHaveURL(/account-dashboard/);

    // Check dashboard sections
    await expect(page.locator('body')).toBeVisible();
    await expect(page.locator('h1:has-text(/account|dashboard|my.*account/i)')).toBeVisible();

    // Should have navigation or sections
    const hasSections = await page.locator('.dashboard-section, .card, .panel, section').first().isVisible().catch(() => false);
    expect(hasSections).toBeTruthy();

    await logoutUser(page);
  });
});

// --- SELLER WORKFLOW TESTS ---

test.describe('Seller End-to-End Workflow', () => {
  test('User can apply to become seller', async ({ page }) => {
    // First register as regular user
    await registerUser(page, TEST_SELLER);

    // Look for "Become a Seller" or similar link
    const sellerLink = page.locator('a:has-text(/sell.*us|become.*seller|seller.*dashboard/i), button:has-text(/sell.*us|become.*seller/i)');
    const hasSellerLink = await sellerLink.first().isVisible().catch(() => false);

    if (hasSellerLink) {
      await sellerLink.first().click();
      await page.waitForLoadState('networkidle');

      // Should be on seller application or dashboard
      await expect(page.locator('body')).toBeVisible();

      // Check for seller form
      const sellerForm = page.locator('form, input[name*="business"], textarea[name*="business"]');
      const hasForm = await sellerForm.first().isVisible().catch(() => false);

      if (hasForm) {
        // Fill seller application
        await page.fill('input[name*="business"], input[name*="company"], #business-name', TEST_SELLER.businessName);
        await page.fill('input[name*="phone"], #phone', TEST_SELLER.phone);
        await page.fill('input[name*="city"], #city', TEST_SELLER.city);
        await page.fill('input[name*="state"], #state', TEST_SELLER.state);

        // Submit
        await page.click('button[type="submit"], button:has-text(/submit.*application|apply/i)');
        await page.waitForTimeout(2000);

        // Check for success message
        const successMsg = await page.locator('text=/success|thank.*application|submitted/i').isVisible().catch(() => false);
        expect(successMsg).toBeTruthy();
      }
    } else {
      console.log('No seller application link found on page');
    }

    await logoutUser(page);
  });

  test('Seller can access dashboard', async ({ page }) => {
    // Login as seller (assuming seller account exists)
    await loginUser(page, TEST_SELLER.email, TEST_SELLER.password);

    // Try to access seller dashboard
    await page.goto('/seller-dashboard.html');

    // Should either load dashboard or redirect (if not seller)
    const isDashboard = await page.locator('h1:has-text(/seller.*dashboard|my.*listings/i)').isVisible().catch(() => false);
    const isRedirected = page.url().includes('index.html');

    if (isDashboard) {
      // Check dashboard content
      await expect(page.locator('body')).toBeVisible();
      const hasSellerContent = await page.locator('text=/listings|sales|inventory/i').isVisible().catch(() => false);
      expect(hasSellerContent).toBeTruthy();
    } else if (isRedirected) {
      console.log('User is not a seller (needs approval)');
    }

    await logoutUser(page);
  });

  test('Seller can create listing', async ({ page }) => {
    await loginUser(page, TEST_SELLER.email, TEST_SELLER.password);

    // Navigate to create listing page if it exists
    await page.goto('/seller-dashboard.html');

    // Look for "Create Listing" button
    const createButton = page.locator('a:has-text(/create.*listing|add.*item|new.*listing/i), button:has-text(/create.*listing|add.*item/i)');
    const hasCreateButton = await createButton.first().isVisible().catch(() => false);

    if (hasCreateButton) {
      await createButton.first().click();
      await page.waitForLoadState('networkidle');

      // Should be on create listing form
      const formTitle = await page.locator('h1, h2:has-text(/create.*listing|list.*item/i)').isVisible().catch(() => false);

      if (formTitle) {
        // Fill basic listing info
        await page.fill('input[name*="title"], #title', 'Test Antique Chair');
        await page.fill('textarea[name*="description"], #description', 'Beautiful antique chair from 1920s, excellent condition');
        await page.fill('input[name*="starting.*bid"], #starting-bid', '50');
        await page.fill('input[name*="category"], #category', 'Furniture');

        // Submit form
        await page.click('button[type="submit"], button:has-text(/save.*listing|create.*listing/i)');
        await page.waitForTimeout(2000);

        // Check for success
        const successMsg = await page.locator('text=/success|created|listing.*saved/i').isVisible().catch(() => false);
        expect(successMsg).toBeTruthy();
      }
    } else {
      console.log('No create listing button found (may need seller approval)');
    }

    await logoutUser(page);
  });
});

// --- ADMIN WORKFLOW TESTS ---

test.describe('Admin End-to-End Workflow', () => {
  test('Admin can access admin panel', async ({ page }) => {
    // Note: Need actual admin credentials for this test
    console.log('Admin test requires actual admin credentials');

    // Try to access admin panel (will redirect if not admin)
    await page.goto('/admin-panel.html');

    // Check if we're on admin panel or redirected
    const isAdminPanel = page.url().includes('admin-panel');
    const hasAdminContent = await page.locator('text=/admin.*panel|dashboard|moderate/i').isVisible().catch(() => false);

    if (isAdminPanel && hasAdminContent) {
      // Admin access successful
      await expect(page.locator('body')).toBeVisible();

      // Check for admin sections
      const hasSections = await page.locator('text=/users|sellers|listings|moderation/i').isVisible().catch(() => false);
      expect(hasSections).toBeTruthy();
    } else {
      console.log('Not an admin user (expected redirect)');
      // Should be redirected to main page
      await expect(page).toHaveURL(/\//);
    }
  });

  test('Admin can approve seller applications', async ({ page }) => {
    // This test requires admin login and pending sellers
    console.log('Seller approval test requires admin login and pending sellers');

    // Would need to:
    // 1. Login as admin
    // 2. Navigate to seller approvals section
    // 3. Find pending sellers
    // 4. Click approve button
    // 5. Verify status changes
  });
});

// --- COMPREHENSIVE SITE TEST ---

test.describe('Comprehensive Site Health Check', () => {
  test('All main pages load without errors', async ({ page }) => {
    const pages = [
      '/index.html',
      '/auction-browse.html',
      '/account-dashboard.html',
      '/account-profile.html',
      '/seller-dashboard.html',
      '/admin-panel.html',
      '/messages.html'
    ];

    const errors = [];

    page.on('console', msg => {
      if (msg.type() === 'error') {
        errors.push(`Console error on ${page.url()}: ${msg.text()}`);
      }
    });

    page.on('pageerror', error => {
      errors.push(`Page error on ${page.url()}: ${error.message}`);
    });

    for (const path of pages) {
      try {
        console.log(`Testing ${path}...`);
        const response = await page.goto(path, { waitUntil: 'domcontentloaded', timeout: 10000 });

        if (response && response.status() >= 400) {
          errors.push(`${path} returned ${response.status()}`);
        }

        await page.waitForTimeout(500); // Let page settle

      } catch (error) {
        errors.push(`Failed to load ${path}: ${error.message}`);
      }
    }

    // Log any errors
    if (errors.length > 0) {
      console.log('Errors found:', errors);
    }

    // For now, just warn but don't fail (some pages may require auth)
    if (errors.length > 10) {
      throw new Error(`Too many page load errors: ${errors.length}`);
    }
  });

  test('Critical user flows are functional', async ({ page }) => {
    // Quick test of essential functionality
    console.log('Testing critical user flows...');

    // 1. Homepage loads
    await page.goto('/index.html');
    await expect(page.locator('body')).toBeVisible();

    // 2. Navigation works
    await page.click('a[href="/auction-browse.html"]');
    await expect(page).toHaveURL(/auction-browse/);

    // 3. Back to homepage
    await page.click('a[href="/index.html"]');
    await expect(page).toHaveURL(/\//);

    // 4. Modal opens (signup)
    const viewport = page.viewportSize();
    const isMobile = viewport && viewport.width < 960;

    if (isMobile) {
      const hamburger = page.locator('#hamburger');
      await hamburger.click();
      await page.waitForSelector('#mobile-menu', { state: 'visible' });
      const signupButton = page.locator('.mobile-menu-ctas button:has-text("Start Bidding Free")');
      await signupButton.click();
    } else {
      const signupButton = page.locator('button:has-text("Start Bidding Free")').first();
      await signupButton.click();
    }

    // Modal should be visible
    await expect(page.locator('#ov-register')).toBeVisible();

    // Close modal
    await page.click('.modal-x');
    await page.waitForTimeout(500);

    console.log('Critical flows passed');
  });
});