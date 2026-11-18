"use client";

import { useState } from "react";

export function VideoCard({ id, title }: { id: string; title: string }) {
  const [playing, setPlaying] = useState(false);
  if (playing) {
    return (
      <iframe
        src={`https://www.youtube-nocookie.com/embed/${id}?autoplay=1`}
        title={title}
        allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share"
        allowFullScreen
        className="aspect-video w-full rounded-lg border-0"
      />
    );
  }
  return (
    <button
      type="button"
      aria-label={`Play ${title}`}
      onClick={() => {
        setPlaying(true);
      }}
      className="aspect-video w-full rounded-lg bg-poster text-on-image flex flex-col items-center justify-center gap-3 p-4 hover:opacity-90"
    >
      <svg
        aria-hidden="true"
        viewBox="0 0 48 48"
        className="size-14"
        fill="none"
      >
        <circle
          cx="24"
          cy="24"
          r="23"
          fill="currentColor"
          fillOpacity="0.25"
          stroke="currentColor"
          strokeWidth="2"
        />
        <path d="M20 16l14 8-14 8z" fill="currentColor" />
      </svg>
      <span className="font-serif text-lg text-center">{title}</span>
    </button>
  );
}
