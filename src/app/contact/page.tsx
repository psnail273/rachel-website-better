import type { Metadata } from "next";
import { siteConfig } from "@/lib/site-config";
import { tieLast } from "../../lib/tie";
import { ContactForm } from "../_components/contact-form";
import {
  Center,
  Lead,
  Section,
  SectionHeading,
  Stack,
} from "../_components/layout/components";
import { sendMessage } from "./actions";

export const metadata: Metadata = {
  title: "Contact",
  description:
    "How to reach Rachel Siegel: therapy inquiries through Wellness Alliance, and email for performances, workshops and anything else.",
};

export default function ContactPage() {
  return (
    <Section labelledBy="contact-heading">
      <Center>
        <SectionHeading level={1} id="contact-heading">
          Contact
        </SectionHeading>
        <Stack space="block">
          <Stack space="flow">
            <Lead>
              For therapy, please reach out through{" "}
              <a
                href={siteConfig.wellnessAllianceUrl}
                target="_blank"
                rel="noopener noreferrer"
              >
                {tieLast("Wellness Alliance")}
              </a>
              .
            </Lead>
            <Lead>
              For performances, workshops or anything else,{" "}
              <a href={`mailto:${siteConfig.email}`}>
                {tieLast("email me directly")}
              </a>
              .
            </Lead>
          </Stack>
          <div>
            <SectionHeading level={2} id="contact-form-heading">
              Send a message
            </SectionHeading>
            <ContactForm sendAction={sendMessage} />
          </div>
        </Stack>
      </Center>
    </Section>
  );
}
