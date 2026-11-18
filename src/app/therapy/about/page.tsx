import type { Metadata } from "next";

import { images } from "../../../lib/images";
import { tieLabel, tieLast } from "../../../lib/tie";
import {
  Lead,
  List,
  PhotoPage,
  Prose,
  PullQuote,
  Section,
  Stack,
} from "../../_components/layout/components";

export const metadata: Metadata = {
  title: "About Me",
  description:
    "Rachel Siegel is a psychotherapist who works with high-achieving adolescents and adults on perfectionism, anxiety, imposter syndrome, identity and burnout, drawing on ACT and Compassion Focused Therapy.",
};

const SPECIALTIES = [
  "Anxiety, chronic stress, and feeling constantly “on”",
  "Self-doubt and imposter syndrome",
  "Identity development",
  "Depression and burnout",
  "Work life balance/relationship issues",
  "Eating and body image concerns",
];

export default function AboutPage() {
  return (
    <>
      <PhotoPage
        headingId="about-heading"
        title="About Me"
        image={images["headshot-therapist"]}
      >
        <Stack space="heading">
          <Lead rule>
            {tieLast(
              "I believe every person holds the power to transform their life.",
            )}
          </Lead>
          <Prose align="start">
            <p>
              {tieLast(
                "It is my honor to be a part of that journey, helping empower my clients with the tools they need to build a more connected, joyful, and meaningful life.",
              )}
            </p>
            <p>
              {tieLast(
                "My background as a classical musician may, at first glance, appear to be unrelated to my work as a psychotherapist. But the insights I gained from this industry regarding self-inquiry, psychology, body awareness, and teamwork are highly applicable to therapeutic work and growth.",
              )}
            </p>
            <p>
              {tieLast(
                "Because of this background, I am especially passionate about working with high-achieving adolescents and adults, especially those struggling with maladaptive perfectionism. I also specialize in several related concerns, including:",
              )}
            </p>
            <List variant="panel" items={SPECIALTIES} />
            <p>
              {tieLast(
                "In my sessions, I combine a warm, empathetic approach with evidence-based strategies. I draw especially upon ACT (Acceptance & Commitment Therapy) and CFT (Compassion Focused Therapy), both of which can help you develop flexibility in the face of adversity and build an authentic, values-driven life. I believe compassion, vulnerability, and having a safe space to just “be” are at the root of healing, and I look forward to providing that space for you.",
              )}
            </p>
          </Prose>
        </Stack>
      </PhotoPage>
      <Section label="A line from Rilke">
        <PullQuote
          quote="Let everything happen to you: beauty and terror. Just keep going. No feeling is final."
          caption={
            <>
              Rainer Maria Rilke,{" "}
              <cite>{tieLabel("Letters to a Young Poet")}</cite>
            </>
          }
        />
      </Section>
    </>
  );
}
