/**
 * MacHinge — Real-time Scroll-Driven MacBook Lid Physics Controller
 * Maps vertical scroll distance through each effect track directly to
 * 3D rotateX perspective and shader intensity layers.
 */

(function () {
  'use strict';

  const sections = document.querySelectorAll('.scroll-effect-section');
  if (!sections.length) return;

  let ticking = false;

  function updateLidPositions() {
    const vh = window.innerHeight;
    const stickyTop = 70; // Matches sticky top: 70px

    sections.forEach((section) => {
      const rect = section.getBoundingClientRect();
      const trackHeight = section.offsetHeight;
      const scrollableDist = trackHeight - vh + stickyTop;

      let progress = 0;

      if (rect.top <= stickyTop) {
        // We have started scrolling through the track
        progress = (stickyTop - rect.top) / scrollableDist;
        progress = Math.max(0, Math.min(1, progress));
      } else {
        progress = 0;
      }

      // If user scrolled past the section completely, clamp to 1
      if (rect.bottom <= vh) {
        progress = 1;
      }

      // Smooth step easing for natural physical hinge resistance
      const naturalProgress = Math.pow(progress, 1.12);

      // Lid closes from 0deg (upright open) to -65deg (closing down in front toward the base lip)
      const lidAngle = (-naturalProgress * 65).toFixed(1) + 'deg';

      // 1. Luminous Wake & Fold Glow variables:
      // Metal: glowTiming = pow(smoothstep(0.12, 1.0, p), 1.35)
      const glowProg = Math.max(0, (naturalProgress - 0.12) / 0.88);
      const glowTiming = Math.pow(glowProg, 1.35);
      // Cascading light sweep flowing down across fold horizon: 1.0 - (0.55 * p)
      const flowPos = ((1.0 - 0.55 * naturalProgress) * 100).toFixed(1) + '%';

      // 2. Apple Frosted Glass variables:
      // Metal: 13-tap Poisson blur radius 0.0075 * pow(p, 0.80)
      const glassBlur = (Math.pow(naturalProgress, 0.8) * 26).toFixed(1) + 'px';
      const glassOpacity = Math.pow(naturalProgress, 0.75).toFixed(3);

      // 3. Magnetic Lens Distortion variables:
      // Metal: lensTiming = pow(smoothstep(0.12, 1.0, p), 1.25)
      const lensProg = Math.max(0, (naturalProgress - 0.12) / 0.88);
      const lensTiming = Math.pow(lensProg, 1.25).toFixed(3);

      section.style.setProperty('--lid-rotate', lidAngle);
      section.style.setProperty('--lid-fold', naturalProgress.toFixed(3));
      section.style.setProperty('--glow-intensity', glowTiming.toFixed(3));
      section.style.setProperty('--flow-pos', flowPos);
      section.style.setProperty('--glass-blur', glassBlur);
      section.style.setProperty('--glass-opacity', glassOpacity);
      section.style.setProperty('--lens-timing', lensTiming);
    });

    ticking = false;
  }

  function onScroll() {
    if (!ticking) {
      window.requestAnimationFrame(updateLidPositions);
      ticking = true;
    }
  }

  window.addEventListener('scroll', onScroll, { passive: true });
  window.addEventListener('resize', onScroll, { passive: true });

  // Smooth scrolling for in-page anchors (e.g. effect pill buttons, note sticker)
  function bindSmoothAnchors() {
    document.querySelectorAll('a[href^="#"]').forEach(anchor => {
      if (anchor.dataset.smoothBound) return;
      anchor.dataset.smoothBound = 'true';
      anchor.addEventListener('click', function (e) {
        const targetId = this.getAttribute('href');
        if (!targetId || targetId === '#') return;
        const target = document.querySelector(targetId);
        if (target) {
          e.preventDefault();
          target.scrollIntoView({ behavior: 'smooth' });
          if (history.pushState) {
            history.pushState(null, '', targetId);
          }
        }
      });
    });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', bindSmoothAnchors);
  } else {
    bindSmoothAnchors();
  }

  // Hide sticky note button when viewing the developer note section
  function initStickerObserver() {
    const devNoteSection = document.getElementById('developer-note');
    const noteSticker = document.querySelector('.hero-note-sticker');
    if (devNoteSection && noteSticker && 'IntersectionObserver' in window) {
      const observer = new IntersectionObserver((entries) => {
        entries.forEach(entry => {
          if (entry.isIntersecting) {
            noteSticker.classList.add('sticker-hidden');
          } else {
            noteSticker.classList.remove('sticker-hidden');
          }
        });
      }, { threshold: 0.05 });
      observer.observe(devNoteSection);
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initStickerObserver);
  } else {
    initStickerObserver();
  }

  // Initial calculation on load
  document.addEventListener('DOMContentLoaded', updateLidPositions);
  updateLidPositions();
})();
