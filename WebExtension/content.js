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
  let resumeTimer = null;      // one-shot check that the main video actually resumes after an ad
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
    // If the main video is still paused shortly after the ad ended, resume it once (YouTube meant to autoplay it).
    clearTimeout(resumeTimer);
    resumeTimer = setTimeout(() => {
      if (video.paused && !video.ended && !player()?.classList.contains('ad-showing')) {
        console.info('[SafariAdBlock] main video did not resume after the ad; resuming');
        video.play().catch(() => {});
      }
    }, 800);
  }

  // Dismiss the ad-blocker detection warning and resume playback
  function dismissEnforcement(video) {
    const message = document.querySelector('ytd-enforcement-message-view-model');
    if (!message) return;
    const dialog = message.closest('tp-yt-paper-dialog');
    if (dialog) dialog.remove();
    document.querySelectorAll('tp-yt-iron-overlay-backdrop').forEach((b) => b.remove());
    if (video && video.paused) video.play().catch(() => {});
  }

  function tick() {
    const p = player();
    if (!p) return;
    if (!reported && document.body) {
      reported = true;
      console.info('[SafariAdBlock] Video Ad Skipper active. Main-world script:', document.documentElement.dataset.sabMain === '1' ? 'running' : 'not running');
    }
    const video = p.querySelector('video.html5-main-video') || p.querySelector('video');
    const adShowing = p.classList.contains('ad-showing');
    if (video) {
      if (adShowing) {
        adTicks += 1;
        skipAd(p, video);
      } else {
        adTicks = 0;
        if (finite(video.duration)) contentDuration = video.duration;
        restore(video);
      }
    }
    clickAny(p, CLOSE_BUTTONS);
    dismissEnforcement(video);
  }

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
