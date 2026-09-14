import { effectsData } from './effects-data.js';
import { createMediaContainer } from './video-placeholder.js';

document.addEventListener('DOMContentLoaded', () => {
  initNavbar();
  initHeroSimulation();
  initEffectsShowcase();
  initHotkeyTester();
  initScrollAnimations();
});

/**
 * 1. Navigation Bar Blur & Scroll State
 */
function initNavbar() {
  const navbar = document.querySelector('.site-nav');
  const mobileToggle = document.querySelector('.mobile-menu-toggle');
  const mobileDrawer = document.querySelector('.mobile-menu');

  if (!navbar) return;

  const handleScroll = () => {
    if (window.scrollY > 24) {
      navbar.classList.add('nav-scrolled');
    } else {
      navbar.classList.remove('nav-scrolled');
    }
  };

  window.addEventListener('scroll', handleScroll, { passive: true });
  handleScroll();

  if (mobileToggle && mobileDrawer) {
    mobileToggle.addEventListener('click', () => {
      const isExpanded = mobileToggle.getAttribute('aria-expanded') === 'true';
      mobileToggle.setAttribute('aria-expanded', !isExpanded);
      mobileDrawer.classList.toggle('is-open');
    });

    mobileDrawer.querySelectorAll('a').forEach(link => {
      link.addEventListener('click', () => {
        mobileToggle.setAttribute('aria-expanded', 'false');
        mobileDrawer.classList.remove('is-open');
      });
    });
  }
}

/**
 * 2. Hero Interactive MacBook Simulation
 * 
 * Accurately models MacHinge's decoupled trigger architecture:
 * - Angles > 78°: 100% normal crisp display (0% GPU / Idle)
 * - Angles <= 78°: Smooth progressive Metal shader folding transition
 */
function initHeroSimulation() {
  const slider = document.getElementById('hero-angle-slider');
  const angleReadout = document.getElementById('hero-angle-value');
  const statusBadge = document.getElementById('hero-status-badge');
  const macbookDisplay = document.getElementById('sim-display');
  const macbookScreen = document.getElementById('sim-screen');
  const lidMesh = document.getElementById('sim-mesh');
  const presetBtns = document.querySelectorAll('.hero-preset-btn');
  const effectTabs = document.querySelectorAll('.hero-effect-tab');

  if (!slider || !angleReadout || !macbookDisplay) return;

  let activeEffect = 'luminous-glow';

  function updateSimulation(angle) {
    angleReadout.textContent = `${angle.toFixed(1)}°`;

    // MacHinge trigger threshold is 78.0° by default (effective range 78° down to 25°)
    const triggerAngle = 78.0;
    const closedEndpoint = 25.0;

    let progress = 0.0;
    if (angle < triggerAngle) {
      progress = Math.min(1.0, Math.max(0.0, (triggerAngle - angle) / (triggerAngle - closedEndpoint)));
    }

    // Update status badge
    if (angle > triggerAngle) {
      statusBadge.innerHTML = `
        <span class="badge-dot dot-idle"></span>
        <span class="badge-text">Normal Viewing Range • 100% Crisp Passthrough (0% GPU)</span>
      `;
      statusBadge.className = 'sim-status-badge state-idle';
    } else {
      const pct = Math.round(progress * 100);
      statusBadge.innerHTML = `
        <span class="badge-dot dot-active"></span>
        <span class="badge-text">Metal Transition Active • Fold ${pct}%</span>
      `;
      statusBadge.className = 'sim-status-badge state-active';
    }

    // Physical 3D perspective fold deformation
    const foldStrength = Math.pow(progress, 1.15);
    const perspectiveY = foldStrength * 28; // deg
    const compression = 1.0 - (foldStrength * 0.18);
    const translateY = foldStrength * 16; // px

    if (macbookScreen) {
      macbookScreen.style.transform = `perspective(1000px) rotateX(${perspectiveY}deg) scaleY(${compression}) translateY(${translateY}px)`;
    }

    // Visual effect simulation layers
    if (lidMesh) {
      if (activeEffect === 'luminous-glow') {
        const glowOpacity = Math.min(1.0, Math.pow(progress, 1.35) * 1.5);
        lidMesh.style.background = `radial-gradient(ellipse at 50% 100%, rgba(255, 255, 255, ${glowOpacity * 0.95}) 0%, rgba(200, 220, 255, ${glowOpacity * 0.45}) 35%, transparent 70%)`;
        lidMesh.style.filter = `blur(${progress * 12}px)`;
        lidMesh.style.opacity = glowOpacity > 0.02 ? '1' : '0';
      } else if (activeEffect === 'frosted-glass') {
        const blurAmount = progress * 16;
        const frostedOpacity = progress * 0.85;
        lidMesh.style.background = `rgba(255, 255, 255, ${frostedOpacity * 0.18})`;
        lidMesh.style.backdropFilter = `blur(${blurAmount}px)`;
        lidMesh.style.webkitBackdropFilter = `blur(${blurAmount}px)`;
        lidMesh.style.opacity = progress > 0.02 ? '1' : '0';
      } else if (activeEffect === 'magnetic-lens') {
        const lensProgress = Math.pow(progress, 1.25);
        lidMesh.style.background = `radial-gradient(circle at 50% 105%, rgba(10, 132, 255, ${lensProgress * 0.6}) 0%, rgba(94, 92, 230, ${lensProgress * 0.3}) 45%, transparent 70%)`;
        lidMesh.style.filter = `contrast(${1 + lensProgress * 0.3}) saturate(${1 + lensProgress * 0.5})`;
        lidMesh.style.opacity = lensProgress > 0.02 ? '1' : '0';
      }
    }
  }

  slider.addEventListener('input', (e) => {
    updateSimulation(parseFloat(e.target.value));
  });

  presetBtns.forEach(btn => {
    btn.addEventListener('click', () => {
      const angle = parseFloat(btn.dataset.angle);
      slider.value = angle;
      presetBtns.forEach(b => b.classList.remove('is-active'));
      btn.classList.add('is-active');
      updateSimulation(angle);
    });
  });

  effectTabs.forEach(tab => {
    tab.addEventListener('click', () => {
      effectTabs.forEach(t => t.classList.remove('is-active'));
      tab.classList.add('is-active');
      activeEffect = tab.dataset.effect;
      updateSimulation(parseFloat(slider.value));
    });
  });

  // Initial simulation state at comfortable viewing angle (105.0°)
  updateSimulation(105.0);
}

