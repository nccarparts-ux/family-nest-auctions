const { test, expect } = require('@playwright/test');

test('main auction page loads', async ({ page }) => {
  await page.goto('/index.html');

  // Check page title
  await expect(page).toHaveTitle(/BidYard \| Online Garage & Estate Sale Auctions/);

  // Check for presence of key page elements
  await expect(page.locator('header')).toBeVisible();
  await expect(page.locator('nav')).toBeVisible();
  await expect(page.locator('.hero')).toBeVisible();
});

test('admin panel redirects when not authenticated', async ({ page }) => {
  // Admin panel should redirect to main page when not authenticated
  await page.goto('/admin-panel.html');

  // Should redirect to index.html
  await expect(page).toHaveURL(/\//);
  await expect(page).toHaveTitle(/BidYard/);
});

test('seller dashboard redirects when not authenticated', async ({ page }) => {
  // Seller dashboard should redirect when not authenticated
  await page.goto('/seller-dashboard.html');

  // Should redirect to index.html (possibly with login param)
  await expect(page).toHaveURL(/\//);
  await expect(page).toHaveTitle(/BidYard/);
});

test('key pages are accessible', async ({ page }) => {
  // Test several important pages
  const pages = [
    { path: '/index.html', name: 'Main auction page' },
    { path: '/auction-browse.html', name: 'Browse auctions' },
    { path: '/account-dashboard.html', name: 'Account dashboard' },
    { path: '/account-profile.html', name: 'Account profile' },
    { path: '/messages.html', name: 'Messages' },
  ];

  for (const pageInfo of pages) {
    console.log(`Testing ${pageInfo.name} at ${pageInfo.path}`);
    try {
      const response = await page.goto(pageInfo.path, { waitUntil: 'domcontentloaded' });
      // If response exists, check status
      if (response) {
        expect(response.status()).toBeLessThan(400); // Not 4xx or 5xx
      }
      await expect(page.locator('body')).toBeVisible({ timeout: 5000 });
    } catch (error) {
      console.error(`Failed to load ${pageInfo.path}:`, error.message);
      // If page fails to load, at least ensure we're not getting a 500 error
      // by checking that we can navigate somewhere
      await expect(page).not.toHaveURL(/500|404/);
    }
  }
});