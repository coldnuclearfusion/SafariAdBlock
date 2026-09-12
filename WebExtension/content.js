// Video Ad Skipper — runs inside the video site's pages (isolated world). Fallback for ads that main.js did not filter out.
// How it works: while the player is in the ad state (.ad-showing), click the skip button and play the ad at 16x.
// The ad is deliberately NOT muted: unmuting by script afterwards makes Safari pause the main video (WebKit's autoplay
// policy), and YouTube would also persist the muted state as the user's setting.
// Seeking to the end of the ad video happens only when ALL of the following hold, because otherwise the main video could be skipped:
//   - ad UI (overlay, remaining time, etc.) is actually visible,
//   - the video element's duration differs from the main video duration recorded just before the ad
//     (guards against the switch-over moment when the element still points at the main video),
//   - the ad state has been observed on at least two consecutive ticks (the first tick after the switch is skipped).
// Needs adjusting when the site changes its page structure.
(() => {
  'use strict';

  const SKIP_BUTTONS = [
    '.ytp-skip-ad-button',
    '.ytp-ad-skip-button',
    '.ytp-ad-skip-button-modern',
    '.ytp-ad-skip-button-slot button',
    '.ytp-ad-skip-button-container button',
  ];
  const AD_UI = [
    '.ytp-ad-player-overlay-layout', '.ytp-ad-player-overlay', '.ytp-ad-text', '.ytp-ad-preview-container',
    '.ytp-ad-duration-remaining', '.ytp-ad-simple-ad-badge', '.ytp-ad-skip-button-container', '.ytp-skip-ad-button',
    '.ytp-ad-persistent-progress-bar-container',
  ];
  const CLOSE_BUTTONS = ['.ytp-ad-overlay-close-button'];
  const AD_RATE = 16;

  let saved = null;            // user's playback rate before the ad
  let resumeTimer = null;      // interval that checks the main video actually resumes after an ad
  let startupTimer = null;     // interval that checks a freshly opened video actually starts
  let lastWatchURL = '';       // last watch page URL for which the startup check ran
  const watched = new WeakSet(); // video elements whose pause/play events are being logged

  // Diagnostics: the last 40 lines go to the console and into data-sab-log on <html>, where they can be read from
  // the page's main world (for example via Safari's "Allow JavaScript from Apple Events").
  const diagLines = [];
  function diag(msg) {
    diagLines.push(new Date().toISOString().slice(11, 23) + ' ' + msg);
    if (diagLines.length > 40) diagLines.shift();
    console.info('[SafariAdBlock] ' + msg);
    try { document.documentElement.dataset.sabLog = JSON.stringify(diagLines); } catch (e) {}
  }
  const playerClasses = (p) => Array.from(p.classList).filter((c) => /mode|ad-|ended/.test(c)).join(' ');
  const openDialogs = () => document.querySelectorAll('tp-yt-paper-dialog:not([aria-hidden="true"]), ytd-enforcement-message-view-model').length;

  function watchVideo(p, video) {
    if (watched.has(video)) return;
    watched.add(video);
    for (const type of ['pause', 'play', 'ended']) {
      video.addEventListener(type, () => {
        diag(type + ' event at t=' + video.currentTime.toFixed(1) + ', rate=' + video.playbackRate + ', muted=' + video.muted +
             ', dialogs=' + openDialogs() + ', player=[' + playerClasses(p) + ']');
      });
    }
  }
  let contentDuration = NaN;   // main video duration seen just before the ad
  let adTicks = 0;             // consecutive ticks in which the ad state was observed
  let observed = null;         // the player the MutationObserver is watching
  let reported = false;

  const player = () => document.querySelector('#movie_player, .html5-video-player');
  const finite = (n) => Number.isFinite(n) && n > 0;

  function clickAny(root, selectors) {
    for (const sel of selectors) {
      const button = root.querySelector(sel);
      if (button) button.click();
    }
  }

  function skipAd(p, video) {
    if (saved === null) saved = video.playbackRate;
    clickAny(p, SKIP_BUTTONS);
    if (video.playbackRate !== AD_RATE) video.playbackRate = AD_RATE;

    const adUIVisible = AD_UI.some((sel) => p.querySelector(sel));
    const looksLikeAdMedia = finite(video.duration) && video.duration !== contentDuration;
    if (adTicks >= 2 && adUIVisible && looksLikeAdMedia && video.currentTime < video.duration - 0.5) {
      video.currentTime = video.duration;   // jump to the end of the ad
    }
  }

  function restore(video) {
    if (saved === null) return;
    video.playbackRate = saved;
    saved = null;
    scheduleResume(video);
  }

  // YouTube means to keep playing after an ad or after its warning dialog. If the video is paused instead, resume it:
  // check every 250 ms for five seconds, at most four attempts. A deliberate pause by the user after that is left alone.
  function scheduleResume(video) {
    clearInterval(resumeTimer);
    let checks = 0;
    let attempts = 0;
    resumeTimer = setInterval(() => {
      checks += 1;
      const p = player();
      const adShowing = p && p.classList.contains('ad-showing');
      if (checks > 20 || attempts >= 4 || !document.contains(video)) { clearInterval(resumeTimer); return; }
      if (adShowing || !video.paused || video.ended) return;
      attempts += 1;
      diag('video is paused after an ad or a dialog; resuming (attempt ' + attempts + ')');
      video.play().catch((e) => {
        diag('play() was rejected: ' + (e && e.name) + ' — ' + (e && e.message));
        // Fall back to the player's own play button, which goes through YouTube's code path.
        const button = p && p.querySelector('.ytp-play-button, .ytp-large-play-button');
        if (button && video.paused) button.click();
      });
    }, 250);
  }

  // Dismiss the ad-blocker detection warning and resume playback
  function dismissEnforcement(video) {
    const message = document.querySelector('ytd-enforcement-message-view-model');
    if (!message) return;
    diag('ad-blocker warning dialog found; dismissing');
    const dialog = message.closest('tp-yt-paper-dialog');
    if (dialog) dialog.remove();
    document.querySelectorAll('tp-yt-iron-overlay-backdrop').forEach((b) => b.remove());
    if (video) scheduleResume(video);   // YouTube pauses the video ~30 ms after the dialog appears; keep checking
  }

  // A freshly opened watch page is meant to start playing on its own. If the video has media ready but sits paused at
  // the start for a while (no ad involved), start it: check every 400 ms for six seconds after navigation, at most two
  // attempts, top frame only, and never while the tab is hidden. Whatever paused it (an anti-ad-blocker nudge, a
  // playback policy) is reported in the console.
  function startupCheck() {
    if (window !== window.top || !location.pathname.startsWith('/watch')) return;
    if (location.href === lastWatchURL) return;
    lastWatchURL = location.href;
    clearInterval(startupTimer);
    let checks = 0;
    let attempts = 0;
    startupTimer = setInterval(() => {
      checks += 1;
      const p = player();
      const video = p && (p.querySelector('video.html5-main-video') || p.querySelector('video'));
      if (checks > 15 || attempts >= 2 || document.hidden) { if (checks > 15 || attempts >= 2) clearInterval(startupTimer); return; }
      if (!video || video.readyState < 2 || !video.paused || video.ended || video.currentTime > 1) return;
      if (p.classList.contains('ad-showing')) return;
      attempts += 1;
      diag('video is paused at the start of ' + location.pathname + location.search + '; starting it (attempt ' + attempts + '), player=[' + playerClasses(p) + '], dialogs=' + openDialogs());
      video.play().catch((e) => diag('play() was rejected: ' + (e && e.name) + ' — ' + (e && e.message)));
    }, 400);
  }

  function tick() {
    startupCheck();
    const p = player();
    if (!p) return;
    if (!reported && document.body) {
      reported = true;
      diag('Video Ad Skipper active. Main-world script: ' + (document.documentElement.dataset.sabMain === '1' ? 'running' : 'not running'));
    }
    const video = p.querySelector('video.html5-main-video') || p.querySelector('video');
    const adShowing = p.classList.contains('ad-showing');
    if (video) {
      watchVideo(p, video);
      if (adShowing) {
        adTicks += 1;
        if (adTicks === 1) diag('ad started (duration=' + video.duration + ', contentDuration=' + contentDuration + ')');
        skipAd(p, video);
      } else {
        if (adTicks > 0) diag('ad ended (video paused=' + video.paused + ', t=' + video.currentTime.toFixed(1) + ')');
        adTicks = 0;
        if (finite(video.duration)) contentDuration = video.duration;
        restore(video);
      }
    }
    clickAny(p, CLOSE_BUTTONS);
    dismissEnforcement(video);
  }

  // Remove the ad-blocker warning the moment it is inserted, before YouTube's open-popup handler pauses the video, and
  // keep the video playing. The periodic tick also catches it in case the insertion is missed.
  const dialogObserver = new MutationObserver((mutations) => {
    for (const m of mutations) {
      for (const node of m.addedNodes) {
        if (node.nodeType !== 1) continue;
        const hit = node.matches && node.matches('ytd-enforcement-message-view-model') ? node : node.querySelector && node.querySelector('ytd-enforcement-message-view-model');
        if (!hit) continue;
        const p = player();
        const video = p && (p.querySelector('video.html5-main-video') || p.querySelector('video'));
        diag('ad-blocker warning inserted; removing immediately');
        dismissEnforcement(video);
        return;
      }
    }
  });
  if (document.documentElement) dialogObserver.observe(document.documentElement, { childList: true, subtree: true });

  // React to player class changes immediately; the periodic check follows player replacement during in-page navigation
  const observer = new MutationObserver(tick);
  function ensureObserver() {
    const p = player();
    if (p && p !== observed) {
      observer.disconnect();
      observer.observe(p, { attributes: true, attributeFilter: ['class'] });
      observed = p;
    }
  }
  setInterval(() => { ensureObserver(); tick(); }, 200);
})();
