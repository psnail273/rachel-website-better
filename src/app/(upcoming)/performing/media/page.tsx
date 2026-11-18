import type { Metadata } from "next";
import Image from "next/image";
import { images } from "@/lib/images";
import { siteConfig } from "@/lib/site-config";
import { Stack } from "../../../_components/layout/components";
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
    <Stack space="block" className="w-full max-w-5xl self-center">
      <h1 className="font-serif text-4xl text-heading">Media</h1>
      <Stack space="block" className="md:flex-row md:items-start">
        <div className="md:w-1/3">
          <Image
            src={image.src}
            alt={image.alt}
            width={image.width}
            height={image.height}
            className="w-full h-auto rounded-lg"
          />
        </div>
        <Stack space="block" className="md:w-2/3">
          <Stack space="flow" as="section">
            <h2 className="font-serif text-2xl text-heading">Video</h2>
            {videos.map((video) => (
              <VideoCard key={video.id} id={video.id} title={video.title} />
            ))}
          </Stack>
          <Stack space="flow" as="section">
            <h2 className="font-serif text-2xl text-heading">Audio</h2>
            <Stack space="tight" as="ul">
              {recordings.map((title) => (
                <li
                  key={title}
                  className="flex flex-wrap items-center justify-between"
                >
                  <span>{title}</span>
                  <span className="text-muted">Coming soon</span>
                </li>
              ))}
            </Stack>
            <p>
              For access to the full Brahms Quintet performance, contact Rachel
              via <a href={`mailto:${siteConfig.email}`}>email</a>.
            </p>
          </Stack>
        </Stack>
      </Stack>
    </Stack>
  );
}
