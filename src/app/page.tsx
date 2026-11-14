import type { Metadata } from "next";
import Image from "next/image";
import { images } from "../lib/images";

export const metadata: Metadata = {
  title: {
    absolute: "Rachel Siegel · Psychotherapist, clarinetist and recorder player",
  },
  description:
    "Rachel Siegel is a licensed psychotherapist, clarinetist and recorder player. Find her therapy practice, her performances and her upcoming concerts.",
};

export default function Home() {
  const hero = images["hero-mountain-lake"];
  return (
    <section className="relative -mx-6 -mt-8 flex min-h-[70vh] items-center justify-center overflow-hidden">
      <Image
        src={hero.src}
        alt={hero.alt}
        width={hero.width}
        height={hero.height}
        preload
        className="absolute inset-0 h-full w-full scale-110 object-cover blur-sm"
      />
      <div
        aria-hidden="true"
        className="absolute inset-0 bg-gradient-to-b from-[#2e1a47]/50 to-[#1f2a4d]/50"
      />
      <div className="relative px-6 text-center">
        <h1 className="text-5xl text-background! sm:text-6xl">Rachel Siegel</h1>
        <p className="mt-4 text-xl text-background">
          Licensed psychotherapist, clarinetist, recorder player
        </p>
      </div>
    </section>
  );
}
