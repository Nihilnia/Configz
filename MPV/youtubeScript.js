// ==UserScript==
// @name         YouTube MPV & Copy Buttons in Control Bar
// @namespace    http://tampermonkey.net/
// @version      7.0
// @description  Adds "Open in MPV" and "Copy link" icon buttons to YouTube's native control bar
// @author       You
// @match        https://www.youtube.com/*
// @grant        none
// ==/UserScript==

(function () {
  'use strict';

  const style = document.createElement('style');
  style.textContent = `
    #mpv-ctrl-open,
    #mpv-ctrl-copy {
      background: none !important;
      border: none !important;
      padding: 0 !important;
      margin: 0 !important;
      cursor: pointer !important;
      display: inline-flex !important;
      align-items: center !important;
      justify-content: center !important;
      width: 36px !important;
      height: 100% !important;
      min-height: 0 !important;
      align-self: stretch !important;
      opacity: 0.9 !important;
      flex-shrink: 0 !important;
    }
    #mpv-ctrl-open:hover,
    #mpv-ctrl-copy:hover { opacity: 1 !important; }
    #mpv-ctrl-open svg,
    #mpv-ctrl-copy svg {
      width: 24px !important;
      height: 24px !important;
      display: block !important;
      pointer-events: none !important;
      overflow: visible !important;
    }
  `;
  document.head.appendChild(style);

  function makeMpvIcon() {
    const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
    svg.setAttribute('viewBox', '7 4 13 16');
    svg.setAttribute('width', '24');
    svg.setAttribute('height', '24');
    const path = document.createElementNS('http://www.w3.org/2000/svg', 'path');
    path.setAttribute('d', 'M8 5v14l11-7z');
    path.setAttribute('fill', 'white');
    svg.appendChild(path);
    return svg;
  }

  function makeLinkIcon(color) {
    const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
    svg.setAttribute('viewBox', '0 0 24 24');
    svg.setAttribute('width', '24');
    svg.setAttribute('height', '24');
    const path = document.createElementNS('http://www.w3.org/2000/svg', 'path');
    path.setAttribute('d', 'M3.9 12c0-1.71 1.39-3.1 3.1-3.1h4V7H7c-2.76 0-5 2.24-5 5s2.24 5 5 5h4v-1.9H7c-1.71 0-3.1-1.39-3.1-3.1zM8 13h8v-2H8v2zm9-6h-4v1.9h4c1.71 0 3.1 1.39 3.1 3.1s-1.39 3.1-3.1 3.1h-4V17h4c2.76 0 5-2.24 5-5s-2.24-5-5-5z');
    path.setAttribute('fill', color || 'white');
    svg.appendChild(path);
    return svg;
  }

  function makeCheckIcon() {
    const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
    svg.setAttribute('viewBox', '0 0 24 24');
    svg.setAttribute('width', '24');
    svg.setAttribute('height', '24');
    const path = document.createElementNS('http://www.w3.org/2000/svg', 'path');
    path.setAttribute('d', 'M9 16.17 4.83 12l-1.42 1.41L9 19 21 7l-1.41-1.41z');
    path.setAttribute('fill', '#4caf50');
    svg.appendChild(path);
    return svg;
  }

  function getVideoUrl() {
    const vid = new URLSearchParams(location.search).get('v');
    return vid ? 'https://www.youtube.com/watch?v=' + vid : location.href;
  }

  function openInMpv() {
    const url = 'mpv://' + encodeURIComponent(getVideoUrl());
    const a = document.createElement('a');
    a.href = url;
    a.style.display = 'none';
    document.body.appendChild(a);
    a.click();
    setTimeout(() => document.body.removeChild(a), 100);
  }

  function inject() {
    if (document.getElementById('mpv-ctrl-open')) return;
    const bar = document.querySelector('.ytp-right-controls-left');
    if (!bar) return;

    const btnOpen = document.createElement('button');
    btnOpen.id = 'mpv-ctrl-open';
    btnOpen.className = 'ytp-button';
    btnOpen.title = 'Open in MPV';
    btnOpen.appendChild(makeMpvIcon());
    btnOpen.onclick = (e) => {
      e.preventDefault();
      openInMpv();
    };

    const btnCopy = document.createElement('button');
    btnCopy.id = 'mpv-ctrl-copy';
    btnCopy.className = 'ytp-button';
    btnCopy.title = 'Copy link';
    btnCopy.appendChild(makeLinkIcon());
    let copyTimer = null;
    btnCopy.onclick = (e) => {
      e.preventDefault();
      navigator.clipboard.writeText(getVideoUrl()).then(() => {
        btnCopy.replaceChildren(makeCheckIcon());
        btnCopy.title = 'Copied!';
        clearTimeout(copyTimer);
        copyTimer = setTimeout(() => {
          btnCopy.replaceChildren(makeLinkIcon());
          btnCopy.title = 'Copy link';
        }, 1800);
      });
    };

    bar.appendChild(btnOpen);
    bar.appendChild(btnCopy);
  }

  // Use MutationObserver for faster injection
  const observer = new MutationObserver(inject);
  observer.observe(document.body, { childList: true, subtree: true });

  // Fallback and URL change detection
  let lastUrl = location.href;
  setInterval(() => {
    if (location.href !== lastUrl) {
      lastUrl = location.href;
      document.getElementById('mpv-ctrl-open')?.remove();
      document.getElementById('mpv-ctrl-copy')?.remove();
      inject();
    }
  }, 500);

  inject();
})();