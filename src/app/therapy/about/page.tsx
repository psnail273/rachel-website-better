import type { Metadata } from "next";
import Image from "next/image";

import { images } from "../../../lib/images";

export const metadata: Metadata = {
  title: "About Me",
  description:
    "Rachel Siegel is a psychotherapist who works with high-achieving adolescents and adults on perfectionism, anxiety, imposter syndrome, identity and burnout, drawing on ACT and Compassion Focused Therapy.",
};

export default function AboutPage() {
  const headshot = images["headshot-therapist"];
  return (
    <div className="max-w-3xl mx-auto space-y-8">
      <h1 className="font-serif text-4xl text-heading">About Me</h1>
      <div className="flex flex-col gap-6 md:flex-row md:items-start">
        <Image
          src={headshot.src}
          alt={headshot.alt}
          width={headshot.width}
          height={headshot.height}
          className="w-40 md:w-56 h-auto shrink-0 rounded-lg"
        />
        <div className="space-y-4">
          <p>
            I believe every person holds the power to transform their life. It
            is my honor to be a part of that journey, helping empower my clients
            with the tools they need to build a more connected, joyful, and
            meaningful life.
          </p>
          <p>
            My background as a classical musician may, at first glance, appear
            to be unrelated to my work as a psychotherapist. But the insights I
            gained from this industry regarding self-inquiry, psychology, body
            awareness, and teamwork are highly applicable to therapeutic work
            and growth.
          </p>
          <p>
            Because of this background, I am especially passionate about working
            with high-achieving adolescents and adults, especially those
            struggling with maladaptive perfectionism. I also specialize in
            several related concerns, including:
          </p>
          <ul className="list-disc pl-6 space-y-1">
            <li>
              Anxiety, chronic stress, and feeling constantly &quot;on&quot;
            </li>
            <li>Self-doubt and imposter syndrome</li>
            <li>Identity development</li>
            <li>Depression and burnout</li>
            <li>Work life balance/relationship issues</li>
            <li>Eating and body image concerns</li>
          </ul>
          <p>
            In my sessions, I combine a warm, empathetic approach with
            evidence-based strategies. I draw especially upon ACT (Acceptance
            &amp; Commitment Therapy) and CFT (Compassion Focused Therapy), both
            of which can help you develop flexibility in the face of adversity
            and build an authentic, values-driven life. I believe compassion,
            vulnerability, and having a safe space to just &quot;be&quot; are at
            the root of healing, and I look forward to providing that space for
            you.
          </p>
        </div>
      </div>
      <figure className="border-l-4 border-accent pl-4">
        <blockquote className="font-serif text-2xl italic">
          Let everything happen to you: beauty and terror. Just keep going. No
          feeling is final.
        </blockquote>
        <figcaption className="text-accent">
          — Rainer Maria Rilke, <cite>Letters to a Young Poet</cite>
        </figcaption>
      </figure>
    </div>
  );
}
