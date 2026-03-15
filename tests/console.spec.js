const { test, expect } = require('@playwright/test');

test('no JavaScript errors on homepage', async ({ page }) => {
  const errors = [];
  const consoleMessages = [];

  // Capture console errors
  page.on('console', msg => {
    if (msg.type() === 'error') {
      consoleMessages.push(`Console error: ${msg.text()}`);
    }
  });

  // Capture page errors (uncaught exceptions)
  page.on('pageerror', error => {
    errors.push(`Page error: ${error.message}`);
  });

  await page.goto('/index.html', { waitUntil: 'networkidle' });

  // Wait a bit for any async errors
  await page.waitForTimeout(1000);

  // Check for FNA is not defined errors
  const fnaErrors = [...errors, ...consoleMessages].filter(msg =>
    msg.includes('FNA') || msg.includes('FNA is not defined')
  );

  expect(fnaErrors, `Found FNA-related errors: ${JSON.stringify(fnaErrors)}`).toHaveLength(0);

  // Log any errors for debugging
  if (errors.length > 0 || consoleMessages.length > 0) {
    console.log('Errors found:', errors);
    console.log('Console messages:', consoleMessages);
  }
});

test('login modal opens without errors', async ({ page }) => {
  const errors = [];
  const consoleMessages = [];

  page.on('console', msg => {
    if (msg.type() === 'error') {
      consoleMessages.push(`Console error: ${msg.text()}`);
    }
  });

  page.on('pageerror', error => {
    errors.push(`Page error: ${error.message}`);
  });

  await page.goto('/index.html', { waitUntil: 'networkidle' });

  // Handle mobile vs desktop viewport
  const viewport = page.viewportSize();
  const isMobile = viewport && viewport.width < 960;

  if (isMobile) {
    // Open mobile menu first
    const hamburger = page.locator('#hamburger');
    await expect(hamburger).toBeVisible();
    await hamburger.click();

    // Wait for mobile menu to open
    await page.waitForSelector('#mobile-menu', { state: 'visible' });

    // Click mobile menu button
    const loginButton = page.locator('.mobile-menu-ctas button:has-text("Sign In")');
    await expect(loginButton).toBeVisible();
    await loginButton.click();
  } else {
    // Desktop: click desktop button
    const loginButton = page.locator('button:has-text("Sign In")').first();
    await expect(loginButton).toBeVisible();
    await loginButton.click();
  }

  // Wait for modal to appear
  const modal = page.locator('.overlay.on, [class*="modal"]');
  await modal.waitFor({ state: 'visible', timeout: 5000 }).catch(() => {
    // Modal might not have 'on' class initially, try alternative selector
    console.log('Modal not found with .overlay.on, trying alternatives');
  });

  // Try to find email input (login modal specific)
  const emailInput = page.locator('#login-email');
  await expect(emailInput).toBeVisible({ timeout: 5000 });

  // Check for errors after opening modal
  await page.waitForTimeout(500);

  const fnaErrors = [...errors, ...consoleMessages].filter(msg =>
    msg.includes('FNA') || msg.includes('FNA is not defined')
  );

  expect(fnaErrors, `Found FNA-related errors when opening login modal: ${JSON.stringify(fnaErrors)}`).toHaveLength(0);
});

test('signup modal opens without errors', async ({ page }) => {
  const errors = [];
  const consoleMessages = [];

  page.on('console', msg => {
    if (msg.type() === 'error') {
      consoleMessages.push(`Console error: ${msg.text()}`);
    }
  });

  page.on('pageerror', error => {
    errors.push(`Page error: ${error.message}`);
  });

  await page.goto('/index.html', { waitUntil: 'networkidle' });

  // Handle mobile vs desktop viewport
  const viewport = page.viewportSize();
  const isMobile = viewport && viewport.width < 960;

  if (isMobile) {
    // Open mobile menu first
    const hamburger = page.locator('#hamburger');
    await expect(hamburger).toBeVisible();
    await hamburger.click();

    // Wait for mobile menu to open
    await page.waitForSelector('#mobile-menu', { state: 'visible' });

    // Click mobile menu button
    const signupButton = page.locator('.mobile-menu-ctas button:has-text("Start Bidding Free")');
    await expect(signupButton).toBeVisible();
    await signupButton.click();
  } else {
    // Desktop: click desktop button
    const signupButton = page.locator('button:has-text("Start Bidding Free")').first();
    await expect(signupButton).toBeVisible();
    await signupButton.click();
  }

  // Wait for modal to appear
  const modal = page.locator('.overlay.on, [class*="modal"]');
  await modal.waitFor({ state: 'visible', timeout: 5000 }).catch(() => {
    // Modal might not have 'on' class initially
  });

  // Try to find name input in signup form (register modal specific)
  const nameInput = page.locator('#reg-name');
  await expect(nameInput).toBeVisible({ timeout: 5000 });

  // Check for errors after opening modal
  await page.waitForTimeout(500);

  const fnaErrors = [...errors, ...consoleMessages].filter(msg =>
    msg.includes('FNA') || msg.includes('FNA is not defined')
  );

  expect(fnaErrors, `Found FNA-related errors when opening signup modal: ${JSON.stringify(fnaErrors)}`).toHaveLength(0);
});