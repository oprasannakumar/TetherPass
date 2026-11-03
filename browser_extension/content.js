/**
 * CardVault Content Script
 * Detects payment, bank account, and credential input fields and renders
 * floating inline autofill suggestion chips when authorized by mobile app.
 */

(function () {
  let activeDropdown = null;
  let activeInput = null;
  let selectedItemIndex = -1;
  let managedInput = null;
  let originalAutocomplete = null;

  function suppressBrowserAutofill(input) {
    if (!input) return;
    managedInput = input;
    originalAutocomplete = input.getAttribute('autocomplete');
    input.setAttribute('autocomplete', 'off');
  }

  function restoreBrowserAutofill() {
    if (managedInput) {
      if (originalAutocomplete !== null) {
        managedInput.setAttribute('autocomplete', originalAutocomplete);
      } else {
        managedInput.removeAttribute('autocomplete');
      }
      managedInput = null;
      originalAutocomplete = null;
    }
  }

  function updateRowHighlight(rows) {
    if (!rows) return;
    rows.forEach((r, idx) => {
      if (idx === selectedItemIndex) {
        r.classList.add('cv-selected');
        r.scrollIntoView({ block: 'nearest' });
      } else {
        r.classList.remove('cv-selected');
      }
    });
  }


  function getElementTextContext(input) {
    if (!input) return '';
    const pieces = [];

    if (input.name) pieces.push(input.name);
    if (input.id) pieces.push(input.id);
    if (input.placeholder) pieces.push(input.placeholder);
    if (input.title) pieces.push(input.title);
    if (input.getAttribute('autocomplete')) pieces.push(input.getAttribute('autocomplete'));
    if (input.getAttribute('aria-label')) pieces.push(input.getAttribute('aria-label'));
    if (input.getAttribute('aria-placeholder')) pieces.push(input.getAttribute('aria-placeholder'));
    if (input.getAttribute('data-testid')) pieces.push(input.getAttribute('data-testid'));
    if (input.getAttribute('data-field')) pieces.push(input.getAttribute('data-field'));

    // Check aria-labelledby & aria-describedby
    const labelledBy = input.getAttribute('aria-labelledby');
    if (labelledBy) {
      labelledBy.split(/\s+/).forEach(id => {
        const el = document.getElementById(id);
        if (el && el.textContent) pieces.push(el.textContent.trim());
      });
    }
    const describedBy = input.getAttribute('aria-describedby');
    if (describedBy) {
      describedBy.split(/\s+/).forEach(id => {
        const el = document.getElementById(id);
        if (el && el.textContent) pieces.push(el.textContent.trim());
      });
    }

    // Check associated HTML <label> elements
    if (input.labels && input.labels.length > 0) {
      for (const lbl of input.labels) {
        if (lbl.textContent) pieces.push(lbl.textContent.trim());
      }
    }

    // Check closest label or container
    const parentLabel = input.closest('label');
    if (parentLabel && parentLabel.textContent) pieces.push(parentLabel.textContent.trim());

    // Check previous & next siblings
    let sib = input.previousElementSibling;
    let sibCount = 0;
    while (sib && sibCount < 3) {
      const txt = sib.textContent ? sib.textContent.trim() : '';
      if (txt && txt.length < 80) pieces.push(txt);
      sib = sib.previousElementSibling;
      sibCount++;
    }
    sib = input.nextElementSibling;
    sibCount = 0;
    while (sib && sibCount < 3) {
      const txt = sib.textContent ? sib.textContent.trim() : '';
      if (txt && txt.length < 80) pieces.push(txt);
      sib = sib.nextElementSibling;
      sibCount++;
    }

    // Inspect immediate field container for floating labels / headers
    let cur = input.parentElement;
    for (let depth = 0; depth < 2 && cur && cur !== document.body && cur.tagName !== 'FORM'; depth++) {
      if (cur.className && typeof cur.className === 'string') pieces.push(cur.className);
      if (cur.id) pieces.push(cur.id);

      // Only inspect descendant text elements if this container is dedicated to this input
      // (does not wrap multiple separate inputs like an entire form or table)
      const siblingInputs = cur.querySelectorAll('input:not([type="hidden"])');
      if (siblingInputs.length <= 1) {
        const textEls = cur.querySelectorAll('label, span, div, p, strong, b, small, h1, h2, h3, h4, h5, h6');
        textEls.forEach(el => {
          if (el !== input && !el.contains(input)) {
            const txt = el.textContent ? el.textContent.trim() : '';
            if (txt && txt.length > 0 && txt.length < 60) {
              pieces.push(txt);
            }
          }
        });
      }
      cur = cur.parentElement;
    }

    return pieces.join(' ').toLowerCase();
  }

  // Field type classifiers
  function classifyInput(input) {
    if (!input || input.type === 'hidden' || input.type === 'submit' || input.type === 'button') return null;

    const raw = getElementTextContext(input);
    const norm = raw.replace(/[-_./]/g, ' ');
    const type = (input.type || '').toLowerCase();
    const autocomplete = (input.getAttribute('autocomplete') || '').toLowerCase();
    const ph = (input.placeholder || '').toLowerCase();

    // 0. Explicit Password Input Type
    if (type === 'password') {
      if (input.maxLength >= 3 && input.maxLength <= 4 && (norm.includes('cvv') || norm.includes('cvc') || norm.includes('security code'))) {
        return 'CVV';
      }
      return 'PASSWORD';
    }

    // 1. 2FA / TOTP / One-Time Passcode
    if (
      autocomplete.includes('one-time-code') ||
      raw.includes('totp') || raw.includes('2fa') || raw.includes('mfa') ||
      raw.includes('otp') || raw.includes('authenticator') ||
      (type === 'text' && input.maxLength === 6 && (norm.includes('code') || norm.includes('pin')))
    ) {
      return 'TOTP';
    }

    // 2. CVV / Security Code
    if (
      autocomplete.includes('cc-csc') || autocomplete.includes('security-code') ||
      raw.includes('cvv') || raw.includes('cvc') || raw.includes('cid') || raw.includes('csc') ||
      norm.includes('security code') || norm.includes('verification code')
    ) {
      return 'CVV';
    }

    // 3. Expiry Date
    if (
      autocomplete.includes('cc-exp') || norm.includes('expiry') || norm.includes('expire') ||
      norm.includes('expiration') || norm.includes('exp date') || norm.includes('expiry date') ||
      norm.includes('valid thru') || norm.includes('valid till') || norm.includes('valid upto') ||
      raw.includes('mm/yy') || raw.includes('mm / yy') || raw.includes('mm-yy') || raw.includes('mmyy') ||
      raw.includes('ccexp') || raw.includes('card_exp')
    ) {
      return 'EXPIRY';
    }

    // 4. Cardholder Name (Check BEFORE Card Number so "Name on Card" matches Cardholder Name!)
    if (
      autocomplete.includes('cc-name') || raw.includes('cardholder') || raw.includes('card_holder') ||
      norm.includes('name on card') || norm.includes('card holder') || norm.includes('cardholder') ||
      raw.includes('card_name') || raw.includes('cardname') ||
      ((norm.includes('name') || norm.includes('holder')) && norm.includes('card') && !norm.includes('nickname'))
    ) {
      return 'CARD_HOLDER';
    }

    // 5. Card Number
    if (
      autocomplete.includes('cc-number') || raw.includes('cardnumber') || raw.includes('card_number') ||
      raw.includes('card_no') || raw.includes('cardno') || norm.includes('card number') ||
      norm.includes('card no') || raw.includes('cc_num') || raw.includes('cc-num') || raw.includes('ccnum') ||
      ph.includes('xxxx') || ph.includes('••••') ||
      (norm.includes('card') && !norm.includes('holder') && !norm.includes('name') && !norm.includes('exp') && !norm.includes('cvv') && !norm.includes('nickname')) ||
      (type === 'tel' && (norm.includes('credit') || norm.includes('debit') || norm.includes('card')))
    ) {
      return 'CARD_NUMBER';
    }

    // 6. Bank IFSC Code
    if (raw.includes('ifsc') || norm.includes('ifsc code') || norm.includes('bank code')) {
      return 'IFSC';
    }

    // 7. Bank Account Number
    if (
      raw.includes('account_number') || raw.includes('accountnumber') || raw.includes('acc_num') ||
      raw.includes('acc_no') || norm.includes('account number') || norm.includes('account no') ||
      norm.includes('bank account')
    ) {
      return 'ACCOUNT_NUMBER';
    }

    // 8. User ID / Customer ID / Username / Email / Netbanking ID (Checked BEFORE generic text password!)
    if (
      type === 'email' || autocomplete.includes('username') || autocomplete.includes('email') ||
      raw.includes('customer id') || raw.includes('customer_id') || raw.includes('cust_id') ||
      raw.includes('user id') || raw.includes('userid') || raw.includes('user_id') ||
      raw.includes('username') || raw.includes('user_name') || raw.includes('email') ||
      raw.includes('login id') || raw.includes('cif') || norm.includes('customer id') || norm.includes('user id') ||
      raw.includes('login')
    ) {
      return 'USER_ID';
    }

    // 9. Text-based Password / MPIN (e.g. unmasked password toggled with eye icon, strictly requires password keywords in its own attributes)
    const selfName = (input.name || '').toLowerCase();
    const selfId = (input.id || '').toLowerCase();
    if (
      autocomplete.includes('current-password') || autocomplete.includes('new-password') ||
      selfName.includes('password') || selfName.includes('pass') || selfName.includes('pwd') || selfName.includes('mpin') ||
      selfId.includes('password') || selfId.includes('pass') || selfId.includes('pwd') || selfId.includes('mpin')
    ) {
      if (!selfName.includes('user') && !selfId.includes('user') && !selfName.includes('cust') && !selfId.includes('cust')) {
        return 'PASSWORD';
      }
    }

    return null;
  }

  function isInputFilled(input) {
    if (!input) return false;
    if (typeof input.value === 'string' && input.value.trim().length > 0) return true;
    if (input.dataset && input.dataset.tpFilled === 'true') return true;
    try {
      if (input.matches && (input.matches(':-webkit-autofill') || input.matches(':autofill'))) {
        return true;
      }
    } catch (_) {}
    return false;
  }

  function clearInputFilledState(input) {
    if (input && input.dataset) {
      delete input.dataset.tpFilled;
    }
  }

  function requestSuggestionsForInput(target, fieldType) {
    if (!target || isInputFilled(target)) {
      removeDropdown();
      return;
    }

    chrome.runtime.sendMessage(
      { action: 'GET_AUTOFILL_SUGGESTIONS', payload: { fieldType, domain: window.location.hostname } },
      (response) => {
        // Double check target is still active/focused element and still completely empty before rendering
        if (!response || (document.activeElement !== target && !target.matches(':focus'))) return;
        if (isInputFilled(target)) {
          removeDropdown();
          return;
        }
        renderDropdown(target, fieldType, response);
      }
    );
  }

  function handleInputInteraction(target) {
    if (!target || target.tagName !== 'INPUT') return;
    if (isInputFilled(target)) {
      removeDropdown();
      return;
    }

    const fieldType = classifyInput(target);
    if (!fieldType) {
      removeDropdown();
      return;
    }

    // Immediately suppress browser native autofill so browser password manager does not hijack
    suppressBrowserAutofill(target);

    activeInput = target;
    requestSuggestionsForInput(target, fieldType);
  }

  // Handle focus on fields
  document.addEventListener('focusin', (e) => {
    handleInputInteraction(e.target);
  });

  // Handle click on fields (triggers suggestions even if field was already focused)
  document.addEventListener('click', (e) => {
    const target = e.target;
    if (target && target.tagName === 'INPUT') {
      if (isInputFilled(target)) {
        removeDropdown();
      } else {
        handleInputInteraction(target);
      }
    }
  });

  // Handle typing, clearing, and pasting in fields
  document.addEventListener('input', (e) => {
    const target = e.target;
    if (!target || target.tagName !== 'INPUT') return;

    // If text box now contains text/credentials, dismiss suggestions immediately
    if (isInputFilled(target)) {
      removeDropdown();
      return;
    }

    // If text box is cleared (empty), and user is actively focused on it, re-trigger suggestions
    clearInputFilledState(target);
    if (document.activeElement === target && (!target.value || target.value.trim().length === 0)) {
      handleInputInteraction(target);
    }
  });

  // Listen for Backspace/Delete clearing
  document.addEventListener('keyup', (e) => {
    const target = e.target;
    if (!target || target.tagName !== 'INPUT') return;

    if (isInputFilled(target)) {
      removeDropdown();
      return;
    }

    clearInputFilledState(target);
    if (document.activeElement === target && (!target.value || target.value.trim().length === 0)) {
      if (!activeDropdown) {
        handleInputInteraction(target);
      }
    }
  });

  // If a field is autofocused on page load (e.g. GitHub username or 2FA):
  if (document.activeElement && document.activeElement.tagName === 'INPUT' && !isInputFilled(document.activeElement)) {
    handleInputInteraction(document.activeElement);
  }

  // Close dropdown on outside click
  document.addEventListener('mousedown', (e) => {
    if (activeDropdown && !activeDropdown.contains(e.target) && e.target !== activeInput) {
      removeDropdown();
    }
  });



  // Intercept ArrowDown, ArrowUp, Enter, and Escape in capture phase
  // so browser native password manager (Google Password Manager) DOES NOT hijack!
  document.addEventListener('keydown', (e) => {
    if (!activeDropdown) return;

    const rows = activeDropdown.querySelectorAll('.cv-item-row');
    if (!rows || rows.length === 0) return;

    if (e.key === 'ArrowDown') {
      e.preventDefault();
      e.stopPropagation();
      e.stopImmediatePropagation();

      selectedItemIndex++;
      if (selectedItemIndex >= rows.length) selectedItemIndex = 0;
      updateRowHighlight(rows);
      return;
    }

    if (e.key === 'ArrowUp') {
      e.preventDefault();
      e.stopPropagation();
      e.stopImmediatePropagation();

      selectedItemIndex--;
      if (selectedItemIndex < 0) selectedItemIndex = rows.length - 1;
      updateRowHighlight(rows);
      return;
    }

    if (e.key === 'Enter') {
      if (selectedItemIndex >= 0 && selectedItemIndex < rows.length) {
        e.preventDefault();
        e.stopPropagation();
        e.stopImmediatePropagation();
        rows[selectedItemIndex].click();
        return;
      }
    }

    if (e.key === 'Escape') {
      e.preventDefault();
      e.stopPropagation();
      removeDropdown();
      return;
    }
  }, true);

  function removeDropdown() {
    restoreBrowserAutofill();
    if (activeDropdown) {
      activeDropdown.remove();
      activeDropdown = null;
      selectedItemIndex = -1;
    }
  }

  function renderDropdown(targetInput, fieldType, data) {
    removeDropdown();

    // Guard: do not render if input already has credentials / value
    if (!targetInput || isInputFilled(targetInput)) {
      return;
    }

    suppressBrowserAutofill(targetInput);

    const rect = targetInput.getBoundingClientRect();
    const dropdown = document.createElement('div');
    dropdown.className = 'cv-autofill-dropdown';
    dropdown.style.left = `${window.scrollX + rect.left}px`;
    dropdown.style.top = `${window.scrollY + rect.bottom + 6}px`;
    dropdown.style.minWidth = `${Math.max(260, rect.width)}px`;

    // ── Header ──
    const header = document.createElement('div');
    header.className = 'cv-dropdown-header';
    header.innerHTML = `
      <div class="cv-header-left">
        <span class="cv-logo-badge">CV</span>
        <span class="cv-title">TetherPass</span>
      </div>
      <span class="cv-status-tag ${data.authorized ? 'cv-authorized' : 'cv-locked'}">
        ${data.authorized ? '● Unlocked' : '🔒 Locked'}
      </span>
    `;
    dropdown.appendChild(header);

    // ── Content ──
    if (!data.authorized) {
      // Locked state: Must authorize from mobile application
      const lockBox = document.createElement('div');
      lockBox.className = 'cv-locked-notice';
      lockBox.innerHTML = `
        <div class="cv-lock-icon">🔒</div>
        <div class="cv-lock-text">
          <strong>Mobile Authorization Required</strong>
          <p>Open <em>TetherPass</em> on your phone → <strong>Settings → Browser Extension</strong> to unlock autofill.</p>
        </div>
      `;
      dropdown.appendChild(lockBox);
    } else {
      const itemsList = document.createElement('div');
      itemsList.className = 'cv-items-list';

      // 1. CARDS (If card field or general payment)
      if (['CARD_NUMBER', 'EXPIRY', 'CVV', 'CARD_HOLDER'].includes(fieldType) && data.cards && data.cards.length > 0) {
        data.cards.forEach(card => {
          const itemRow = document.createElement('div');
          itemRow.className = 'cv-item-row';
          const last4 = card.cardNumber.slice(-4) || '••••';
          itemRow.innerHTML = `
            <div class="cv-item-icon">💳</div>
            <div class="cv-item-info">
              <div class="cv-item-title">${escapeHtml(card.nickname)} (${escapeHtml(card.cardNetwork)})</div>
              <div class="cv-item-sub">•••• ${last4} | Exp: ${escapeHtml(card.expiry || '••/••')}</div>
            </div>
          `;
          itemRow.addEventListener('mouseenter', () => {
            const allRows = itemsList.querySelectorAll('.cv-item-row');
            selectedItemIndex = Array.from(allRows).indexOf(itemRow);
            updateRowHighlight(allRows);
          });
          itemRow.addEventListener('click', (ev) => {
            ev.stopPropagation();
            ev.preventDefault();
            removeDropdown();
            fillCardDetails(targetInput, card, fieldType);
            removeDropdown();
          });
          itemsList.appendChild(itemRow);
        });
      }

      // 2. BANK ACCOUNTS & IFSC (Only for bank account / IFSC transfer fields)
      if (['ACCOUNT_NUMBER', 'IFSC'].includes(fieldType) && data.bankAccounts && data.bankAccounts.length > 0) {
        data.bankAccounts.forEach(bank => {
          if (bank.accounts && bank.accounts.length > 0) {
            bank.accounts.forEach((acc, i) => {
              const itemRow = document.createElement('div');
              itemRow.className = 'cv-item-row';
              itemRow.innerHTML = `
                <div class="cv-item-icon">🏦</div>
                <div class="cv-item-info">
                  <div class="cv-item-title">${escapeHtml(bank.bankName)} ${acc.accountNumber ? '• ' + acc.accountNumber.slice(-4) : ''}</div>
                  <div class="cv-item-sub">A/C: ${escapeHtml(acc.accountNumber)} ${acc.ifscCode ? '| IFSC: ' + escapeHtml(acc.ifscCode) : ''}</div>
                </div>
              `;
              itemRow.addEventListener('mouseenter', () => {
                const allRows = itemsList.querySelectorAll('.cv-item-row');
                selectedItemIndex = Array.from(allRows).indexOf(itemRow);
                updateRowHighlight(allRows);
              });
              itemRow.addEventListener('click', (ev) => {
                ev.stopPropagation();
                ev.preventDefault();
                removeDropdown();
                fillBankAccountDetails(targetInput, acc, bank, fieldType);
                removeDropdown();
              });
              itemsList.appendChild(itemRow);
            });
          }
        });
      }

      // Bank Netbanking Login (ONLY if current website is specifically that bank's website)
      if (['USER_ID', 'PASSWORD'].includes(fieldType) && data.bankAccounts && data.bankAccounts.length > 0) {
        data.bankAccounts.forEach(bank => {
          if (bank.userId || bank.loginPassword) {
            const itemRow = document.createElement('div');
            itemRow.className = 'cv-item-row';
            itemRow.innerHTML = `
              <div class="cv-item-icon">🔑</div>
              <div class="cv-item-info">
                <div class="cv-item-title">${escapeHtml(bank.bankName)} Login</div>
                <div class="cv-item-sub">User: ${escapeHtml(bank.userId || '••••')}</div>
              </div>
            `;
            itemRow.addEventListener('mouseenter', () => {
              const allRows = itemsList.querySelectorAll('.cv-item-row');
              selectedItemIndex = Array.from(allRows).indexOf(itemRow);
              updateRowHighlight(allRows);
            });
            itemRow.addEventListener('click', (ev) => {
              ev.stopPropagation();
              ev.preventDefault();
              removeDropdown();
              fillCredentials(targetInput, bank, fieldType);
              removeDropdown();
            });
            itemsList.appendChild(itemRow);
          }
        });
      }

      // 3. WEBSITE PASSWORDS & 2FA TOTP (Matching current domain)
      if (['TOTP', 'USER_ID', 'PASSWORD'].includes(fieldType) && data.passwords && data.passwords.length > 0) {
        data.passwords.forEach(pwd => {
          if (fieldType === 'TOTP' && !pwd.totpCode) return;
          const itemRow = document.createElement('div');
          itemRow.className = 'cv-item-row';
          const totpBadge = pwd.totpCode ? `<span class="cv-totp-badge">⚡ ${escapeHtml(pwd.totpCode)} (${pwd.totpSeconds}s)</span>` : '';
          itemRow.innerHTML = `
            <div class="cv-item-icon">${fieldType === 'TOTP' ? '🔐' : '🌐'}</div>
            <div class="cv-item-info">
              <div class="cv-item-title">${escapeHtml(pwd.nickname)} ${totpBadge}</div>
              <div class="cv-item-sub">${escapeHtml(pwd.username)} ${pwd.website ? '• ' + escapeHtml(pwd.website) : ''}</div>
            </div>
          `;
          itemRow.addEventListener('mouseenter', () => {
            const allRows = itemsList.querySelectorAll('.cv-item-row');
            selectedItemIndex = Array.from(allRows).indexOf(itemRow);
            updateRowHighlight(allRows);
          });
          itemRow.addEventListener('click', (ev) => {
            ev.stopPropagation();
            ev.preventDefault();
            removeDropdown();
            if (fieldType === 'TOTP' && pwd.totpCode) {
              setInputValue(targetInput, pwd.totpCode);
              try { navigator.clipboard.writeText(pwd.totpCode); } catch (_) {}
            } else {
              fillPasswordCredentials(targetInput, pwd, fieldType);
            }
            removeDropdown();
          });
          itemsList.appendChild(itemRow);
        });
      }

      if (itemsList.children.length === 0) {
        removeDropdown();
        return;
      }

      dropdown.appendChild(itemsList);
      const initialRows = itemsList.querySelectorAll('.cv-item-row');
      if (initialRows.length > 0) {
        selectedItemIndex = 0;
        updateRowHighlight(initialRows);
      }
    }

    document.body.appendChild(dropdown);
    activeDropdown = dropdown;
  }

  // ── Auto-Filling Logic with Input Event Dispatching ──

  function setInputValue(input, value) {
    if (!input || value === undefined || value === null) return;

    const valStr = String(value);

    // 1. Native Property Descriptor Setter (Required for React 16+ SPAs like Flipkart & Blinkit)
    try {
      const nativeSetter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value')?.set;
      if (nativeSetter) {
        nativeSetter.call(input, valStr);
      } else {
        input.value = valStr;
      }
    } catch (_) {
      input.value = valStr;
    }

    // 2. React Internal Tracker Update
    if (input._valueTracker) {
      input._valueTracker.setValue(valStr);
    }

    if (input.dataset) input.dataset.tpFilled = 'true';

    // 3. Dispatch Full Event Suite for modern frameworks
    input.dispatchEvent(new Event('input', { bubbles: true, composed: true }));
    try {
      input.dispatchEvent(new InputEvent('input', { bubbles: true, composed: true, data: valStr, inputType: 'insertText' }));
    } catch (_) {}
    input.dispatchEvent(new Event('change', { bubbles: true, composed: true }));
    input.dispatchEvent(new KeyboardEvent('keyup', { bubbles: true, key: valStr.slice(-1) }));
  }

  function getCardNumberFormattedForInput(input, rawCardNumber) {
    const digits = (rawCardNumber || '').replace(/\D/g, '');
    if (!digits) return '';

    if (input.maxLength === 16) return digits;

    const ph = (input.placeholder || '').toLowerCase();
    // Format as 4-4-4-4 for standard card inputs or placeholders like XXXX XXXX XXXX XXXX
    if (ph.includes(' ') || input.maxLength === 19 || input.maxLength === -1 || !input.maxLength) {
      return digits.replace(/(\d{4})(?=\d)/g, '$1 ').trim();
    }
    return digits;
  }

  function getExpiryFormattedForInput(input, rawExpiry) {
    if (!rawExpiry) return '';
    const clean = rawExpiry.trim();
    const ph = (input.placeholder || '').toLowerCase();
    const hasSpacedSlash = ph.includes(' / ') || ph.includes(' /');
    if (hasSpacedSlash) {
      return clean.replace(/\s*\/\s*/, ' / ');
    }
    return clean.replace(/\s*\/\s*/, '/');
  }

  function getAllPageInputs(focusedInput) {
    const parentContainer = focusedInput.closest('form, div[class*="payment"], div[class*="checkout"], div[class*="card"], fieldset') || document;
    const inputs = Array.from(parentContainer.querySelectorAll('input'));
    if (inputs.length < 2 && parentContainer !== document) {
      return Array.from(document.querySelectorAll('input'));
    }
    return inputs;
  }

  function fillCardDetails(focusedInput, card, currentFieldType) {
    const cardNumFormatted = getCardNumberFormattedForInput(focusedInput, card.cardNumber);
    const expiryFormatted = getExpiryFormattedForInput(focusedInput, card.expiry);

    // Fill current focused field first
    if (currentFieldType === 'CARD_NUMBER') setInputValue(focusedInput, cardNumFormatted);
    if (currentFieldType === 'EXPIRY') setInputValue(focusedInput, expiryFormatted);
    if (currentFieldType === 'CVV') setInputValue(focusedInput, card.cvv);
    if (currentFieldType === 'CARD_HOLDER') setInputValue(focusedInput, card.cardHolder);

    // Also scan form or page to auto-fill sister fields simultaneously!
    const inputs = getAllPageInputs(focusedInput);
    inputs.forEach(inp => {
      if (inp === focusedInput) return;
      const t = classifyInput(inp);
      if (t === 'CARD_NUMBER' && card.cardNumber) {
        setInputValue(inp, getCardNumberFormattedForInput(inp, card.cardNumber));
      }
      if (t === 'EXPIRY' && card.expiry) {
        setInputValue(inp, getExpiryFormattedForInput(inp, card.expiry));
      }
      if (t === 'CVV' && card.cvv) {
        setInputValue(inp, card.cvv);
      }
      if (t === 'CARD_HOLDER' && card.cardHolder) {
        setInputValue(inp, card.cardHolder);
      }
    });
  }

  function fillBankAccountDetails(focusedInput, account, bank, currentFieldType) {
    if (currentFieldType === 'ACCOUNT_NUMBER') setInputValue(focusedInput, account.accountNumber);
    if (currentFieldType === 'IFSC') setInputValue(focusedInput, account.ifscCode);

    // Scan sister fields
    const inputs = getAllPageInputs(focusedInput);
    inputs.forEach(inp => {
      if (inp === focusedInput) return;
      const t = classifyInput(inp);
      if (t === 'ACCOUNT_NUMBER' && account.accountNumber) setInputValue(inp, account.accountNumber);
      if (t === 'IFSC' && account.ifscCode) setInputValue(inp, account.ifscCode);
    });
  }

  function fillCredentials(focusedInput, bank, currentFieldType) {
    if (currentFieldType === 'USER_ID') setInputValue(focusedInput, bank.userId);
    if (currentFieldType === 'PASSWORD') setInputValue(focusedInput, bank.loginPassword || bank.profilePassword || bank.mpin);

    const inputs = getAllPageInputs(focusedInput);
    inputs.forEach(inp => {
      if (inp === focusedInput) return;
      const t = classifyInput(inp);
      if (t === 'USER_ID' && bank.userId) setInputValue(inp, bank.userId);
      if (t === 'PASSWORD' && (bank.loginPassword || bank.profilePassword)) {
        setInputValue(inp, bank.loginPassword || bank.profilePassword);
      }
    });
  }

  function fillPasswordCredentials(focusedInput, pwd, currentFieldType) {
    if (currentFieldType === 'USER_ID') setInputValue(focusedInput, pwd.username);
    if (currentFieldType === 'PASSWORD') setInputValue(focusedInput, pwd.password);

    // Auto-fill sister input in form or page
    const inputs = getAllPageInputs(focusedInput);
    inputs.forEach(inp => {
      if (inp === focusedInput) return;
      const t = classifyInput(inp);
      if (t === 'USER_ID' && pwd.username) setInputValue(inp, pwd.username);
      if (t === 'PASSWORD' && pwd.password) setInputValue(inp, pwd.password);
    });
  }

  function escapeHtml(str) {
    if (!str) return '';
    return str.replace(/[&<>'"]/g, tag => ({
      '&': '&amp;',
      '<': '&lt;',
      '>': '&gt;',
      "'": '&#39;',
      '"': '&quot;'
    }[tag] || tag));
  }

  // ── Automatic "Save Password" Prompt ──
  let activePromptCard = null;

  function removeSavePrompt() {
    if (activePromptCard) {
      activePromptCard.remove();
      activePromptCard = null;
    }
  }

  function showSavePasswordPrompt(domain, username, password) {
    removeSavePrompt();

    const card = document.createElement('div');
    card.className = 'cv-save-prompt-card';
    card.innerHTML = `
      <div class="cv-prompt-header">
        <div class="cv-prompt-title">
          <span>🛡️</span>
          <span>TetherPass</span>
        </div>
        <button class="cv-prompt-close" title="Dismiss">✕</button>
      </div>
      <div class="cv-prompt-body">
        <div>Save credentials for <strong>${escapeHtml(domain)}</strong> to your encrypted vault?</div>
        <div class="cv-prompt-user-badge">
          <span>👤</span>
          <span>${escapeHtml(username || 'Account')}</span>
        </div>
      </div>
      <div class="cv-prompt-actions">
        <button class="cv-btn-dismiss">Ignore</button>
        <button class="cv-btn-save">Save to Vault</button>
      </div>
    `;

    card.querySelector('.cv-prompt-close').addEventListener('click', removeSavePrompt);
    card.querySelector('.cv-btn-dismiss').addEventListener('click', removeSavePrompt);

    card.querySelector('.cv-btn-save').addEventListener('click', () => {
      chrome.runtime.sendMessage({
        action: 'SAVE_NEW_PASSWORD',
        payload: {
          website: domain,
          username: username || '',
          password: password,
          nickname: domain
        }
      }, (res) => {
        if (res && res.success) {
          card.querySelector('.cv-prompt-body').innerHTML = `
            <div style="color: #10B981; font-weight: 700;">✅ Saved to TetherPass!</div>
          `;
          setTimeout(removeSavePrompt, 2000);
        } else {
          removeSavePrompt();
        }
      });
    });

    document.body.appendChild(card);
    activePromptCard = card;

    setTimeout(() => {
      if (activePromptCard === card) removeSavePrompt();
    }, 15000);
  }

  // ── Listener for Direct Autofill from Extension Popup ──
  if (typeof chrome !== 'undefined' && chrome.runtime?.onMessage) {
    chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
      if (message && message.action === 'VAULT_STATUS_CHANGED') {
        if (!message.isAuthorized) removeDropdown();
      }

      if (message && message.action === 'FILL_CARD_NOW' && message.card) {
        const count = fillAllCardInputsOnPage(message.card);
        showFillToast(count > 0 ? 'Card details autofilled!' : 'No payment inputs found on page', count > 0);
        sendResponse({ success: true, count });
      }
    });
  }

  function fillAllCardInputsOnPage(card) {
    const inputs = Array.from(document.querySelectorAll('input')).filter(inp => {
      return inp.type !== 'hidden' && inp.type !== 'submit' && inp.type !== 'button';
    });

    let filledCount = 0;
    inputs.forEach(inp => {
      const type = classifyInput(inp);
      if (type === 'CARD_NUMBER' && card.cardNumber) {
        const formatted = getCardNumberFormattedForInput(inp, card.cardNumber);
        setInputValue(inp, formatted);
        filledCount++;
      } else if (type === 'EXPIRY' && card.expiry) {
        const formatted = getExpiryFormattedForInput(inp, card.expiry);
        setInputValue(inp, formatted);
        filledCount++;
      } else if (type === 'CVV' && card.cvv) {
        setInputValue(inp, card.cvv);
        filledCount++;
      } else if (type === 'CARD_HOLDER' && card.cardHolder) {
        setInputValue(inp, card.cardHolder);
        filledCount++;
      }
    });

    return filledCount;
  }

  function showFillToast(text, isSuccess = true) {
    // If this frame found 0 inputs, but it is top frame with iframes,
    // suppress negative toast since an iframe contains the payment gateway!
    if (!isSuccess && window.self === window.top && document.querySelectorAll('iframe').length > 0) {
      return;
    }

    const toast = document.createElement('div');
    toast.style.cssText = `
      position: fixed;
      top: 20px;
      left: 50%;
      transform: translateX(-50%);
      background: #0F172A;
      color: #FFFFFF;
      padding: 10px 20px;
      border-radius: 24px;
      font-size: 13px;
      font-weight: 700;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      box-shadow: 0 10px 25px -5px rgba(0, 0, 0, 0.3);
      z-index: 2147483647;
      display: flex;
      align-items: center;
      gap: 8px;
      border: 1px solid rgba(255, 111, 0, 0.5);
      pointer-events: none;
      transition: opacity 0.3s ease;
    `;
    toast.innerHTML = `<span>🛡️</span><span>${escapeHtml(text)}</span>`;
    document.body.appendChild(toast);
    setTimeout(() => {
      toast.style.opacity = '0';
      setTimeout(() => toast.remove(), 300);
    }, 2200);
  }

  // Intercept form submissions to offer saving new credentials
  document.addEventListener('submit', (e) => {
    try {
      const form = e.target;
      if (!form || !form.querySelector) return;
      const pwdInput = form.querySelector('input[type="password"]');
      if (!pwdInput || !pwdInput.value || pwdInput.value.length < 3) return;

      // Find username / email
      let userInput = form.querySelector('input[type="email"], input[name*="user" i], input[name*="email" i], input[autocomplete*="username" i], input[autocomplete*="email" i]');
      if (!userInput) {
        const inputs = Array.from(form.querySelectorAll('input:not([type="hidden"]):not([type="submit"])'));
        const idx = inputs.indexOf(pwdInput);
        if (idx > 0) userInput = inputs[idx - 1];
      }

      const domain = window.location.hostname.replace(/^www\./, '');
      const userVal = userInput ? userInput.value.trim() : '';
      const pwdVal = pwdInput.value;

      showSavePasswordPrompt(domain, userVal, pwdVal);
    } catch (_) {}
  }, true);
})();
