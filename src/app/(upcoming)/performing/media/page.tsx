import type { Metadata } from "next";
import { images } from "@/lib/images";
import { siteConfig } from "@/lib/site-config";
import {
  PhotoPage,
  Prose,
  Rows,
  SectionHeading,
  Stack,
  Switcher,
} from "../../../_components/layout/components";
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
  ] as const;
  const recordings = [
    "Brahms Clarinet Quintet, mvmt. 3",
    "Brahms Clarinet Quintet, mvmt. 4",
    "Chamber Music St. Louis radio broadcast, September 2025",
  ];
  return (
    <PhotoPage
      headingId="media-heading"
      title="Media"
      image={images["headshot-recorder"]}
    >
      <Stack space="block">
        <div>
          <SectionHeading level={2}>Video</SectionHeading>
          <Switcher kind="pair">
            {[
              <VideoCard
                key={videos[0].id}
                id={videos[0].id}
                title={videos[0].title}
              />,
              <VideoCard
                key={videos[1].id}
                id={videos[1].id}
                title={videos[1].title}
              />,
            ]}
          </Switcher>
        </div>
        <div>
          <SectionHeading level={2}>Audio</SectionHeading>
          <Prose align="start">
            <Rows
              rows={recordings.map((text) => ({
                text,
                status: "Coming soon",
              }))}
            />
            <p>
              For access to the full Brahms Quintet performance, contact Rachel
              via{"\u00a0"}
              <a href={`mailto:${siteConfig.email}`}>email</a>.
            </p>
          </Prose>
        </div>
      </Stack>
    </PhotoPage>
  );
}
