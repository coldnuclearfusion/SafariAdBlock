// Background script: in case Safari ignores world: "MAIN" in the manifest, register main.js in the main world dynamically.
// (scripting.registerContentScripts with the MAIN world is supported since Safari 16.4.) main.js runs only once even if both paths are active.
(async () => {
  const api = typeof browser !== 'undefined' ? browser : chrome;
  if (!api.scripting || !api.scripting.registerContentScripts) return;
  const script = {
    id: 'sab-video-main',
    js: ['main.js'],
    matches: ['*://www.youtube.com/*', '*://m.youtube.com/*', '*://music.youtube.com/*', '*://www.youtube-nocookie.com/*'],
    runAt: 'document_start',
    allFrames: true,
    world: 'MAIN',
  };
  try {
    const existing = await api.scripting.getRegisteredContentScripts({ ids: [script.id] });
    if (existing && existing.length) await api.scripting.updateContentScripts([script]);
    else await api.scripting.registerContentScripts([script]);
  } catch (e) {
    console.warn('[SafariAdBlock] failed to register the main-world script:', e);
  }
})();
