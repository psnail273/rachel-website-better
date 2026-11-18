import type { Metadata } from "next";
import Image from "next/image";
import Link from "next/link";
import { images } from "../../lib/images";
import { tieLabel } from "../../lib/tie";
import { Cluster, PageShell, Section } from "../_components/layout/components";

export const metadata: Metadata = {
  title: {
    absolute:
      "Rachel Siegel · Psychotherapist, clarinetist and recorder player",
  },
  description:
    "Rachel Siegel is a licensed psychotherapist, clarinetist and recorder player. Find her therapy practice, her performances and her upcoming concerts.",
};

export default function Home() {
  const hero = images["hero-mountain-lake"];
  return (
    <Section bleed labelledBy="hero-heading">
      <Image
        src={hero.src}
        alt={hero.alt}
        width={hero.width}
        height={hero.height}
        preload
      />
      <div data-hero-scrim="" aria-hidden="true" />
      <PageShell>
        <h1 id="hero-heading" className="type-display">
          Rachel Siegel
        </h1>
        <p className="type-hero-tag">
          {tieLabel("Licensed psychotherapist, clarinetist, recorder player")}
        </p>
        <Cluster align="center">
          <Link
            href="/therapy/about"
            data-hero-button=""
            className="type-button"
          >
            Therapy
          </Link>
          <Link
            href="/performing/bio"
            data-hero-button=""
            className="type-button"
          >
            Performing
          </Link>
        </Cluster>
      </PageShell>
    </Section>
  );
}
