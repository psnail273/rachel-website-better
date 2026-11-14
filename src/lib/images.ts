export type ImageKey =
  | "hero-mountain-lake"
  | "headshot-therapist"
  | "headshot-clarinet"
  | "headshot-recorder";

export type SiteImage = {
  src: string;
  alt: string;
  width: number;
  height: number;
};

export const images: Record<ImageKey, SiteImage> = {
  "hero-mountain-lake": {
    src: "/images/hero-mountain-lake.svg",
    alt: "Snow-capped mountains glowing pink at sunset above a still lake",
    width: 1920,
    height: 1280,
  },
  "headshot-therapist": {
    src: "/images/headshot-therapist.svg",
    alt: "Rachel Siegel in glasses and a navy tee, seated outdoors",
    width: 874,
    height: 1184,
  },
  "headshot-clarinet": {
    src: "/images/headshot-clarinet.svg",
    alt: "Rachel Siegel holding her clarinet among white blossoming trees",
    width: 768,
    height: 1024,
  },
  "headshot-recorder": {
    src: "/images/headshot-recorder.svg",
    alt: "Rachel Siegel holding a wooden recorder among pink cherry blossoms",
    width: 1471,
    height: 2048,
  },
};
