"use client";

import Image from "next/image";
import { useState } from "react";
import { tieLabel } from "../../../../lib/tie";

const ALLOW =
  "accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share";

export function VideoCard({ id, title }: { id: string; title: string }) {
  const [playing, setPlaying] = useState(false);
  return (
    <figure data-video="">
      {playing ? (
        <iframe
          data-video-frame=""
          src={`https://www.youtube-nocookie.com/embed/${id}?autoplay=1`}
          title={title}
          allow={ALLOW}
          allowFullScreen
        />
      ) : (
        <button
          type="button"
          data-video-frame=""
          aria-label={`Play ${title}`}
          onClick={() => {
            setPlaying(true);
          }}
        >
          <Image
            src={`https://i.ytimg.com/vi/${id}/hqdefault.jpg`}
            alt={`Still from the video of ${title}`}
            width={480}
            height={360}
            unoptimized
          />
          <svg
            data-play=""
            aria-hidden="true"
            width="56"
            height="56"
            viewBox="0 0 56 56"
          >
            <circle cx="28" cy="28" r="28" />
            <path d="M22 17v22l18-11z" />
          </svg>
        </button>
      )}
      <figcaption data-card-title="" className="type-card-title">
        {tieLabel(title)}
      </figcaption>
    </figure>
  );
}
