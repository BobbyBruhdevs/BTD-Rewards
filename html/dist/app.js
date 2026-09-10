import { uiConfig } from './config.js';

let playerData = { activeTime: 0, rewards: [] };
let currentCode = '';
const $ = id => document.getElementById(id);
const resourceName = typeof GetParentResourceName === 'function' ? GetParentResourceName() : uiConfig.resourceName;
const post = (endpoint, body = {}) => fetch(`https://${resourceName}/${endpoint}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body)
});

function escapeHtml(value) {
    const element = document.createElement('div');
    element.textContent = value;
    return element.innerHTML;
}

function formatTime(seconds) {
    const hours = Math.floor(seconds / 3600);
    const minutes = Math.floor((seconds % 3600) / 60);
    return hours ? `${hours}h ${minutes}m` : `${minutes}m`;
}

function formatRequired(minutes) {
    if (minutes >= 60) {
        const hours = Math.floor(minutes / 60);
        const remaining = minutes % 60;
        return remaining ? `${hours}h ${remaining}m ${uiConfig.copy.required}` : `${hours} hour${hours === 1 ? '' : 's'} ${uiConfig.copy.required}`;
    }
    return `${minutes} minute${minutes === 1 ? '' : 's'} ${uiConfig.copy.required}`;
}

function show(id) { $(id).classList.add('is-visible'); $(id).setAttribute('aria-hidden', 'false'); }
function hide(id) { $(id).classList.remove('is-visible'); $(id).setAttribute('aria-hidden', 'true'); }

function renderRewards() {
    const activeMinutes = playerData.activeTime / 60;
    const grid = $('rewardsGrid');
    let claimedCount = 0;
    let nextReward = null;
    grid.innerHTML = '';

    playerData.rewards.forEach((reward, index) => {
        const available = activeMinutes >= reward.time && !reward.claimed;
        const progress = Math.min((activeMinutes / reward.time) * 100, 100);
        if (reward.claimed) claimedCount++;
        if (!reward.claimed && nextReward === null) nextReward = Math.max(0, reward.time - activeMinutes);

        const card = document.createElement('article');
        card.className = `reward-card${reward.claimed ? ' is-claimed' : ''}${!available && !reward.claimed ? ' is-locked' : ''}`;
        card.innerHTML = `<div class="reward-card__top"><span class="reward-number">${String(index + 1).padStart(2, '0')}</span><span class="badge badge--${reward.claimed ? 'claimed' : available ? 'available' : 'locked'}">${reward.claimed ? uiConfig.copy.claimed : available ? uiConfig.copy.available : uiConfig.copy.locked}</span></div><h3>${escapeHtml(reward.name)}</h3><p>${escapeHtml(reward.description)}</p><div class="reward-card__meta"><span>${formatRequired(reward.time)}</span><span>${Math.round(progress)}%</span></div><div class="progress"><span style="width:${progress}%"></span></div><button class="claim-button" type="button" ${available ? '' : 'disabled'}>${reward.claimed ? uiConfig.copy.alreadyClaimed : available ? uiConfig.copy.claim : uiConfig.copy.notAvailable}</button>`;
        card.querySelector('button')?.addEventListener('click', () => post('claimReward', { index: index + 1 }));
        grid.appendChild(card);
    });

    $('activeTime').textContent = formatTime(playerData.activeTime);
    $('rewardsClaimed').textContent = String(claimedCount);
    $('nextReward').textContent = nextReward === null ? uiConfig.copy.allClaimed : `${Math.ceil(nextReward)}m`;
    const journey = playerData.rewards.length ? Math.round((claimedCount / playerData.rewards.length) * 100) : 0;
    $('journeyProgress').textContent = `${journey}%`;
    $('journeyBar').style.width = `${journey}%`;
    $('rewardCount').textContent = `${playerData.rewards.length} reward${playerData.rewards.length === 1 ? '' : 's'}`;
}

function openRewards(data) { playerData = data; show('app'); hide('codePage'); renderRewards(); }
function closeUi(notifyGame = true) { hide('app'); hide('codePage'); if (notifyGame) post('close'); }
function showCode(data) {
    if (data.uiColor)
        applyConfig(data.uiColor);
    currentCode = data.code;
    $('codeText').textContent = data.code;
    $('codeReward').textContent = data.rewardName;
    $('claimedTime').textContent = new Date().toLocaleString();
    hide('app');
    show('codePage');
}

function notify(message, type) {
    const element = document.createElement('div');
    element.className = `notification notification--${type}`;
    element.textContent = message;
    document.body.appendChild(element);
    window.setTimeout(() => element.remove(), 3500);
}

async function copyWithFallback(value) {
    if (navigator.clipboard?.writeText) {
        try {
            await navigator.clipboard.writeText(value);
            return;
        }
        catch {
            // Fall through to the legacy NUI-compatible copy method.
        }
    }
    const input = document.createElement('textarea');
    input.value = value;
    input.setAttribute('readonly', '');
    input.style.position = 'fixed';
    input.style.opacity = '0';
    document.body.appendChild(input);
    input.select();
    const copied = document.execCommand('copy');
    input.remove();
    if (!copied)
        throw new Error('Copy command failed');
}
async function copyCode() {
    try { await copyWithFallback(currentCode); notify(uiConfig.copy.copied, 'success'); }
    catch { notify(uiConfig.copy.copyFailed, 'error'); }
}

function resolveRgb(color) {
    const element = document.createElement('span');
    element.style.color = color;
    document.body.appendChild(element);
    const match = getComputedStyle(element).color.match(/\d+(?:\.\d+)?/g);
    element.remove();
    return match ? match.slice(0, 3).map(Number) : [56, 168, 232];
}
function mixColor(color, base, amount) {
    const foreground = resolveRgb(color);
    const background = resolveRgb(base);
    return `rgb(${foreground.map((value, index) => Math.round(value * amount + background[index] * (1 - amount))).join(', ')})`;
}
function alphaColor(color, opacity) {
    return `rgba(${resolveRgb(color).join(', ')}, ${opacity})`;
}

function applyConfig(uiColor = uiConfig.uiColor) {
    const variables = {
        '--accent': uiColor,
        '--accent-strong': mixColor(uiColor, 'white', .55),
        '--cyan': uiColor,
        '--amber': mixColor(uiColor, 'white', .72),
        '--success': uiConfig.theme.success,
        '--danger': uiConfig.theme.danger,
        '--surface': mixColor(uiColor, '#081018', .12),
        '--header-surface': mixColor(uiColor, '#0a1018', .16),
        '--card-surface': mixColor(uiColor, '#0c121b', .22),
        '--soft': alphaColor(uiColor, .075),
        '--hover': alphaColor(uiColor, .13),
        '--border': alphaColor(uiColor, .14),
        '--border-bright': alphaColor(uiColor, .25),
        '--text': uiConfig.theme.text,
        '--muted': uiConfig.theme.mutedText,
        '--panel-width': uiConfig.layout.panelWidth,
        '--code-panel-width': uiConfig.layout.codePanelWidth,
        '--panel-height': uiConfig.layout.panelHeight,
        '--radius-panel': uiConfig.layout.panelRadius,
        '--radius-card': uiConfig.layout.cardRadius,
        '--radius-control': uiConfig.layout.controlRadius,
        '--radius-small': uiConfig.layout.smallRadius
    };
    Object.entries(variables).forEach(([name, value]) => document.documentElement.style.setProperty(name, value));

    $('brand').textContent = uiConfig.brand;
    $('eyebrow').textContent = uiConfig.eyebrow;
    $('tagline').textContent = uiConfig.tagline;
    $('availableTitle').textContent = uiConfig.availableTitle;
    $('codeBrand').textContent = uiConfig.brand;
    $('codeTitle').textContent = uiConfig.copy.codeTitle;
    $('codeDescription').textContent = uiConfig.copy.codeDescription;
    $('codeLabel').textContent = uiConfig.copy.codeLabel;
    $('codeHint').textContent = uiConfig.copy.codeHint;
    $('rewardDetailsTitle').textContent = uiConfig.copy.rewardDetails;
    $('copyHint').textContent = uiConfig.copy.copyCode;
    $('instructionsTitle').textContent = uiConfig.copy.instructions;
    $('instructionList').innerHTML = uiConfig.copy.instructionItems.map(item => `<li>${escapeHtml(item)}</li>`).join('');
    document.querySelectorAll('[data-copy]').forEach(element => { element.textContent = String(uiConfig.copy[element.dataset.copy]); });
}

document.addEventListener('DOMContentLoaded', () => {
    applyConfig();
    $('closeButton').addEventListener('click', closeUi);
    $('backButton').addEventListener('click', () => { hide('codePage'); show('app'); post('requestStats'); });
    $('backButtonBottom').addEventListener('click', () => { hide('codePage'); show('app'); post('requestStats'); });
    $('copyCode').addEventListener('click', copyCode);
    document.addEventListener('keydown', event => { if (event.key === 'Escape') closeUi(); });
});

window.addEventListener('message', event => {
    if (event.data.action === 'open' && event.data.data) {
        if (event.data.data.uiColor)
            applyConfig(event.data.data.uiColor);
        openRewards(event.data.data);
    }
    if (event.data.action === 'showCode' && event.data.data) showCode(event.data.data);
    if (event.data.action === 'redemptionResult' && event.data.data) notify(event.data.data.message, event.data.data.success ? 'success' : 'error');
    if (event.data.action === 'close') closeUi(false);
});
