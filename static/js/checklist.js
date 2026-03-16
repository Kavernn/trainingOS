/**
 * checklist.js — "Check avant de partir"
 * localStorage only, daily reset, gym bag sub-items.
 */
(function () {
  const STORAGE_KEY = 'cl_state_v1';
  const DATE_KEY    = 'cl_date_v1';

  const ITEMS = [
    { id: 'telephone',  label: 'Téléphone' },
    { id: 'portefeuille', label: 'Portefeuille' },
    { id: 'cles',       label: 'Clés' },
    { id: 'vape',       label: 'Vape' },
    { id: 'montre',     label: 'Montre' },
    { id: 'gym',        label: 'Sac de gym', gym: true },
  ];

  const GYM_SUBS = [
    { id: 'gym_bas',      label: 'Bas' },
    { id: 'gym_chandail', label: 'Chandail' },
    { id: 'gym_shorts',   label: 'Shorts' },
    { id: 'gym_gourde',   label: 'Gourde' },
    { id: 'gym_serv_d',   label: 'Serviette douche' },
    { id: 'gym_serv_g',   label: 'Serviette gym' },
    { id: 'gym_savon',    label: 'Savon' },
    { id: 'gym_goug',     label: 'Gougounes' },
  ];

  // ── State ───────────────────────────────────────────────────────────────

  function todayStr() {
    return new Date().toISOString().slice(0, 10);
  }

  function loadState() {
    const stored = localStorage.getItem(DATE_KEY);
    if (stored !== todayStr()) {
      localStorage.removeItem(STORAGE_KEY);
      localStorage.setItem(DATE_KEY, todayStr());
    }
    try {
      return JSON.parse(localStorage.getItem(STORAGE_KEY) || '{}');
    } catch (_) {
      return {};
    }
  }

  function saveState(state) {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(state));
  }

  // ── Render ──────────────────────────────────────────────────────────────

  function render() {
    const card = document.getElementById('checklist-card');
    if (!card) return;

    // If already hidden today → keep hidden
    const stored = localStorage.getItem(DATE_KEY);
    const hidden = localStorage.getItem('cl_hidden_date');
    if (hidden === todayStr()) {
      card.style.display = 'none';
      return;
    }
    if (stored !== todayStr()) {
      // new day: clear hidden flag
      localStorage.removeItem('cl_hidden_date');
    }

    const state = loadState();
    const list  = document.getElementById('cl-list');
    list.innerHTML = '';

    let gymExpanded = state['gym_expanded'] === true;

    ITEMS.forEach(item => {
      const checked = !!state[item.id];
      const row = document.createElement('div');
      row.className = 'cl-item' + (checked ? ' checked' : '');
      row.dataset.id = item.id;

      row.innerHTML = `
        <div class="cl-checkbox"></div>
        <span class="cl-label">${item.label}</span>
        ${item.gym ? `<span class="cl-expand-btn${gymExpanded ? ' open' : ''}">▼</span>` : ''}
      `;

      if (item.gym) {
        // Expand toggle — only the chevron toggles expand, tap on row toggles check
        row.querySelector('.cl-expand-btn').addEventListener('click', e => {
          e.stopPropagation();
          gymExpanded = !gymExpanded;
          const s = loadState();
          s['gym_expanded'] = gymExpanded;
          saveState(s);
          document.getElementById('sub-gym').classList.toggle('open', gymExpanded);
          e.currentTarget.classList.toggle('open', gymExpanded);
        });
      }

      row.addEventListener('click', () => toggle(item.id));
      list.appendChild(row);

      // Gym sub-items block
      if (item.gym) {
        const sub = document.createElement('div');
        sub.id = 'sub-gym';
        if (gymExpanded) sub.classList.add('open');

        GYM_SUBS.forEach(s => {
          const sc = !!state[s.id];
          const sr = document.createElement('div');
          sr.className = 'cl-subitem' + (sc ? ' checked' : '');
          sr.dataset.id = s.id;
          sr.innerHTML = `<div class="cl-checkbox"></div><span class="cl-label">${s.label}</span>`;
          sr.addEventListener('click', () => toggleSub(s.id));
          sub.appendChild(sr);
        });

        list.appendChild(sub);
      }
    });

    checkCompletion(state);
  }

  // ── Toggle ──────────────────────────────────────────────────────────────

  function toggle(id) {
    const state = loadState();
    state[id] = !state[id];
    saveState(state);
    updateItem(id, state[id]);
    checkCompletion(state);
    if (window.haptic) haptic('light');
  }

  function toggleSub(id) {
    const state = loadState();
    state[id] = !state[id];
    saveState(state);
    updateSubItem(id, state[id]);

    // Auto-check gym parent if all subs checked
    const allSubs = GYM_SUBS.every(s => !!state[s.id]);
    state['gym'] = allSubs;
    saveState(state);
    updateItem('gym', allSubs);
    checkCompletion(state);
    if (window.haptic) haptic('light');
  }

  function updateItem(id, checked) {
    const row = document.querySelector(`.cl-item[data-id="${id}"]`);
    if (row) row.classList.toggle('checked', checked);
  }

  function updateSubItem(id, checked) {
    const row = document.querySelector(`.cl-subitem[data-id="${id}"]`);
    if (row) row.classList.toggle('checked', checked);
  }

  // ── Completion ──────────────────────────────────────────────────────────

  function checkCompletion(state) {
    const allMain = ITEMS.every(i => !!state[i.id]);
    const allSubs = GYM_SUBS.every(s => !!state[s.id]);
    const done    = allMain && allSubs;

    const msg = document.getElementById('cl-complete-msg');
    if (!msg) return;

    if (done) {
      msg.style.display = 'block';
      if (window.haptic) haptic('success');
      setTimeout(() => {
        const card = document.getElementById('checklist-card');
        card.classList.add('hiding');
        setTimeout(() => {
          card.style.display = 'none';
          localStorage.setItem('cl_hidden_date', todayStr());
        }, 400);
      }, 2000);
    } else {
      msg.style.display = 'none';
    }
  }

  // ── Init ────────────────────────────────────────────────────────────────

  document.addEventListener('DOMContentLoaded', render);
})();
