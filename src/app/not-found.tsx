import Link from "next/link";
import type { ReactNode } from "react";
import { tieLabel, tieLast } from "../lib/tie";
import {
  Center,
  Lead,
  Section,
  SectionHeading,
  Stack,
} from "./_components/layout/components";

const BUTTON_CLASS =
  "type-button inline-flex h-14 w-50 max-w-full items-center justify-center self-center border border-heading text-heading transition-colors duration-150 ease-[cubic-bezier(0.2,0.7,0.2,1)] hover:bg-heading hover:text-bg";

export default function NotFound(): ReactNode {
  return (
    <Section labelledBy="not-found-heading">
      <Center>
        <SectionHeading level={1} id="not-found-heading">
          This page wandered off
        </SectionHeading>
        <Stack space="heading">
          <Lead>{tieLast("The page you’re looking for isn’t here.")}</Lead>
          <Link href="/" className={BUTTON_CLASS}>
            {tieLabel("Back to Home")}
          </Link>
        </Stack>
      </Center>
    </Section>
  );
}
