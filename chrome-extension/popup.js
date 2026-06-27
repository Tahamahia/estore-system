/**
 * eStore Cart Extractor — Popup Controller
 *
 * Orchestrates:
 *  1. Settings management (API URL + JWT stored in chrome.storage.local)
 *  2. Cart extraction via content script injection
 *  3. Preview of extracted items
 *  4. Authenticated POST to the eStore API
 */

document.addEventListener('DOMContentLoaded', async () => {
  // ─── DOM References ─────────────────────────────────────
  const $apiUrl = document.getElementById('apiUrl');
  const $jwtToken = document.getElementById('jwtToken');
  const $saveSettings = document.getElementById('saveSettings');
  const $testConnection = document.getElementById('testConnection');
  const $settingsToggle = document.getElementById('settingsToggle');
  const $settingsPanel = document.getElementById('settingsPanel');
  const $connectionStatus = document.getElementById('connectionStatus');
  const $statusText = document.getElementById('statusText');
  const $customerName = document.getElementById('customerName');
  const $customerPhone = document.getElementById('customerPhone');
  const $platform = document.getElementById('platform');
  const $extractBtn = document.getElementById('extractBtn');
  const $sendBtn = document.getElementById('sendBtn');
  const $errorBox = document.getElementById('errorBox');
  const $successBox = document.getElementById('successBox');
  const $resultsSection = document.getElementById('resultsSection');
  const $itemCount = document.getElementById('itemCount');
  const $platformBadge = document.getElementById('platformBadge');
  const $itemList = document.getElementById('itemList');

  let extractedItems = [];
  let extractionMeta = {};

  // ─── Settings Management ────────────────────────────────

  // Load saved settings
  const stored = await chrome.storage.local.get(['apiUrl', 'jwtToken', 'customerName', 'customerPhone']);
  if (stored.apiUrl) $apiUrl.value = stored.apiUrl;
  if (stored.jwtToken) $jwtToken.value = stored.jwtToken;
  if (stored.customerName) $customerName.value = stored.customerName;
  if (stored.customerPhone) $customerPhone.value = stored.customerPhone;

  // Update connection status based on saved config
  updateConnectionStatus();

  $settingsToggle.addEventListener('click', () => {
    $settingsPanel.classList.toggle('visible');
    $settingsToggle.textContent = $settingsPanel.classList.contains('visible')
      ? '⚙️ Hide Settings' : '⚙️ API Settings';
  });

  $saveSettings.addEventListener('click', async () => {
    await chrome.storage.local.set({
      apiUrl: $apiUrl.value.trim().replace(/\/$/, ''),
      jwtToken: $jwtToken.value.trim(),
    });
    updateConnectionStatus();
    showSuccess('Settings saved!');
  });

  $testConnection.addEventListener('click', async () => {
    const baseUrl = $apiUrl.value.trim().replace(/\/$/, '');
    if (!baseUrl) return showError('Enter API URL first');

    try {
      setStatus('extracting', 'Testing connection...');
      // Test health endpoint (no auth needed)
      const healthUrl = baseUrl.replace(/\/api\/v1$/, '/health');
      const resp = await fetch(healthUrl);
      const data = await resp.json();
      if (data.status === 'ok') {
        setStatus('connected', `Connected — v${data.version}`);
      } else {
        setStatus('disconnected', 'Unexpected response');
      }
    } catch (err) {
      setStatus('disconnected', 'Connection failed');
      showError(`Cannot reach API: ${err.message}`);
    }
  });

  // ─── Extraction Flow ────────────────────────────────────

  $extractBtn.addEventListener('click', async () => {
    hideMessages();
    $extractBtn.disabled = true;
    $extractBtn.innerHTML = '<div class="spinner"></div> Extracting...';

    try {
      // Get the active tab
      const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
      if (!tab?.id) throw new Error('No active tab found');

      // Check if we're on a supported site
      const url = tab.url || '';
      if (!url.includes('shein') && !url.includes('trendyol')) {
        throw new Error('Navigate to a Shein or Trendyol cart page first');
      }

      // Auto-detect platform from URL
      if (url.includes('shein')) $platform.value = 'shein';
      if (url.includes('trendyol')) $platform.value = 'trendyol';

      // Inject content script if not already loaded, then send extraction message
      await chrome.scripting.executeScript({
        target: { tabId: tab.id },
        files: ['content.js'],
      });

      // Small delay to let content script initialize
      await new Promise(r => setTimeout(r, 300));

      // Request extraction from content script
      const result = await chrome.tabs.sendMessage(tab.id, { action: 'extractCart' });

      if (!result || !result.success) {
        throw new Error(result?.error || 'Extraction returned no data');
      }

      extractedItems = result.items;
      extractionMeta = { platform: result.platform, strategy: result.strategy };

      // Show results
      renderResults();

    } catch (err) {
      showError(err.message);
    } finally {
      $extractBtn.disabled = false;
      $extractBtn.innerHTML = '🔍 Extract Cart & Send to System';
    }
  });

  // ─── Send to API ────────────────────────────────────────

  $sendBtn.addEventListener('click', async () => {
    hideMessages();
    const baseUrl = $apiUrl.value.trim().replace(/\/$/, '');
    const token = $jwtToken.value.trim();
    const customerName = $customerName.value.trim();
    const customerPhone = $customerPhone.value.trim();

    if (!baseUrl || !token) {
      showError('Configure API URL and JWT Token in settings first');
      $settingsPanel.classList.add('visible');
      return;
    }

    if (!customerName) {
      showError('Enter customer name');
      return;
    }

    if (extractedItems.length === 0) {
      showError('No items to send. Extract cart first.');
      return;
    }

    $sendBtn.disabled = true;
    $sendBtn.innerHTML = '<div class="spinner"></div> Sending...';

    try {
      // Save customer info for next time
      await chrome.storage.local.set({ customerName, customerPhone });

      // Step 1: Find or create customer
      const customerId = await findOrCreateCustomer(baseUrl, token, customerName, customerPhone);

      // Step 2: Create order with items
      const orderId = generateUUID();
      const items = extractedItems.map(item => ({
        id: generateUUID(),
        product_name: item.product_name,
        product_url: item.product_url || '',
        product_image_url: item.image_url || '',
        quantity: item.quantity || 1,
        unit_price_foreign: item.price || 0,
        unit_price_local: 0,
        color: item.color || '',
        size: item.size || '',
        sku: item.sku || '',
        notes: `Extracted from ${extractionMeta.platform} cart via Chrome Extension`,
      }));

      const orderPayload = {
        id: orderId,
        customer_id: customerId,
        platform: extractionMeta.platform || $platform.value,
        currency: 'USD',
        items,
      };

      const resp = await fetch(`${baseUrl}/orders`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${token}`,
          'Idempotency-Key': `ext-${orderId}`,
        },
        body: JSON.stringify(orderPayload),
      });

      if (!resp.ok) {
        const err = await resp.json().catch(() => ({}));
        throw new Error(err.message || `API returned ${resp.status}`);
      }

      showSuccess(`✅ Order created! ${items.length} items pushed.\nOrder ID: ${orderId.substring(0, 8)}...`);

      // Clear extracted items
      extractedItems = [];
      $resultsSection.classList.remove('visible');

    } catch (err) {
      showError(`Send failed: ${err.message}`);
    } finally {
      $sendBtn.disabled = false;
      $sendBtn.innerHTML = '📤 Confirm & Push to eStore API';
    }
  });

  // ─── Helpers ────────────────────────────────────────────

  async function findOrCreateCustomer(baseUrl, token, name, phone) {
    const headers = {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${token}`,
    };

    // Try to find existing customer by name
    try {
      const resp = await fetch(`${baseUrl}/customers?search=${encodeURIComponent(name)}`, { headers });
      if (resp.ok) {
        const data = await resp.json();
        const customers = data.data || data;
        if (Array.isArray(customers)) {
          const match = customers.find(c =>
            c.full_name?.toLowerCase() === name.toLowerCase() ||
            c.phone === phone
          );
          if (match) return match.id;
        }
      }
    } catch { /* proceed to create */ }

    // Create new customer
    const customerId = generateUUID();
    const resp = await fetch(`${baseUrl}/customers`, {
      method: 'POST',
      headers: { ...headers, 'Idempotency-Key': `ext-cust-${customerId}` },
      body: JSON.stringify({
        id: customerId,
        full_name: name,
        phone: phone || null,
      }),
    });

    if (!resp.ok) {
      const err = await resp.json().catch(() => ({}));
      throw new Error(`Failed to create customer: ${err.message || resp.status}`);
    }

    return customerId;
  }

  function renderResults() {
    $itemCount.textContent = extractedItems.length;
    $platformBadge.textContent = extractionMeta.platform || '';
    $platformBadge.className = `platform-badge ${extractionMeta.platform || ''}`;

    $itemList.innerHTML = '';
    for (const item of extractedItems) {
      const card = document.createElement('div');
      card.className = 'result-card';

      const imgSrc = item.image_url || 'data:image/svg+xml,<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 56 56"><rect fill="%23252547" width="56" height="56"/><text x="50%" y="55%" text-anchor="middle" fill="%236c5ce7" font-size="20">📦</text></svg>';

      card.innerHTML = `
        <img src="${escapeHtml(imgSrc)}" alt="" onerror="this.src='data:image/svg+xml,<svg xmlns=%22http://www.w3.org/2000/svg%22 viewBox=%220 0 56 56%22><rect fill=%22%23252547%22 width=%2256%22 height=%2256%22/><text x=%2250%25%22 y=%2255%25%22 text-anchor=%22middle%22 fill=%22%236c5ce7%22 font-size=%2220%22>📦</text></svg>'">
        <div class="result-info">
          <div class="result-name">${escapeHtml(item.product_name)}</div>
          <div class="result-meta">
            ${item.size ? `Size: ${escapeHtml(item.size)}` : ''}
            ${item.size && item.color ? ' · ' : ''}
            ${item.color ? `Color: ${escapeHtml(item.color)}` : ''}
            ${item.quantity > 1 ? ` · Qty: ${item.quantity}` : ''}
            ${item.price ? ` · $${item.price.toFixed(2)}` : ''}
          </div>
          ${item.sku ? `<span class="result-sku">SKU: ${escapeHtml(item.sku)}</span>` : '<span class="result-sku" style="color:var(--warning)">⚠ No SKU</span>'}
        </div>
      `;

      $itemList.appendChild(card);
    }

    $resultsSection.classList.add('visible');
  }

  function updateConnectionStatus() {
    const url = $apiUrl.value.trim();
    const token = $jwtToken.value.trim();
    if (url && token) {
      setStatus('connected', 'Configured');
    } else if (url) {
      setStatus('disconnected', 'Missing JWT Token');
    } else {
      setStatus('disconnected', 'Not configured');
    }
  }

  function setStatus(type, text) {
    $connectionStatus.className = `status ${type}`;
    $statusText.textContent = text;
  }

  function showError(msg) {
    $errorBox.textContent = msg;
    $errorBox.classList.add('visible');
    $successBox.classList.remove('visible');
  }

  function showSuccess(msg) {
    $successBox.textContent = msg;
    $successBox.classList.add('visible');
    $errorBox.classList.remove('visible');
  }

  function hideMessages() {
    $errorBox.classList.remove('visible');
    $successBox.classList.remove('visible');
  }

  function escapeHtml(str) {
    const div = document.createElement('div');
    div.textContent = str || '';
    return div.innerHTML;
  }

  function generateUUID() {
    return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, c => {
      const r = Math.random() * 16 | 0;
      const v = c === 'x' ? r : (r & 0x3 | 0x8);
      return v.toString(16);
    });
  }
});
