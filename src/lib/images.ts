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
    alt: "",
    width: 0,
    height: 0,
  },
  "headshot-therapist": {
    src: "/images/headshot-therapist.svg",
    alt: "",
    width: 0,
    height: 0,
  },
  "headshot-clarinet": {
    src: "/images/headshot-clarinet.svg",
    alt: "",
    width: 0,
    height: 0,
  },
  "headshot-recorder": {
    src: "/images/headshot-recorder.svg",
    alt: "",
    width: 0,
    height: 0,
  },
};
