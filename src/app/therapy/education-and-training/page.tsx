import type { Metadata } from "next";
import {
  Rows,
  Section,
  SectionHeading,
  Stack,
  Switcher,
} from "../../_components/layout/components";

export const metadata: Metadata = {
  title: "Education and Training",
  description:
    "Rachel Siegel's education and training: a Master of Social Work from Saint Louis University, degrees in music performance, and specialized training in ACT, Compassion Focused Therapy, DBT and more.",
};

const education = [
  { text: "MSW, Master of Social Work — Saint Louis University" },
  { text: "MM, Music Performance — University of Southern California" },
  { text: "BM, Music Performance — University of Minnesota – Twin Cities" },
  { text: "Clarinet Performance, Rice University" },
];

const training = [
  { text: "RO-DBT (Radically Open Dialectical Behavioral Therapy) Level 1" },
  {
    text: "Compassion Focused Therapy (Drs. Dennis Church and Paul Gilbert, Psychwire)",
  },
  { text: "Treating Adult ADHD (Margaret Dawson)" },
  {
    text: "Body Perfectionism: Innovative Tools from DBT, CBT, ACT ERP and More to Improve Self-Worth (Deanna Smith, PESI)",
  },
  { text: "Certification Training in DBT (Alexa Mulee, C-DBT)" },
  {
    text: "Understanding Adolescent Eating Disorders: Foundations in Family-Based Treatment (Washington University, St. Louis)",
  },
  {
    text: "Shamelessly Imperfect: A guide to Help Your Clients Break Free from Perfectionism (Milly Feliz, PESI)",
  },
  { text: "ACT 2-Day Intensive (Dr. DJ Moran)" },
  {
    text: "Mindfulness Certification Course, 2-Day Intensive (Dr. Debra Premashakti Alvis)",
  },
  {
    text: "Food and Mood: A Therapist's Guide to the Role of Nutrition in Mental Health (Kathleen Zamperini)",
  },
];

export default function EducationPage() {
  return (
    <Section labelledBy="education-heading">
      <SectionHeading level={1} id="education-heading">
        Education and Training
      </SectionHeading>
      <Stack space="block">
        <Switcher kind="label">
          <SectionHeading level={2}>Education &amp; Credentials</SectionHeading>
          <Rows rows={education} />
        </Switcher>
        <Switcher kind="label">
          <SectionHeading level={2}>Specialized Training</SectionHeading>
          <Rows rows={training} />
        </Switcher>
      </Stack>
    </Section>
  );
}
