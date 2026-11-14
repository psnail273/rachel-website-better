import type { Metadata } from "next";

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
    <div className="max-w-3xl mx-auto space-y-8">
      <h1 className="font-serif text-4xl text-heading">
        Education and Training
      </h1>
      <section>
        <h2 className="font-serif text-2xl text-heading mb-3">
          Education &amp; Credentials
        </h2>
        <ul className="list-disc pl-6 space-y-1">
          {education.map((e) => (
            <li key={e}>{e}</li>
          ))}
        </ul>
      </section>
      <section>
        <h2 className="font-serif text-2xl text-heading mb-3">
          Specialized Training
        </h2>
        <ul className="list-disc pl-6 space-y-1">
          {training.map((t) => (
            <li key={t}>{t}</li>
          ))}
        </ul>
      </section>
    </div>
  );
}
