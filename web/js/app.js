/* ---------------------------------------------------------------------------
   loe_bank — NUI mantığı ("Los Santos Bank" paneli)
   Sol menü görünüm değiştirir: Hesap Özeti / Para Yatır / Para Çek / Havale.
   Tüm para hareketi server'da doğrulanır; her yanıt güncel bakiye + son
   işlemleri geri döndürür, panel ona göre tazelenir.
--------------------------------------------------------------------------- */
(function () {
    'use strict';

    const RES = (typeof GetParentResourceName === 'function')
        ? GetParentResourceName() : 'loe_bank';

    const $ = (id) => document.getElementById(id);

    const app        = $('app');
    const menuEl      = $('menu');
    const mainEl      = $('main');
    const brandName   = $('brand-name');
    const brandTag    = $('brand-tagline');
    const custName    = $('cust-name');
    const custAcct    = $('cust-acct');
    const acBankName  = $('ac-bankname');
    const acBalance   = $('ac-balance');
    const acAccount   = $('ac-account');
    const accountCard = $('account-card');
    const quickEl     = $('quick');
    const statsEl     = $('stats');
    const txPanel     = $('tx-panel');
    const txListEl    = $('tx-list');
    const txEmptyEl   = $('tx-empty');
    const toastEl     = $('toast');
    const eyeToggle   = $('eye-toggle');
    const eyeLabel    = $('eye-label');
    const closeBtn    = $('close-btn');
    const logoutBtn   = $('btn-logout');
    const bellBtn     = $('btn-bell');
    const txRefreshBtn= $('tx-refresh');

    const state = {
        bank: {},           // { name, tagline }
        limits: {},         // { minAmount, maxDeposit, maxWithdraw, maxTransfer, transferFee, transferFeeMin, transferFeeMax }
        player: { name: 'Müşteri', account: null, cash: 0, bank: 0 },
        tx: [],
        donationTotal: 0,
        view: 'overview',
        balHidden: false,
    };

    /* --------------------------------------------------------------- icons */
    const I = {
        home:    '<path d="M3 11l9-8 9 8"/><path d="M5 10v10h14V10"/>',
        deposit: '<path d="M12 3v12"/><path d="M7 10l5 5 5-5"/><path d="M5 21h14"/>',
        withdraw:'<path d="M12 21V9"/><path d="M7 14l5-5 5 5"/><path d="M5 3h14"/>',
        send:    '<path d="M22 2 11 13"/><path d="M22 2 15 22l-4-9-9-4Z"/>',
        doc:     '<path d="M14 3H6a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V9z"/><path d="M14 3v6h6"/>',
        chart:   '<path d="M3 3v18h18"/><path d="M7 15l4-4 3 3 5-6"/>',
        stack:   '<path d="M12 2 2 7l10 5 10-5-10-5Z"/><path d="M2 12l10 5 10-5"/><path d="M2 17l10 5 10-5"/>',
        clock:   '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
        cash:    '<rect x="2" y="6" width="20" height="12" rx="2"/><circle cx="12" cy="12" r="2.5"/>',
        bank:    '<path d="M3 10 12 4l9 6"/><path d="M4 10v9M20 10v9M9 10v9M15 10v9"/><path d="M2 20h20"/>',
        wallet:  '<path d="M3 7a2 2 0 0 1 2-2h13a1 1 0 0 1 1 1v3"/><path d="M3 7v10a2 2 0 0 0 2 2h15a1 1 0 0 0 1-1v-3"/><path d="M16 12h5v4h-5a2 2 0 0 1 0-4Z"/>',
        activity:'<path d="M22 12h-4l-3 9L9 3l-3 9H2"/>',
        txin:    '<path d="M17 7 7 17"/><path d="M17 17H7V7"/>',
        txout:   '<path d="M7 17 17 7"/><path d="M7 7h10v10"/>',
        heart:   '<path d="M19 14c1.5-1.6 3-3.5 3-5.6A4.4 4.4 0 0 0 12 6 4.4 4.4 0 0 0 2 8.4c0 2.1 1.5 4 3 5.6l7 7Z"/>',
    };
    function svg(inner, cls) { return `<svg class="${cls || ''}" viewBox="0 0 24 24" aria-hidden="true">${inner}</svg>`; }

    const MENU = [
        { id: 'overview', label: 'Hesap Özeti',  icon: I.home },
        { id: 'deposit',  label: 'Para Yatır',   icon: I.deposit },
        { id: 'withdraw', label: 'Para Çek',     icon: I.withdraw },
        { id: 'transfer', label: 'Havale / EFT', icon: I.send },
        { id: 'donate',   label: 'Bağış',        icon: I.heart },
        { id: 'fines',    label: 'Cezalar',      icon: I.doc },
        { id: 'bills',    label: 'Faturalar',    icon: I.doc,   soon: true },
        { id: 'invest',   label: 'Yatırımlar',   icon: I.chart, soon: true },
        { id: 'loan',     label: 'Kredi',        icon: I.stack, soon: true },
    ];

    const QUICK = [
        { label: 'Para Yatır',   icon: I.deposit,  go: 'deposit' },
        { label: 'Para Çek',     icon: I.withdraw, go: 'withdraw' },
        { label: 'Havale / EFT', icon: I.send,     go: 'transfer' },
        { label: 'Son İşlemler', icon: I.clock,    flash: true },
    ];

    const TXMETA = {
        deposit:      { icon: I.deposit,  sign: +1, color: '#34e07f' },
        withdraw:     { icon: I.withdraw, sign: -1, color: '#ffb648' },
        transfer_in:  { icon: I.txin,     sign: +1, color: '#34e07f' },
        transfer_out: { icon: I.txout,    sign: -1, color: '#ff2e97' },
        donation:     { icon: I.heart,    sign: -1, color: '#ff2e97' },
    };

    /* ------------------------------------------------------------- helpers */
    function grp(n) { return Math.round(Math.abs(n || 0)).toLocaleString('tr-TR'); }
    function money(n) { return '$' + grp(n); }
    function moneySpaced(n) { return '$ ' + grp(n); }
    function moneySigned(n) {
        const r = Math.round(n || 0);
        return (r < 0 ? '−' : '+') + '$' + grp(r);
    }
    function post(endpoint, data) {
        return fetch(`https://${RES}/${endpoint}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(data || {}),
        }).then(r => r.json()).catch(() => null);
    }
    function fmtBankName(name) {
        const parts = String(name || 'BANK').trim().split(/\s+/);
        if (parts.length === 1) return `<span>${parts[0]}</span>`;
        const last = parts.pop();
        return `${parts.join(' ')} <span>${last}</span>`;
    }
    const MONTHS = ['Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz', 'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara'];
    const DAYS   = ['Paz', 'Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt'];
    function pad2(n) { return String(n).padStart(2, '0'); }
    function fmtWhen(ts) {
        if (!ts) return '';
        const d = new Date(ts * 1000);
        const now = new Date();
        const hm = pad2(d.getHours()) + ':' + pad2(d.getMinutes());
        if (d.toDateString() === now.toDateString()) return 'Bugün ' + hm;
        const y = new Date(now); y.setDate(now.getDate() - 1);
        if (d.toDateString() === y.toDateString()) return 'Dün ' + hm;
        return d.getDate() + ' ' + MONTHS[d.getMonth()];
    }

    function feeFor(amount) {
        const l = state.limits || {};
        const rate = Number(l.transferFee) || 0;
        if (rate <= 0 || amount <= 0) return 0;
        let fee = Math.floor(amount * rate);
        if (l.transferFeeMin > 0 && fee < l.transferFeeMin) fee = l.transferFeeMin;
        if (l.transferFeeMax > 0 && fee > l.transferFeeMax) fee = l.transferFeeMax;
        return fee;
    }

    /* --------------------------------------------------------- amount input */
    function digitsOnly(s) { return String(s || '').replace(/[^\d]/g, '').slice(0, 12); }
    function getAmt(el) { const d = digitsOnly(el.value); return d ? parseInt(d, 10) : 0; }
    function attachAmount(el, onChange) {
        el.addEventListener('input', () => {
            const d = digitsOnly(el.value);
            el.value = d ? parseInt(d, 10).toLocaleString('tr-TR') : '';
            onChange && onChange();
        });
    }
    function setAmt(el, val, onChange) {
        el.value = val > 0 ? Math.floor(val).toLocaleString('tr-TR') : '';
        onChange && onChange();
    }

    /* ---------------------------------------------------------------- menu */
    function renderMenu() {
        menuEl.innerHTML = '';
        MENU.forEach(m => {
            const row = document.createElement('div');
            row.className = 'nav-row' + (m.soon ? ' soon' : '') + (m.id === state.view ? ' active' : '');
            row.innerHTML =
                `<span class="ni">${svg(m.icon)}</span>` +
                `<span class="nl">${m.label}</span>` +
                (m.soon ? '<span class="nb">YAKINDA</span>' : '');
            if (!m.soon) row.addEventListener('click', () => setView(m.id));
            menuEl.appendChild(row);
        });
    }

    const VIEWS = ['overview', 'deposit', 'withdraw', 'transfer', 'donate', 'fines'];
    function setView(id) {
        if (!MENU.some(m => m.id === id && !m.soon)) return;
        state.view = id;
        VIEWS.forEach(v => { $('view-' + v).classList.toggle('hidden', v !== id); });
        renderMenu();
        renderForms();
        mainEl.scrollTop = 0;
        if (id === 'fines') loadFines();
        const focusMap = { deposit: 'dep-amount', withdraw: 'wd-amount', transfer: 'tr-account', donate: 'don-amount' };
        if (focusMap[id]) { const f = $(focusMap[id]); if (f) setTimeout(() => f.focus(), 30); }
    }

    /* ------------------------------------------------------------- header */
    function renderHeader() {
        brandName.innerHTML = fmtBankName(state.bank.name || 'LOS SANTOS BANK');
        brandTag.textContent = state.bank.tagline || '';
        custName.textContent = state.player.name || 'Müşteri';
        custAcct.textContent = 'Hesap No: ' + (state.player.account || '—');
    }

    /* ----------------------------------------------------------- overview */
    function renderOverview() {
        acBankName.innerHTML = fmtBankName(state.bank.name || 'LOS SANTOS BANK');
        acBalance.textContent = moneySpaced(state.player.bank);
        acAccount.textContent = state.player.account || '—';

        quickEl.innerHTML = '';
        QUICK.forEach(q => {
            const t = document.createElement('div');
            t.className = 'q-tile';
            t.innerHTML = `<span class="qi">${svg(q.icon)}</span><span>${q.label}</span>`;
            t.addEventListener('click', () => { if (q.flash) flashTx(); else setView(q.go); });
            quickEl.appendChild(t);
        });

        const cash = state.player.cash || 0;
        const bank = state.player.bank || 0;
        const cutoff = Date.now() / 1000 - 86400;
        let net24 = 0;
        state.tx.forEach(r => {
            if ((r.ts || 0) >= cutoff) {
                const m = TXMETA[r.type];
                if (m) net24 += m.sign * (Number(r.amount) || 0);
            }
        });

        const tiles = [
            { icon: I.cash,     label: 'Nakit',        value: money(cash) },
            { icon: I.bank,     label: 'Banka',        value: money(bank) },
            { icon: I.wallet,   label: 'Toplam Varlık', value: money(cash + bank) },
            { icon: I.activity, label: 'Son 24 Saat',  value: moneySigned(net24), tone: net24 === 0 ? '' : (net24 < 0 ? 'neg' : 'pos') },
        ];
        statsEl.innerHTML = tiles.map(t =>
            `<div class="stat ${t.tone || ''}">
                <span class="si">${svg(t.icon)}</span>
                <span class="sv"><small>${t.label}</small><b>${t.value}</b></span>
             </div>`
        ).join('');

        applyBalHidden();
    }

    /* -------------------------------------------------------------- forms */
    function setHint(el, kind, text) {
        el.className = 'op-hint' + (kind ? ' ' + kind : '');
        el.textContent = text || '';
    }

    function renderForms() {
        const cash = state.player.cash || 0;
        const bank = state.player.bank || 0;

        // deposit
        $('dep-from').textContent = money(cash);
        $('dep-to').textContent   = money(bank);
        const depAmt = getAmt($('dep-amount'));
        const depBad = depAmt > cash;
        $('dep-submit').disabled = depAmt <= 0 || depBad;
        if (depBad) setHint($('dep-hint'), 'err', 'Üzerinde bu kadar nakit yok.');
        else if ($('dep-hint').classList.contains('err')) setHint($('dep-hint'), '', '');

        // withdraw
        $('wd-from').textContent = money(bank);
        $('wd-to').textContent   = money(cash);
        const wdAmt = getAmt($('wd-amount'));
        const wdBad = wdAmt > bank;
        $('wd-submit').disabled = wdAmt <= 0 || wdBad;
        if (wdBad) setHint($('wd-hint'), 'err', 'Banka bakiyen bu kadar değil.');
        else if ($('wd-hint').classList.contains('err')) setHint($('wd-hint'), '', '');

        // transfer
        $('tr-from').textContent = money(bank);
        const acc = $('tr-account').value.trim().toUpperCase();
        $('tr-to').textContent = acc || '—';
        const accOk = /^[A-Z0-9]{4}$/.test(acc);
        const trAmt = getAmt($('tr-amount'));
        const fee = feeFor(trAmt);
        $('tr-fee').textContent = money(fee);
        const trBad = (trAmt + fee) > bank;
        $('tr-submit').disabled = trAmt <= 0 || !accOk || trBad;
        if (acc && !accOk) setHint($('tr-hint'), 'err', 'Hesap no 4 hane olmalı (harf + rakam).');
        else if (trBad) setHint($('tr-hint'), 'err', fee > 0
            ? `Tutar + ücret (${money(trAmt + fee)}) banka bakiyeni aşıyor.`
            : 'Banka bakiyen yetersiz.');
        else if ($('tr-hint').classList.contains('err')) setHint($('tr-hint'), '', '');

        // donate
        $('don-from').textContent  = money(bank);
        $('don-total').textContent = money(state.donationTotal || 0);
        const donAmt = getAmt($('don-amount'));
        const donBad = donAmt > bank;
        $('don-submit').disabled = donAmt <= 0 || donBad;
        if (donBad) setHint($('don-hint'), 'err', 'Banka bakiyen yetersiz.');
        else if ($('don-hint').classList.contains('err')) setHint($('don-hint'), '', '');
    }

    // Para Yatır / Çek / Bağış: bakiyenin yüzdesi. Havale: sabit tutarlar + Tümü.
    const AMT_ID = { dep: 'dep-amount', wd: 'wd-amount', tr: 'tr-amount', don: 'don-amount' };
    function chipEls(kind) { return $(AMT_ID[kind] || 'dep-amount'); }
    function chipBase(kind) {
        return kind === 'dep' ? (state.player.cash || 0) : (state.player.bank || 0);
    }
    function mkChip(label, fn, cls) {
        const b = document.createElement('button');
        b.type = 'button';
        b.className = 'chip-btn' + (cls ? ' ' + cls : '');
        b.textContent = label;
        b.addEventListener('click', fn);
        return b;
    }
    function buildChips() {
        document.querySelectorAll('.chips[data-chips]').forEach(box => {
            const kind = box.dataset.chips;
            box.innerHTML = '';
            if (kind === 'tr') {
                [100, 500, 1000, 5000, 10000].forEach(v => {
                    box.appendChild(mkChip(v.toLocaleString('tr-TR'), () => {
                        const el = chipEls(kind);
                        setAmt(el, getAmt(el) + v, renderForms);
                    }));
                });
                box.appendChild(mkChip('Tümü', () => {
                    const bank = state.player.bank || 0;
                    const rate = Number(state.limits.transferFee) || 0;
                    let amt = rate > 0 ? Math.floor(bank / (1 + rate)) : bank;
                    while (amt > 0 && amt + feeFor(amt) > bank) amt--;
                    setAmt(chipEls(kind), amt, renderForms);
                }, 'max'));
            } else {
                [25, 50, 75, 100].forEach(pct => {
                    box.appendChild(mkChip('%' + pct, () => {
                        setAmt(chipEls(kind), Math.floor(chipBase(kind) * pct / 100), renderForms);
                    }, pct === 100 ? 'max' : ''));
                });
            }
        });
    }

    /* ------------------------------------------------------------- submit */
    const OPS = {
        deposit:  { endpoint: 'deposit',  amount: 'dep-amount', submit: 'dep-submit', hint: 'dep-hint' },
        withdraw: { endpoint: 'withdraw', amount: 'wd-amount',  submit: 'wd-submit',  hint: 'wd-hint' },
        transfer: { endpoint: 'transfer', amount: 'tr-amount',  submit: 'tr-submit',  hint: 'tr-hint' },
        donate:   { endpoint: 'donate',   amount: 'don-amount', submit: 'don-submit', hint: 'don-hint' },
    };

    async function submitOp(kind) {
        const cfg = OPS[kind];
        const amt = getAmt($(cfg.amount));
        if (amt <= 0) { setHint($(cfg.hint), 'err', 'Bir tutar gir.'); return; }

        const payload = { amount: amt };
        if (kind === 'transfer') {
            payload.account = $('tr-account').value.trim().toUpperCase();
            payload.note = $('tr-note').value.trim();
            if (!/^[A-Z0-9]{4}$/.test(payload.account)) {
                setHint($('tr-hint'), 'err', 'Alıcı hesap no 4 hane olmalı.');
                return;
            }
        }

        $(cfg.submit).disabled = true;
        setHint($(cfg.hint), '', 'İşleniyor…');

        const res = await post(cfg.endpoint, payload);
        applyResult(res);

        if (res && res.success) {
            $(cfg.amount).value = '';
            if (kind === 'transfer') { $('tr-note').value = ''; $('tr-account').value = ''; }
            setHint($(cfg.hint), 'ok', res.message || 'İşlem tamamlandı.');
            toast('ok', res.message || 'İşlem tamamlandı.');
            if (kind === 'deposit' || kind === 'withdraw' || kind === 'donate') flashTx();
        } else {
            setHint($(cfg.hint), 'err', (res && res.reason) || 'İşlem başarısız.');
            toast('err', (res && res.reason) || 'İşlem başarısız.');
        }

        renderAll();
    }

    function applyResult(res) {
        if (!res || typeof res !== 'object') return;
        if (typeof res.cash === 'number') state.player.cash = res.cash;
        if (typeof res.bank === 'number') state.player.bank = res.bank;
        if (res.name) state.player.name = res.name;
        if (res.account) state.player.account = res.account;
        if (typeof res.donationTotal === 'number') state.donationTotal = res.donationTotal;
        if (Array.isArray(res.transactions)) state.tx = res.transactions;
    }

    /* ------------------------------------------------------- transactions */
    function renderTx() {
        txListEl.querySelectorAll('.tx-row').forEach(el => el.remove());
        const has = state.tx.length > 0;
        txEmptyEl.classList.toggle('hidden', has);
        if (!has) return;

        state.tx.forEach((r, i) => {
            const m = TXMETA[r.type] || { icon: I.activity, sign: +1, color: '#b46bff' };
            const row = document.createElement('div');
            row.className = 'tx-row';
            row.style.animationDelay = Math.min(i * 16, 220) + 'ms';
            row.style.setProperty('--cat', m.color);
            row.style.setProperty('--cat-bg', hexA(m.color, 0.14));
            row.innerHTML =
                `<span class="ti">${svg(m.icon)}</span>
                 <div class="tinfo">
                    <b>${esc(r.title || '')}</b>
                    <small>${esc(r.description || r.counterparty || '')}</small>
                 </div>
                 <div class="tright">
                    <div class="amt ${m.sign < 0 ? 'neg' : 'pos'}">${moneySigned(m.sign * (Number(r.amount) || 0))}</div>
                    <div class="when">${fmtWhen(r.ts)}</div>
                 </div>`;
            txListEl.appendChild(row);
        });
    }
    function hexA(hex, a) {
        const h = hex.replace('#', '');
        const n = parseInt(h, 16);
        return `rgba(${(n >> 16) & 255}, ${(n >> 8) & 255}, ${n & 255}, ${a})`;
    }
    function esc(s) {
        return String(s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
    }
    let flashTimer;
    function flashTx() {
        txPanel.classList.remove('flash');
        void txPanel.offsetWidth;
        txPanel.classList.add('flash');
        clearTimeout(flashTimer);
        flashTimer = setTimeout(() => txPanel.classList.remove('flash'), 650);
    }

    /* ------------------------------------------------------ balance hide */
    function applyBalHidden() {
        accountCard.classList.toggle('bal-hidden', state.balHidden);
        statsEl.classList.toggle('bal-hidden', state.balHidden);
        eyeLabel.textContent = state.balHidden ? 'Bakiyeyi göster' : 'Bakiyeyi gizle';
    }
    eyeToggle.addEventListener('click', () => {
        state.balHidden = !state.balHidden;
        try { localStorage.setItem('bbank_balHidden', state.balHidden ? '1' : '0'); } catch (e) {}
        applyBalHidden();
    });

    /* -------------------------------------------------------------- misc */
    function renderAll() {
        renderHeader();
        renderOverview();
        renderForms();
        renderTx();
    }

    let toastTimer;
    /* ------------------------------------------------------------- cezalar */
    // Polisin kestiği cezalar (loe_jobcreator): ödenmemişler "Öde" ile bankadan ödenir; ödenenler açıklamalarıyla "Ödendi" olarak kalır.
    async function loadFines() {
        const list = $('fines-list');
        const res = await post('fines');
        list.innerHTML = '';
        if (!res || !res.success) {
            list.innerHTML = `<div class="tx-empty">${esc((res && res.reason) || 'Cezalar alınamadı.')}</div>`;
            return;
        }
        const fines = Array.isArray(res.fines) ? res.fines : [];
        if (fines.length === 0) { list.innerHTML = '<div class="tx-empty">Hiç cezan yok.</div>'; return; }
        fines.forEach(f => {
            const what = (f.offences || []).map(o => (o.code ? o.code + ' ' : '') + (o.label || '')).join(', ');
            const row = document.createElement('div');
            row.className = 'tx-row fine-row' + (f.paid ? ' paid' : '');
            row.style.setProperty('--cat', f.paid ? '#34e07f' : '#ff2e97');
            row.innerHTML =
                `<span class="ti">${svg(I.doc)}</span>` +
                `<div class="tinfo"><b>${esc(String(f.job || '').toUpperCase())} · #${esc(f.id)}${f.callsign ? ' · ' + esc(f.callsign) : ''}</b>` +
                `<small class="wrap">${esc(what)}</small>` +
                (f.note ? `<small class="wrap note">${esc(f.note)}</small>` : '') + `</div>` +
                `<div class="tright"><div class="amt ${f.paid ? 'pos' : 'neg'}">${esc(money(f.amount))}</div>` +
                `<div class="when">${esc(fmtWhen(f.at))}</div>` +
                (f.paid ? `<div class="fine-paid">Ödendi${f.paidAt ? ' · ' + esc(fmtWhen(f.paidAt)) : ''}</div>`
                        : `<button class="op-submit fine-pay" type="button">Öde</button>`) +
                `</div>`;
            const btn = row.querySelector('.fine-pay');
            if (btn) btn.addEventListener('click', async () => {
                btn.disabled = true;
                const r = await post('payFine', { id: f.id });
                if (!r || !r.success) { btn.disabled = false; toast('error', (r && r.reason) || 'Ödenemedi.'); return; }
                toast('success', r.reason || 'Ceza ödendi.');
                if (r.data && r.data.success) { applyResult(r.data); renderAll(); }
                loadFines();
            });
            list.appendChild(row);
        });
    }

    function toast(kind, text) {
        clearTimeout(toastTimer);
        toastEl.className = 'toast ' + kind;
        toastEl.textContent = text;
        toastEl.classList.remove('hidden');
        toastTimer = setTimeout(() => toastEl.classList.add('hidden'), 2800);
    }


    /* -------------------------------------------------------- open/close */
    function openBank(msg) {
        state.bank   = msg.bank || {};
        state.limits = msg.limits || {};
        const d = msg.data || {};
        state.player = {
            name: d.name || 'Müşteri',
            account: d.account || null,
            cash: d.cash || 0,
            bank: d.bank || 0,
        };
        if (d.bankName) state.bank.name = d.bankName;
        state.tx = Array.isArray(d.transactions) ? d.transactions : [];
        state.donationTotal = Number(d.donationTotal) || 0;

        try { state.balHidden = localStorage.getItem('bbank_balHidden') === '1'; } catch (e) { state.balHidden = false; }

        ['dep-amount', 'wd-amount', 'tr-amount', 'tr-account', 'tr-note', 'don-amount'].forEach(id => { $(id).value = ''; });
        ['dep-hint', 'wd-hint', 'tr-hint', 'don-hint'].forEach(id => setHint($(id), '', ''));

        renderMenu();
        setView('overview');
        renderAll();
        app.classList.remove('hidden');
    }
    function updateBank(msg) {
        applyResult(msg.data || msg);
        renderAll();
    }
    function closeBank(fromKey) {
        if (app.classList.contains('hidden')) return;
        app.classList.add('hidden');
        toastEl.classList.add('hidden');
        if (fromKey) post('close', {});
    }

    /* ----------------------------------------------------- copy account */
    async function copyAccount() {
        const acc = state.player.account;
        if (!acc) return;
        let ok = false;
        try { await navigator.clipboard.writeText(acc); ok = true; } catch (e) {}
        if (!ok) {
            try {
                const ta = document.createElement('textarea');
                ta.value = acc;
                ta.style.position = 'fixed'; ta.style.top = '-999px'; ta.style.opacity = '0';
                document.body.appendChild(ta);
                ta.select();
                ok = document.execCommand('copy');
                document.body.removeChild(ta);
            } catch (e) {}
        }
        const btn = $('ac-copy');
        if (ok) {
            btn.classList.add('done');
            setTimeout(() => btn.classList.remove('done'), 1200);
            toast('ok', 'Hesap no kopyalandı.');
        } else {
            toast('err', 'Kopyalanamadı.');
        }
    }

    /* --------------------------------------------------------- listeners */
    buildChips();
    attachAmount($('dep-amount'), renderForms);
    attachAmount($('wd-amount'),  renderForms);
    attachAmount($('tr-amount'),  renderForms);
    attachAmount($('don-amount'), renderForms);
    $('tr-account').addEventListener('input', () => {
        const el = $('tr-account');
        el.value = el.value.toUpperCase().replace(/[^A-Z0-9]/g, '').slice(0, 4);
        renderForms();
    });

    $('dep-submit').addEventListener('click', () => submitOp('deposit'));
    $('wd-submit').addEventListener('click',  () => submitOp('withdraw'));
    $('tr-submit').addEventListener('click',  () => submitOp('transfer'));
    $('don-submit').addEventListener('click', () => submitOp('donate'));

    [['dep-amount', 'deposit'], ['wd-amount', 'withdraw'], ['tr-amount', 'transfer'], ['tr-note', 'transfer'], ['don-amount', 'donate']].forEach(([id, kind]) => {
        $(id).addEventListener('keydown', e => { if (e.key === 'Enter' && !$(OPS[kind].submit).disabled) submitOp(kind); });
    });

    $('promo-donate').addEventListener('click', () => setView('donate'));
    $('ac-copy').addEventListener('click', copyAccount);

    closeBtn.addEventListener('click', () => closeBank(true));
    logoutBtn.addEventListener('click', () => closeBank(true));
    bellBtn.addEventListener('click', () => toast('ok', 'Yeni bildirim yok.'));

    txRefreshBtn.addEventListener('click', async () => {
        const res = await post('refresh', {});
        if (res && res.success) { applyResult(res); renderAll(); flashTx(); }
    });

    window.addEventListener('message', (event) => {
        const data = event.data || {};
        if (data.action === 'open') openBank(data);
        else if (data.action === 'update') updateBank(data);
        else if (data.action === 'close') closeBank(false);
    });

    window.addEventListener('keyup', (event) => {
        if (app.classList.contains('hidden')) return;
        const tag = (document.activeElement && document.activeElement.tagName) || '';
        const typing = tag === 'INPUT' || tag === 'TEXTAREA';
        if (event.key === 'Escape' || (event.key === 'Backspace' && !typing)) closeBank(true);
    });
})();

