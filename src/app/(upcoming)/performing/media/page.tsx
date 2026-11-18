import type { Metadata } from "next";
import Image from "next/image";
import { images } from "@/lib/images";
import { siteConfig } from "@/lib/site-config";
import { VideoCard } from "./video-card";

export const metadata: Metadata = {
  title: "Media",
  description:
    "Videos and recordings of Rachel Siegel's performances on recorder and clarinet, with her upcoming concerts.",
};

export default function MediaPage() {
  const videos = [
    { id: "VdwOjCyVsSE", title: "“Passacaille” by Jacques-Martin Hotteterre" },
    {
      id: "DZA9Wi6KzWY",
      title: "“Aria sopra La Bergamasca” by Marco Uccellini",
    },
  ];
  const recordings = [
    "Brahms Clarinet Quintet, mvmt. 3",
    "Brahms Clarinet Quintet, mvmt. 4",
    "Chamber Music St. Louis radio broadcast, September 2025",
  ];
  const image = images["headshot-recorder"];
  return (
    <div className="max-w-5xl mx-auto space-y-8">
      <h1 className="font-serif text-4xl text-heading">Media</h1>
      <div className="flex flex-col gap-8 md:flex-row md:items-start">
        <div className="md:w-1/3">
          <Image
            src={image.src}
            alt={image.alt}
            width={image.width}
            height={image.height}
            className="w-full h-auto rounded-lg"
          />
        </div>
        <div className="md:w-2/3 space-y-10">
          <section className="space-y-4">
            <h2 className="font-serif text-2xl text-heading">Video</h2>
            {videos.map((video) => (
              <VideoCard key={video.id} id={video.id} title={video.title} />
            ))}
          </section>
          <section className="space-y-4">
            <h2 className="font-serif text-2xl text-heading">Audio</h2>
            <ul className="space-y-2">
              {recordings.map((title) => (
                <li key={title} className="flex flex-wrap items-center gap-3">
                  <span>{title}</span>
                  <span className="rounded-full border border-accent px-2 py-0.5 text-xs text-accent-text">
                    Coming soon
                  </span>
                </li>
              ))}
            </ul>
            <p>
              For access to the full Brahms Quintet performance, contact Rachel
              via{" "}
              <a
                href={`mailto:${siteConfig.email}`}
                className="underline underline-offset-4 hover:text-accent focus-visible:text-accent"
              >
                email
              </a>
              .
            </p>
          </section>
        </div>
      </div>
    </div>
  );
}
