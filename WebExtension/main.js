// Video Ad Skipper — runs in the page's main world (the same space as the site's own scripts) at document_start.
// Removes the ad entries (adPlacements, adSlots, playerAds) from the player response so ads never start.
// Unlike content.js, which ends an ad after it has loaded, this adds no delay. content.js is the fallback for
// anything this misses (server-side inserted ads, for example).
// Requires Safari 16.4 or later (world: "MAIN" in the manifest). Older Safari runs content.js only.
(() => {
  'use strict';
  if (window.__sabMainWorld) return;
  window.__sabMainWorld = true;
  // Leave a marker in the DOM so content.js (isolated world) can tell whether this script is active
  document.documentElement.dataset.sabMain = '1';

  // Ad entries are emptied rather than deleted: the player expects these keys to exist as arrays, and deleting them
  // can break player initialization when YouTube ships a new player build.
  const AD_KEYS = ['adPlacements', 'adSlots', 'playerAds'];
  const PLAYER_PATH = '/youtubei/v1/player';

  function strip(obj) {
    if (obj && typeof obj === 'object') {
      for (const key of AD_KEYS) if (key in obj) obj[key] = [];
    }
    return obj;
  }

  function stripText(text) {
    if (typeof text !== 'string' || !AD_KEYS.some((k) => text.includes('"' + k + '"'))) return text;
    try { return JSON.stringify(strip(JSON.parse(text))); } catch (e) { return text; }
  }

  function isPlayerRequest(input) {
    try {
      const url = typeof input === 'string' ? input : (input instanceof Request ? input.url : String(input));
      return url.includes(PLAYER_PATH);
    } catch (e) { return false; }
  }

  // 1) The initial response embedded in the HTML when a watch page is opened directly
  let initial;
  Object.defineProperty(window, 'ytInitialPlayerResponse', {
    configurable: true,
    enumerable: true,
    get() { return initial; },
    set(value) { initial = strip(value); },
  });

  // 2) Responses fetched during in-page navigation
  const originalFetch = window.fetch;
  window.fetch = async function (input, init) {
    const response = await originalFetch.call(this, input, init);
    if (!isPlayerRequest(input)) return response;
    try {
      const text = await response.clone().text();
      const cleaned = stripText(text);
      if (cleaned === text) return response;
      return new Response(cleaned, { status: response.status, statusText: response.statusText, headers: response.headers });
    } catch (e) {
      return response;
    }
  };

  // 3) Responses received through XMLHttpRequest (legacy path)
  const originalOpen = XMLHttpRequest.prototype.open;
  XMLHttpRequest.prototype.open = function (method, url, ...rest) {
    this.__sabPlayer = isPlayerRequest(url);
    return originalOpen.call(this, method, url, ...rest);
  };
  for (const prop of ['responseText', 'response']) {
    const desc = Object.getOwnPropertyDescriptor(XMLHttpRequest.prototype, prop);
    if (!desc || !desc.get) continue;
    Object.defineProperty(XMLHttpRequest.prototype, prop, {
      configurable: true,
      enumerable: desc.enumerable,
      get() {
        const value = desc.get.call(this);
        if (!this.__sabPlayer) return value;
        if (typeof value === 'string') return stripText(value);
        if (value && typeof value === 'object' && this.responseType === 'json') return strip(value);
        return value;
      },
    });
  }
})();
