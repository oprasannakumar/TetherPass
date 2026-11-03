/**
 * CardVault Content Script
 * Detects payment, bank account, and credential input fields and renders
 * floating inline autofill suggestion chips when authorized by mobile app.
 */

(function () {
  var activeDropdown = null;
  var activeInput = null;
  var selectedItemIndex = -1;
  var managedInput = null;
  var originalAutocomplete = null;

  function suppressBrowserAutofill(input) {
    if (!input) return;
    managedInput = input;
    if (input.getAttribute('autocomplete') !== 'off' && (!input.dataset || !input.dataset.tpOrigAc)) {
      originalAutocomplete = input.getAttribute('autocomplete');
      if (input.dataset) {
        input.dataset.tpOrigAc = originalAutocomplete !== null ? originalAutocomplete : '__none__';
      }
    }
    input.setAttribute('autocomplete', 'off');
  }

  function restoreBrowserAutofill() {
    if (managedInput) {
      const orig = managedInput.dataset?.tpOrigAc;
      if (orig && orig !== '__none__') {
        managedInput.setAttribute('autocomplete', orig);
      } else if (originalAutocomplete !== null) {
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
    const origAc = input.dataset?.tpOrigAc;
    const rawAc = input.getAttribute('autocomplete') || '';
    const autocomplete = ((origAc && origAc !== '__none__') ? origAc : rawAc).toLowerCase();
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

    // 3. Expiry Date (Full, Month, Year)
    const isExpiryRelated = !raw.includes('dob') && !raw.includes('birth') && !autocomplete.includes('bday') && (
      autocomplete.includes('cc-exp') || norm.includes('expiry') || norm.includes('expire') ||
      norm.includes('expiration') || norm.includes('exp date') || norm.includes('expiry date') ||
      norm.includes('valid thru') || norm.includes('valid till') || norm.includes('valid upto') ||
      raw.includes('mm/yy') || raw.includes('mm / yy') || raw.includes('mm-yy') || raw.includes('mmyy') ||
      raw.includes('ccexp') || raw.includes('card_exp') || ph === 'mm' || ph === 'yy' || ph === 'yyyy' ||
      ph === 'mm/yy' || ph === 'mm / yy'
    );

    if (isExpiryRelated) {
      const isMonth = autocomplete.includes('cc-exp-month') || raw.includes('month') || raw.includes('exp_m') ||
        raw.includes('ccexpm') || ph === 'mm' || (input.maxLength === 2 && (norm.includes('month') || ph.includes('m')));
      const isYear = autocomplete.includes('cc-exp-year') || raw.includes('year') || raw.includes('exp_y') ||
        raw.includes('ccexpy') || ph === 'yy' || ph === 'yyyy' || (input.maxLength <= 4 && (norm.includes('year') || ph.includes('y')));

      if (isMonth && !isYear) return 'EXPIRY_MONTH';
      if (isYear && !isMonth) return 'EXPIRY_YEAR';
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
    const val = typeof input.value === 'string' ? input.value.trim() : '';
    if (val.length === 0) {
      if (input.dataset) {
        delete input.dataset.tpFilled;
      }
      return false;
    }
    return true;
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
        if (!response) return;
        const isStillTarget = (target === activeInput) ||
                              (document.activeElement === target) ||
                              (target.matches && target.matches(':focus'));
        if (!isStillTarget) return;
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
    clearInputFilledState(target);
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
      clearInputFilledState(target);
      if (isInputFilled(target)) {
        removeDropdown();
      } else {
        handleInputInteraction(target);
      }
    }
  });

  // Handle typing, clearing, cut, change, and pasting in fields
  ['input', 'change', 'cut', 'paste'].forEach(evtName => {
    document.addEventListener(evtName, (e) => {
      const target = e.target;
      if (!target || target.tagName !== 'INPUT') return;

      clearInputFilledState(target);

      // If text box now contains text/credentials, dismiss suggestions immediately
      if (isInputFilled(target)) {
        removeDropdown();
        return;
      }

      // If text box is empty, and user is focused on it, re-trigger suggestions immediately!
      const isFocused = (document.activeElement === target) || (target.matches && target.matches(':focus'));
      if (isFocused && (!target.value || target.value.trim().length === 0)) {
        handleInputInteraction(target);
      }
    });
  });

  // Listen for Backspace/Delete clearing
  document.addEventListener('keyup', (e) => {
    const target = e.target;
    if (!target || target.tagName !== 'INPUT') return;

    clearInputFilledState(target);

    if (isInputFilled(target)) {
      removeDropdown();
      return;
    }

    const isFocused = (document.activeElement === target) || (target.matches && target.matches(':focus'));
    if (isFocused && (!target.value || target.value.trim().length === 0)) {
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
    let brandLogoHtml;
    try {
      const logoUrl = chrome.runtime?.getURL ? chrome.runtime.getURL('icons/icon48.png') : '';
      if (logoUrl) {
        brandLogoHtml = `<img src="${logoUrl}" class="cv-brand-icon" alt="TetherPass" onerror="this.outerHTML='<span class=\\'cv-logo-badge\\'>TP</span>'" />`;
      } else {
        brandLogoHtml = `<span class="cv-logo-badge">TP</span>`;
      }
    } catch (_) {
      brandLogoHtml = `<span class="cv-logo-badge">TP</span>`;
    }

    header.innerHTML = `
      <div class="cv-header-left">
        ${brandLogoHtml}
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
      if (['CARD_NUMBER', 'EXPIRY', 'EXPIRY_MONTH', 'EXPIRY_YEAR', 'CVV', 'CARD_HOLDER'].includes(fieldType) && data.cards && data.cards.length > 0) {
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

  function parseCardExpiry(expiryStr) {
    if (!expiryStr) return null;
    const clean = String(expiryStr).trim();
    let m = null;
    let y = null;

    if (clean.includes('/')) {
      const parts = clean.split('/');
      m = parts[0].trim();
      y = parts[1].trim();
    } else if (clean.includes('-')) {
      const parts = clean.split('-');
      m = parts[0].trim();
      y = parts[1].trim();
    } else if (/^\d{4}$/.test(clean)) {
      m = clean.slice(0, 2);
      y = clean.slice(2, 4);
    } else if (/^\d{6}$/.test(clean)) {
      m = clean.slice(0, 2);
      y = clean.slice(2, 6);
    }

    if (!m || !y) return null;

    let monthNum = parseInt(m, 10);
    let yearNum = parseInt(y, 10);
    if (isNaN(monthNum) || isNaN(yearNum)) return null;

    if (monthNum > 12 && yearNum <= 12) {
      const tmp = monthNum;
      monthNum = yearNum;
      yearNum = tmp;
    }
    if (monthNum < 1 || monthNum > 12) return null;

    const month2 = String(monthNum).padStart(2, '0');
    const month1 = String(monthNum);
    const shortMonths = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    const fullMonths = ['', 'January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    const monthShort = shortMonths[monthNum] || '';
    const monthFull = fullMonths[monthNum] || '';

    const year4 = yearNum < 100 ? String(2000 + yearNum) : String(yearNum);
    const year2 = year4.slice(-2);

    return {
      monthNum,
      month2,
      month1,
      monthShort,
      monthFull,
      year4,
      year2
    };
  }

  function setSelectValue(selectEl, candidateValues) {
    if (!selectEl || !selectEl.options || selectEl.options.length === 0) return false;

    const candidates = candidateValues.map(v => String(v).trim().toLowerCase()).filter(Boolean);
    if (candidates.length === 0) return false;

    let bestIndex = -1;
    let bestScore = 0;

    for (let i = 0; i < selectEl.options.length; i++) {
      const opt = selectEl.options[i];
      const optVal = (opt.value || '').trim().toLowerCase();
      const optText = (opt.text || opt.textContent || '').trim().toLowerCase();

      for (const cand of candidates) {
        // 1. Exact value match (score 100)
        if (optVal === cand) {
          bestIndex = i;
          bestScore = 100;
          break;
        }
        // 2. Exact text match (score 95)
        if (optText === cand && bestScore < 95) {
          bestIndex = i;
          bestScore = 95;
        }
        // 3. Numeric match (e.g. "5" matches "05")
        const candNum = parseInt(cand, 10);
        if (!isNaN(candNum) && (optVal === String(candNum) || optVal === String(candNum).padStart(2, '0')) && bestScore < 90) {
          bestIndex = i;
          bestScore = 90;
        }
        // 4. Token match in text (e.g. "05 - May", "May (05)", "2028")
        const tokens = optText.split(/[\s\-/,()]+/);
        if (tokens.includes(cand) && bestScore < 85) {
          bestIndex = i;
          bestScore = 85;
        }
        // 5. Text starts with or contains candidate
        if (optText.startsWith(cand) && bestScore < 80) {
          bestIndex = i;
          bestScore = 80;
        } else if (optText.includes(cand) && bestScore < 70) {
          bestIndex = i;
          bestScore = 70;
        }
      }
      if (bestScore === 100) break;
    }

    if (bestIndex >= 0) {
      selectEl.selectedIndex = bestIndex;
      selectEl.value = selectEl.options[bestIndex].value;

      try {
        const tracker = selectEl._valueTracker;
        if (tracker) tracker.setValue(selectEl.value);
      } catch (_) {}

      try {
        selectEl.dispatchEvent(new Event('focus', { bubbles: true }));
        selectEl.dispatchEvent(new Event('input', { bubbles: true }));
        selectEl.dispatchEvent(new Event('change', { bubbles: true }));
        selectEl.dispatchEvent(new Event('blur', { bubbles: true }));
      } catch (_) {}

      // Synchronize custom dropdown UI display (Amazon a-dropdown, select2, bootstrap, etc.)
      try {
        const parentDropdown = selectEl.closest('.a-dropdown-container, .dropdown, .custom-select, [class*="select"]');
        if (parentDropdown) {
          const promptSpan = parentDropdown.querySelector('.a-dropdown-prompt, [class*="prompt"], [class*="selected-text"], .select2-selection__rendered');
          if (promptSpan) {
            promptSpan.textContent = selectEl.options[bestIndex].text || selectEl.options[bestIndex].textContent || selectEl.options[bestIndex].value;
          }
        }
      } catch (_) {}

      return true;
    }
    return false;
  }

  function fillCardExpirySelects(container, cardExpiry) {
    const parsed = parseCardExpiry(cardExpiry);
    if (!parsed) return 0;

    let selects = Array.from((container || document).querySelectorAll('select'));
    if (selects.length === 0 && container && container !== document) {
      selects = Array.from(document.querySelectorAll('select'));
    }
    if (selects.length === 0) return 0;

    let filledCount = 0;
    let monthSelect = null;
    let yearSelect = null;
    let combinedSelect = null;

    selects.forEach(sel => {
      if (sel.disabled) return;

      const raw = getElementTextContext(sel);
      const norm = raw.replace(/[-_./]/g, ' ');
      const autocomplete = (sel.getAttribute('autocomplete') || '').toLowerCase();
      const name = (sel.name || '').toLowerCase();
      const id = (sel.id || '').toLowerCase();

      const options = Array.from(sel.options || []);
      const optTexts = options.map(o => (o.text || o.textContent || '').trim().toLowerCase());
      const optVals = options.map(o => (o.value || '').trim().toLowerCase());
      const allStrings = optTexts.concat(optVals).filter(Boolean);

      const monthMatches = allStrings.filter(s => /^(0?[1-9]|1[0-2])$/.test(s) || ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'].includes(s.slice(0, 3)));
      const hasStrongMonthOptions = monthMatches.length >= 6;

      const yearMatches = allStrings.filter(s => /^(20[2-4][0-9]|[2-4][0-9])$/.test(s));
      const hasStrongYearOptions = yearMatches.length >= 3;

      const hasCombinedOptions = allStrings.some(s => /^(0?[1-9]|1[0-2])\s*[\/\-]\s*(20[2-4][0-9]|[2-4][0-9])$/.test(s));

      const isMonthByAttr = autocomplete.includes('cc-exp-month') ||
                            name.includes('expmonth') || name.includes('exp-month') || name.includes('exp_month') ||
                            id.includes('expmonth') || id.includes('exp-month') || id.includes('exp_month') ||
                            name.includes('expirationmonth') || id.includes('expirationmonth') ||
                            name.includes('ccexpmonth') || id.includes('ccexpmonth') ||
                            name.includes('ppw-expirationdate_month') || id.includes('ppw-expirationdate_month') ||
                            ((name.includes('month') || id.includes('month') || norm.includes('month')) && (norm.includes('card') || norm.includes('exp') || norm.includes('valid')));

      const isYearByAttr = autocomplete.includes('cc-exp-year') ||
                           name.includes('expyear') || name.includes('exp-year') || name.includes('exp_year') ||
                           id.includes('expyear') || id.includes('exp-year') || id.includes('exp_year') ||
                           name.includes('expirationyear') || id.includes('expirationyear') ||
                           name.includes('ccexpyear') || id.includes('ccexpyear') ||
                           name.includes('ppw-expirationdate_year') || id.includes('ppw-expirationdate_year') ||
                           ((name.includes('year') || id.includes('year') || norm.includes('year')) && (norm.includes('card') || norm.includes('exp') || norm.includes('valid')));

      if (isMonthByAttr || (!isYearByAttr && hasStrongMonthOptions && !hasStrongYearOptions)) {
        if (!monthSelect) monthSelect = sel;
      } else if (isYearByAttr || (!isMonthByAttr && hasStrongYearOptions && !hasStrongMonthOptions)) {
        if (!yearSelect) yearSelect = sel;
      } else if (hasCombinedOptions || autocomplete === 'cc-exp' || norm.includes('expiry') || norm.includes('expiration')) {
        if (!combinedSelect) combinedSelect = sel;
      }
    });

    if (monthSelect) {
      const monthCandidates = [
        parsed.month2,
        parsed.month1,
        `${parsed.month2} - ${parsed.monthShort}`,
        `${parsed.month1} - ${parsed.monthShort}`,
        `${parsed.month2} - ${parsed.monthFull}`,
        `${parsed.month1} - ${parsed.monthFull}`,
        `${parsed.month2}/${parsed.monthShort}`,
        `${parsed.monthShort} (${parsed.month2})`,
        `${parsed.month2} (${parsed.monthShort})`,
        parsed.monthShort,
        parsed.monthFull
      ];
      if (setSelectValue(monthSelect, monthCandidates)) filledCount++;
    }

    if (yearSelect) {
      const yearCandidates = [
        parsed.year4,
        parsed.year2,
        `'${parsed.year2}`
      ];
      if (setSelectValue(yearSelect, yearCandidates)) filledCount++;
    }

    if (!monthSelect && !yearSelect && combinedSelect) {
      const combinedCandidates = [
        `${parsed.month2}/${parsed.year2}`,
        `${parsed.month2} / ${parsed.year2}`,
        `${parsed.month2}/${parsed.year4}`,
        `${parsed.month2} / ${parsed.year4}`,
        `${parsed.monthShort} ${parsed.year4}`,
        `${parsed.monthFull} ${parsed.year4}`
      ];
      if (setSelectValue(combinedSelect, combinedCandidates)) filledCount++;
    }

    return filledCount;
  }

  function fillCardDetails(focusedInput, card, currentFieldType) {
    const parsedExpiry = parseCardExpiry(card.expiry);
    const cardNumFormatted = getCardNumberFormattedForInput(focusedInput, card.cardNumber);
    const expiryFormatted = getExpiryFormattedForInput(focusedInput, card.expiry);

    // Fill current focused field first
    if (currentFieldType === 'CARD_NUMBER') setInputValue(focusedInput, cardNumFormatted);
    if (currentFieldType === 'EXPIRY') setInputValue(focusedInput, expiryFormatted);
    if (currentFieldType === 'EXPIRY_MONTH') setInputValue(focusedInput, parsedExpiry ? parsedExpiry.month2 : '');
    if (currentFieldType === 'EXPIRY_YEAR') {
      const yr = parsedExpiry ? (focusedInput.maxLength === 4 ? parsedExpiry.year4 : parsedExpiry.year2) : '';
      setInputValue(focusedInput, yr);
    }
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
      if (t === 'EXPIRY_MONTH' && parsedExpiry) {
        setInputValue(inp, parsedExpiry.month2);
      }
      if (t === 'EXPIRY_YEAR' && parsedExpiry) {
        setInputValue(inp, inp.maxLength === 4 ? parsedExpiry.year4 : parsedExpiry.year2);
      }
      if (t === 'CVV' && card.cvv) {
        setInputValue(inp, card.cvv);
      }
      if (t === 'CARD_HOLDER' && card.cardHolder) {
        setInputValue(inp, card.cardHolder);
      }
    });

    // Also auto-fill any <select> dropdowns for Expiry Month & Year!
    const parentContainer = focusedInput ? (focusedInput.closest('form, div[class*="payment"], div[class*="checkout"], div[class*="card"], fieldset') || document) : document;
    fillCardExpirySelects(parentContainer, card.expiry);
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

    const parsedExpiry = parseCardExpiry(card.expiry);
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
      } else if (type === 'EXPIRY_MONTH' && parsedExpiry) {
        setInputValue(inp, parsedExpiry.month2);
        filledCount++;
      } else if (type === 'EXPIRY_YEAR' && parsedExpiry) {
        setInputValue(inp, inp.maxLength === 4 ? parsedExpiry.year4 : parsedExpiry.year2);
        filledCount++;
      } else if (type === 'CVV' && card.cvv) {
        setInputValue(inp, card.cvv);
        filledCount++;
      } else if (type === 'CARD_HOLDER' && card.cardHolder) {
        setInputValue(inp, card.cardHolder);
        filledCount++;
      }
    });

    // Auto-fill <select> dropdowns across page / forms
    const selectCount = fillCardExpirySelects(document, card.expiry);
    filledCount += selectCount;

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
