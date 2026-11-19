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
    src: "/images/hero-mountain-lake.jpg",
    alt: "Snow-capped mountains glowing pink at sunset above a still lake",
    width: 2600,
    height: 1736,
  },
  "headshot-therapist": {
    src: "/images/headshot-therapist.jpg",
    alt: "Rachel Siegel in glasses and a navy tee, seated outdoors",
    width: 874,
    height: 1184,
  },
  "headshot-clarinet": {
    src: "/images/headshot-clarinet.jpg",
    alt: "Rachel Siegel holding her clarinet among white blossoming trees",
    width: 684,
    height: 922,
  },
  "headshot-recorder": {
    src: "/images/headshot-recorder.jpg",
    alt: "Rachel Siegel holding a wooden recorder among pink cherry blossoms",
    width: 716,
    height: 998,
  },
};