/**
 * 3. Effects Showcase Dynamic Mounting
 */
function initEffectsShowcase() {
  const showcaseContainer = document.getElementById('effects-list-container');
  if (!showcaseContainer) return;

  effectsData.forEach((effect, index) => {
    const card = document.createElement('article');
    card.className = 'effect-card';
    card.id = `effect-${effect.id}`;

    // Layout: Alternating media left/right on desktop
    const isReversed = index % 2 === 1;

    const detailsCol = document.createElement('div');
    detailsCol.className = 'effect-details-col';
    detailsCol.innerHTML = `
      <div class="effect-badge-row">
        <span class="effect-badge">${effect.badge}</span>
        <span class="effect-verified-pill">Shader Verified</span>
      </div>
      <h3 class="effect-title">${effect.name}</h3>
      <p class="effect-tagline">${effect.tagline}</p>
      <p class="effect-summary">${effect.summary}</p>
      
      <div class="effect-behavior-box">
        <h4 class="behavior-heading">Lid Movement Behavior</h4>
        <p class="behavior-text">${effect.behavior}</p>
      </div>

      <div class="effect-best-for">
        <strong>Best For:</strong> ${effect.bestFor}
      </div>

      <div class="effect-specs-list">
        <div class="specs-title">Metal Implementation Highlights</div>
        <ul>
          ${effect.shaderDetails.map(d => `<li><code>${escapeHTML(d)}</code></li>`).join('')}
        </ul>
      </div>
    `;

    const mediaCol = document.createElement('div');
    mediaCol.className = 'effect-media-col';
    const mediaContainer = createMediaContainer(effect);
    mediaCol.appendChild(mediaContainer);

    if (isReversed) {
      card.appendChild(mediaCol);
      card.appendChild(detailsCol);
      card.classList.add('layout-reversed');
    } else {
      card.appendChild(detailsCol);
      card.appendChild(mediaCol);
    }

    showcaseContainer.appendChild(card);
  });
}

/**
 * 4. Hotkeys Interactive Tester & Calibration Toast HUD
 */
function initHotkeyTester() {
  const testBtn = document.getElementById('test-hotkey-btn');
  const hud = document.getElementById('calibration-hud');
  const hudAngle = document.getElementById('hud-calibrated-angle');

  if (!hud) return;

  function triggerHUD(angle = 80.0) {
    if (hudAngle) hudAngle.textContent = `${angle.toFixed(1)}°`;
    hud.classList.add('hud-visible');

    if (window.hudTimeout) clearTimeout(window.hudTimeout);
    window.hudTimeout = setTimeout(() => {
      hud.classList.remove('hud-visible');
    }, 2800);
  }

  if (testBtn) {
    testBtn.addEventListener('click', () => {
      triggerHUD(80.0);
    });
  }

  // Listen for actual Option + Command + S on keyboard
  window.addEventListener('keydown', (e) => {
    if (e.altKey && e.metaKey && e.code === 'KeyS') {
      e.preventDefault();
      triggerHUD(80.0);
    }
  });
}

/**
 * 5. Scroll-driven Animations & Fallback
 */
function initScrollAnimations() {
  // Check for CSS scroll-driven animation support
  const supportsCSSScrollTimeline = CSS.supports && CSS.supports('(animation-timeline: view()) and (animation-range: entry)');

  if (!supportsCSSScrollTimeline) {
    const observer = new IntersectionObserver((entries) => {
      entries.forEach(entry => {
        if (entry.isIntersecting) {
          entry.target.classList.add('is-visible');
        }
      });
    }, {
      threshold: 0.15,
      rootMargin: '0px 0px -40px 0px'
    });

    document.querySelectorAll('.animate-on-scroll').forEach(el => {
      observer.observe(el);
    });
  }
}

function escapeHTML(str) {
  return str.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}
