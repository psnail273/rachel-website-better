import type { Metadata } from "next";
import { Stack } from "../../_components/layout/components";

export const metadata: Metadata = {
  title: "Education and Training",
  description:
    "Rachel Siegel's education and training: a Master of Social Work from Saint Louis University, degrees in music performance, and specialized training in ACT, Compassion Focused Therapy, DBT and more.",
};

export default function EducationPage() {
  const education = [
    "MSW, Master of Social Work — Saint Louis University",
    "MM, Music Performance — University of Southern California",
    "BM, Music Performance — University of Minnesota – Twin Cities",
    "Clarinet Performance, Rice University",
  ];
  const training = [
    "RO-DBT (Radically Open Dialectical Behavioral Therapy) Level 1",
    "Compassion Focused Therapy (Drs. Dennis Church and Paul Gilbert, Psychwire)",
    "Treating Adult ADHD (Margaret Dawson)",
    "Body Perfectionism: Innovative Tools from DBT, CBT, ACT ERP and More to Improve Self-Worth (Deanna Smith, PESI)",
    "Certification Training in DBT (Alexa Mulee, C-DBT)",
    "Understanding Adolescent Eating Disorders: Foundations in Family-Based Treatment (Washington University, St. Louis)",
    "Shamelessly Imperfect: A guide to Help Your Clients Break Free from Perfectionism (Milly Feliz, PESI)",
    "ACT 2-Day Intensive (Dr. DJ Moran)",
    "Mindfulness Certification Course, 2-Day Intensive (Dr. Debra Premashakti Alvis)",
    "Food and Mood: A Therapist's Guide to the Role of Nutrition in Mental Health (Kathleen Zamperini)",
  ];
  return (
    <Stack space="block" className="w-full max-w-3xl self-center">
      <h1 className="font-serif text-4xl text-heading">
        Education and Training
      </h1>
      <Stack space="tight" as="section">
        <h2 className="font-serif text-2xl text-heading">
          Education &amp; Credentials
        </h2>
        <Stack space="tight" as="ul" className="list-disc list-inside">
          {education.map((e) => (
            <li key={e}>{e}</li>
          ))}
        </Stack>
      </Stack>
      <Stack space="tight" as="section">
        <h2 className="font-serif text-2xl text-heading">
          Specialized Training
        </h2>
        <Stack space="tight" as="ul" className="list-disc list-inside">
          {training.map((t) => (
            <li key={t}>{t}</li>
          ))}
        </Stack>
      </Stack>
    </Stack>
  );
}
