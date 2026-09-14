/**
 * MacHinge Reusable Video & Placeholder Media Component
 * 
 * Supports seamless transitions from placeholder state to full HTML5 video
 * (MP4 / WebM) without altering DOM structure or CSS layouts.
 */

export function createMediaContainer(effect) {
  const container = document.createElement('div');
  container.className = `media-viewport effect-${effect.id}`;
  container.setAttribute('role', 'region');
  container.setAttribute('aria-label', `${effect.name} video preview`);

  if (effect.videoSrc) {
    // 1. Full Real HTML5 Video Implementation
    const videoWrapper = document.createElement('div');
    videoWrapper.className = 'video-wrapper';

    const video = document.createElement('video');
    video.className = 'effect-video';
    video.src = effect.videoSrc;
    if (effect.posterSrc) video.poster = effect.posterSrc;
    video.autoplay = true;
    video.muted = true;
    video.loop = true;
    video.playsInline = true;
    video.setAttribute('preload', 'metadata');
    video.setAttribute('aria-label', `${effect.name} demonstration video`);

    // Controls bar
    const controls = document.createElement('div');
    controls.className = 'video-controls-overlay';
    
    const playBtn = document.createElement('button');
    playBtn.className = 'video-btn play-pause-btn';
    playBtn.setAttribute('aria-label', 'Pause video');
    playBtn.innerHTML = `
      <svg class="icon-pause" viewBox="0 0 24 24" width="16" height="16" fill="currentColor">
        <path d="M6 19h4V5H6v14zm8-14v14h4V5h-4z"/>
      </svg>
      <svg class="icon-play" viewBox="0 0 24 24" width="16" height="16" fill="currentColor" style="display:none;">
        <path d="M8 5v14l11-7z"/>
      </svg>
    `;

    playBtn.addEventListener('click', () => {
      if (video.paused) {
        video.play();
        playBtn.querySelector('.icon-pause').style.display = 'block';
        playBtn.querySelector('.icon-play').style.display = 'none';
        playBtn.setAttribute('aria-label', 'Pause video');
      } else {
        video.pause();
        playBtn.querySelector('.icon-pause').style.display = 'none';
        playBtn.querySelector('.icon-play').style.display = 'block';
        playBtn.setAttribute('aria-label', 'Play video');
      }
    });

    const muteBtn = document.createElement('button');
    muteBtn.className = 'video-btn mute-btn';
    muteBtn.setAttribute('aria-label', 'Unmute audio');
    muteBtn.innerHTML = `
      <svg class="icon-muted" viewBox="0 0 24 24" width="16" height="16" fill="currentColor">
        <path d="M16.5 12c0-1.77-1.02-3.29-2.5-4.03v2.21l2.45 2.45c.03-.2.05-.41.05-.63zm2.5 0c0 .94-.2 1.82-.54 2.64l1.51 1.51C20.63 14.91 21 13.5 21 12c0-4.28-2.99-7.86-7-8.77v2.06c2.89.86 5 3.54 5 6.71zM4.27 3L3 4.27 7.73 9H3v6h4l5 5v-6.73l4.25 4.25c-.67.52-1.42.93-2.25 1.18v2.06c1.38-.31 2.63-.95 3.69-1.81L19.73 21 21 19.73l-9-9L4.27 3zM12 4L9.91 6.09 12 8.18V4z"/>
      </svg>
    `;
    muteBtn.addEventListener('click', () => {
      video.muted = !video.muted;
      muteBtn.setAttribute('aria-label', video.muted ? 'Unmute audio' : 'Mute audio');
    });

    controls.appendChild(playBtn);
    controls.appendChild(muteBtn);

    videoWrapper.appendChild(video);
    videoWrapper.appendChild(controls);
    container.appendChild(videoWrapper);

  } else {
    // 2. Cinematic Apple-Style Video Placeholder Container
    const placeholder = document.createElement('div');
    placeholder.className = 'media-placeholder';
    
    // Abstract shader visualization aura
    const aura = document.createElement('div');
    aura.className = `placeholder-aura aura-${effect.id}`;
    placeholder.appendChild(aura);

    // Subtle Mac display bezel framing
    const innerFrame = document.createElement('div');
    innerFrame.className = 'placeholder-inner-frame';

    // Center badge & label
    const content = document.createElement('div');
    content.className = 'placeholder-content';
    content.innerHTML = `
      <div class="placeholder-icon-wrap">
        <div class="placeholder-pulse-ring"></div>
        <svg class="placeholder-cam-icon" viewBox="0 0 24 24" width="28" height="28" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round">
          <polygon points="5 3 19 12 5 21 5 3"></polygon>
        </svg>
      </div>
      <div class="placeholder-badge">Effect preview coming soon</div>
      <div class="placeholder-hint">Visual demonstration recording in production</div>
      <div class="placeholder-meta">
        <span class="meta-tag">Apple Metal Shaders</span>
        <span class="meta-dot">•</span>
        <span class="meta-tag">60 FPS Hardware Sync</span>
      </div>
    `;

    innerFrame.appendChild(content);
    placeholder.appendChild(innerFrame);
    container.appendChild(placeholder);
  }

  return container;
}
