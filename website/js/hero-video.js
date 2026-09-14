/**
 * MacHinge — Hero Demo Video Controller
 * Drop in your video file path into `videoSrc` to immediately display the real video player.
 */

const HERO_VIDEO_CONFIG = {
  // Set this to your local or remote video path when ready (e.g., 'assets/videos/machinge-demo.mp4')
  videoSrc: null,
  posterSrc: null,
  title: 'MacHinge Demonstration',
  subtext: 'Real-time Apple SPU sensor tracking and Metal GPU display transitions.'
};

document.addEventListener('DOMContentLoaded', () => {
  const container = document.getElementById('hero-video-mount');
  if (!container) return;

  if (HERO_VIDEO_CONFIG.videoSrc) {
    // Render real HTML5 video player
    container.innerHTML = `
      <div class="video-player-frame">
        <video 
          controls 
          playsinline 
          preload="metadata"
          poster="${HERO_VIDEO_CONFIG.posterSrc || ''}"
          class="hero-video-element"
        >
          <source src="${HERO_VIDEO_CONFIG.videoSrc}" type="video/mp4">
          Your browser does not support HTML5 video.
        </video>
      </div>
    `;
  } else {
    // Render Apple-style minimalist placeholder
    container.innerHTML = `
      <div class="video-placeholder-frame">
        <div class="video-placeholder-ambient"></div>
        <div class="video-placeholder-content">
          <div class="video-play-btn" aria-hidden="true">
            <svg viewBox="0 0 24 24" width="28" height="28" fill="currentColor">
              <path d="M8 5v14l11-7z"/>
            </svg>
          </div>
          <p class="video-placeholder-title">${HERO_VIDEO_CONFIG.title}</p>
          <p class="video-placeholder-subtitle">Demo video coming soon &bull; Upload path ready</p>
          <div class="video-spec-tags">
            <span class="video-tag">1080p 60 FPS</span>
            <span class="video-tag">Apple Metal Shaders</span>
            <span class="video-tag">Zero Telemetry</span>
          </div>
        </div>
      </div>
    `;
  }
});
