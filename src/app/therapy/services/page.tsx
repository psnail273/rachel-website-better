import type { Metadata } from "next";

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

const listClass = "list-disc pl-6 space-y-1";
const h2Class = "font-serif text-2xl text-heading mb-3";

function Items({ items }: { items: string[] }) {
  return (
    <ul className={listClass}>
      {items.map((item) => (
        <li key={item}>{item}</li>
      ))}
    </ul>
  );
}

export default function ServicesPage() {
  return (
    <div className="max-w-3xl mx-auto space-y-8">
      <h1 className="font-serif text-4xl text-heading">Services</h1>
      <p>
        I provide individual therapy to adults and adolescents (aged 14 and up)
        through a group practice, Wellness Alliance Counseling and
        Psychotherapy. In-person therapy takes place at our office in Clayton,
        MO. For telehealth, clients must be in Missouri or Illinois.
      </p>
      <figure className="border-l-4 border-accent pl-4">
        <blockquote className="font-serif text-2xl italic">
          {'And you may ask yourself, "Well, how did I get here?"'}
        </blockquote>
        <figcaption className="mt-2 text-muted">— Talking Heads</figcaption>
      </figure>
      <section>
        <h2 className={h2Class}>You might be struggling with…</h2>
        <Items items={struggling} />
      </section>
      <section>
        <h2 className={h2Class}>Therapy may help you…</h2>
        <Items items={help} />
      </section>
      <section className="space-y-3">
        <h2 className={h2Class}>A note on perfectionism…</h2>
        <p>
          {
            "Contrary to common belief, perfectionism usually doesn't help us achieve our goals. More often, it keeps us small, distracted by the fear of making a mistake or seeming messy. Perfectionism can cause:"
          }
        </p>
        <Items items={perfectionism} />
        <p>
          What if you could let that all go, and still be successful, loved and
          accepted as you are?
        </p>
      </section>
    </div>
  );
}
