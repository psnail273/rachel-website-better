import type { Metadata } from "next";
import {
  Lead,
  List,
  Prose,
  PullQuote,
  Section,
  SectionHeading,
  Sidebar,
  Stack,
  Switcher,
} from "../../_components/layout/components";
import { tieLast } from "../../../lib/tie";

export const metadata: Metadata = {
  title: "Services",
  description:
    "Individual therapy for adults and adolescents in Clayton, MO, and by telehealth in Missouri and Illinois, with Rachel Siegel at Wellness Alliance Counseling and Psychotherapy.",
};

const struggling = [
  "Identity development",
  "Anxiety and stress management",
  "Maladaptive perfectionism",
  "Self-doubt and imposter syndrome",
  "Depression or burnout",
  "Disordered eating and body image concerns",
  "Work-life balance",
  "Relationship issues/setting boundaries",
];

const help = [
  "Manage stress and anxiety",
  "Reframe unhelpful beliefs",
  "Develop greater self worth and self-confidence",
  "Cope with uncomfortable emotions and situations",
  "Increase compassion for yourself and others",
  "Develop self-care strategies",
  "Learn and set healthier boundaries in relationships and with work",
  "Move through creative or career blocks with clarity",
  "Explore identity outside of work/art/achievement",
  "Create work/performances that have meaning and purpose.",
];

const perfectionism = [
  "Procrastination",
  "Shame",
  "Shutting down when emotional",
  "Imposter syndrome",
  "Obsession with achievement",
  "Chronic stress and burnout",
  "Frequent and intense anxiety of being perceived negatively.",
];

export default function ServicesPage() {
  return (
    <>
      <Section labelledBy="services-heading">
        <Sidebar
          side="trail"
          head={
            <SectionHeading level={1} id="services-heading">
              Services
            </SectionHeading>
          }
          aside={
            <PullQuote
              quote="And you may ask yourself, “Well, how did I get here?”"
              caption="Talking Heads"
            />
          }
        >
          <Prose align="start">
            <p>
              {tieLast(
                "I provide individual therapy to adults and adolescents (aged 14 and up) through a group practice, Wellness Alliance Counseling and Psychotherapy. In-person therapy takes place at our office in Clayton, MO. For telehealth, clients must be in Missouri or Illinois.",
              )}
            </p>
          </Prose>
        </Sidebar>
      </Section>
      <Section label="What therapy can help with">
        <Switcher kind="pair">
          <>
            <SectionHeading level={2}>
              You might be struggling with…
            </SectionHeading>
            <List variant="plain" items={struggling} />
          </>
          <>
            <SectionHeading level={2}>Therapy may help you…</SectionHeading>
            <List variant="plain" items={help} />
          </>
        </Switcher>
      </Section>
      <Section labelledBy="perfectionism-heading">
        <SectionHeading level={2} id="perfectionism-heading">
          A note on perfectionism…
        </SectionHeading>
        <Stack space="block">
          <Switcher kind="run">
            <Prose align="start">
              <p>
                {tieLast(
                  "Contrary to common belief, perfectionism usually doesn’t help us achieve our goals. More often, it keeps us small, distracted by the fear of making a mistake or seeming messy. Perfectionism can cause:",
                )}
              </p>
            </Prose>
            <List variant="plain" items={perfectionism} />
          </Switcher>
          <Prose align="center">
            <Lead>
              {tieLast(
                "What if you could let that all go, and still be successful, loved and accepted as you are?",
              )}
            </Lead>
          </Prose>
        </Stack>
      </Section>
    </>
  );
}
