import type { Metadata } from "next";
import { siteConfig } from "@/lib/site-config";
import { Stack } from "../_components/layout/components";

export const metadata: Metadata = {
  title: "Contact",
  description:
    "How to reach Rachel Siegel: therapy inquiries through Wellness Alliance, and email for performances, workshops and anything else.",
};

export default function ContactPage() {
  return (
    <Stack space="block" className="w-full max-w-3xl self-center">
      <h1 className="font-serif text-4xl text-heading">Contact</h1>
      <p>
        For therapy, please reach out through{" "}
        <a
          href={siteConfig.wellnessAllianceUrl}
          target="_blank"
          rel="noopener noreferrer"
        >
          Wellness Alliance
        </a>
        .
      </p>
      <p>
        For performances, workshops or anything else,{" "}
        <a href={`mailto:${siteConfig.email}`}>email me directly</a>.
      </p>
    </Stack>
  );
}
