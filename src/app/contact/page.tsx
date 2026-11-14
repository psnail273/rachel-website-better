import type { Metadata } from "next";
import { siteConfig } from "@/lib/site-config";

export const metadata: Metadata = {
  title: "Contact",
  description:
    "How to reach Rachel Siegel: therapy inquiries through Wellness Alliance, and email for performances, workshops and anything else.",
};

export default function ContactPage() {
  const linkClass =
    "underline underline-offset-4 hover:text-accent focus-visible:text-accent";
  return (
    <div className="max-w-3xl mx-auto space-y-8">
      <h1 className="font-serif text-4xl text-heading">Contact</h1>
      <p>
        For therapy, please reach out through{" "}
        <a
          href={siteConfig.wellnessAllianceUrl}
          target="_blank"
          rel="noopener noreferrer"
          className={linkClass}
        >
          Wellness Alliance
        </a>
        .
      </p>
      <p>
        For performances, workshops or anything else,{" "}
        <a href={`mailto:${siteConfig.email}`} className={linkClass}>
          email me directly
        </a>
        .
      </p>
    </div>
  );
}
