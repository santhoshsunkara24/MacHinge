/**
 * MacHinge — Hero Demo Video Controller
 * Drop in your video file path into `videoSrc` to immediately display the real video player.
 */

const HERO_VIDEO_CONFIG = {
  videoSrc: 'assets/videos/demo.mp4',
  posterSrc: 'assets/videos/demo-poster.jpg',
  title: 'MacHinge Live Demonstration',
  subtext: 'Real-time Apple Silicon physical lid tracking and Metal GPU folding transitions.'
};

document.addEventListener('DOMContentLoaded', () => {
  const container = document.getElementById('hero-video-mount');
  if (!container) return;

  if (HERO_VIDEO_CONFIG.videoSrc) {
    // Render real HTML5 video player with Apple-grade presentation (always on loop, no overlay controls)
    container.innerHTML = `
      <div class="video-player-frame">
        <video 
          autoplay 
          muted 
          loop 
          playsinline 
          preload="auto"
          poster="${HERO_VIDEO_CONFIG.posterSrc || ''}"
          class="hero-video-element"
        >
          <source src="${HERO_VIDEO_CONFIG.videoSrc}" type="video/mp4">
          Your browser does not support HTML5 video.
        </video>
      </div>
    `;
    const video = container.querySelector('video');
    if (video) {
      video.play().catch(() => {});
    }
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
