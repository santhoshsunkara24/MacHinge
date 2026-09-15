/**
 * MacHinge Visual Effects Registry
 * 
 * All data in this file is strictly verified against MacHinge's Metal shaders
 * (Sources/MacHinge/Metal/Shaders.metal) and engine configuration (AppSettings.swift).
 * 
 * To add real demonstration videos later, simply replace `videoSrc: null` with the
 * relative or absolute path to your MP4/WebM video file (e.g. `videoSrc: "assets/videos/luminous-glow.mp4"`),
 * and optionally provide `posterSrc: "assets/videos/luminous-glow-poster.jpg"`.
 */

export const effectsData = [
  {
    id: "luminous-glow",
    name: "Luminous Wake & Fold Glow",
    badge: "Default Effect",
    tagline: "A gentle white glow travels across the hinge as the lid closes, leaving a subtle trail of light.",
    summary: "As your MacBook lid passes below the closing threshold, a soft volumetric light sweep awakens across the hinge crease and flows upward, reaching a dazzling pure white radiance before sleep.",
    behavior: "Micro-movements maintain a 100% sharp display. Below the trigger angle (~78°), progressive smooth white light illuminates the fold horizon. Near complete closure or instant wake, high-intensity flood bloom sweeps across the screen.",
    bestFor: "Cinematic lid movement, sleep/wake transitions, and dramatic visual feedback.",
    shaderDetails: [
      "Progressive smooth timing curve: pow(smoothstep(0.12, 1.0, progress), 1.35)",
      "Volumetric flood bloom peaking near clamshell sleep",
      "Dynamic angular velocity motion surge scaling up to +30%",
      "Adjustable Glow Radiance slider (20% to 200% in Settings)"
    ],
    videoSrc: null,
    posterSrc: null,
    aspectRatio: "16/10"
  },
  {
    id: "frosted-glass",
    name: "Duo Effect",
    badge: "Physical Optical Glass",
    tagline: "Physical optical depth-of-field shifts with the hinge, keeping the dock crystal clear while defocusing the top.",
    summary: "Simulates a physical optical glass panel with desktop raycasting and contact protection at the hinge.",
    behavior: "Keeps the bottom Dock 100% sharp while progressively defocusing content upward with distance-proportional optical scattering and radial chromatic dispersion.",
    bestFor: "Understated elegance, minimal distraction, and native optical depth-of-field.",
    shaderDetails: [
      "Fixed desktop plane raycast projection from stationary eye viewpoint",
      "Hinge contact clear zone protecting bottom 3.5%–20% (Dock in focus)",
      "17-tap Golden-Angle Poisson Disk bokeh kernel for optical defocus",
      "Radial chromatic dispersion and soft transmission curtain"
    ],
    videoSrc: null,
    posterSrc: null,
    aspectRatio: "16/10"
  },
  {
    id: "magnetic-lens",
    name: "Magnetic Lens Distortion",
    badge: "Kinetic Physics",
    tagline: "The screen subtly pulls toward the hinge in a smooth, magnetic motion.",
    summary: "Treats the MacBook's physical hinge as a gravitational singularity, deflecting desktop pixels with frame-dragging spacetime swirl and electromagnetic caustic rings.",
    behavior: "Creates a gravitational deflection field focused at the hinge pole. Physical angular velocity generates a rotational swirl, accompanied by differential RGB wavelength bending and Einstein ring caustic shimmers.",
    bestFor: "Expressive physics simulation, sci-fi aesthetic, and tactile kinetic feedback.",
    shaderDetails: [
      "Deflection field: fieldStrength / (distToPole * 2.0 + 0.30)",
      "Frame-dragging spacetime swirl tied to lid angular velocity",
      "Chromatic dispersion separating red, green, and blue optical wavelengths",
      "Dynamic Einstein ring caustics and magnetic halo flux along outer edges"
    ],
    videoSrc: null,
    posterSrc: null,
    aspectRatio: "16/10"
  }
];
