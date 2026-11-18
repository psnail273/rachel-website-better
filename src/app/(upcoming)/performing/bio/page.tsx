import type { Metadata } from "next";
import Image from "next/image";
import Link from "next/link";

import { images } from "../../../../lib/images";
import { Stack } from "../../../_components/layout/components";

export const metadata: Metadata = {
  title: "Bio",
  description:
    "Rachel Siegel is a clarinetist and recorder player on modern and historical instruments, a former member of the United States Marine Band, now based in St. Louis.",
};

export default function BioPage() {
  const headshot = images["headshot-clarinet"];
  return (
    <Stack space="block" className="w-full max-w-5xl self-center">
      <h1 className="font-serif text-4xl text-heading">Bio</h1>
      <Stack space="heading" className="md:flex-row md:items-start">
        <Stack space="flow" className="md:w-3/5">
          <p>
            As a performer of modern and historical wind instruments, Rachel
            Siegel defies conventional classifications. Across 34 states and for
            more than two decades, she has played music that spans a millennium,
            from orchestral works to ancient folk songs, on various eras of
            clarinets and recorders—all reflecting her eclectic musical
            interests and experiences.
          </p>
          <p>
            From 2013-2017, Rachel served as a clarinetist in &quot;The
            President&apos;s Own&quot; United States Marine Band in Washington,
            DC. In addition to her duties as a clarinetist and ceremonial
            musician, Rachel had the opportunity to perform Vivaldi&apos;s
            Recorder Concerto in C minor with &quot;The President&apos;s
            Own&quot; Chamber Orchestra. Since then, Rachel has performed (on
            clarinets of all sizes) with the St. Louis Symphony Orchestra,
            Washington National Opera Orchestra, Baltimore Symphony, and the
            Richmond Symphony. Additionally, since its debut in 2016, she has
            played recorder in the Harry Potter in Concert series with several
            orchestras, including the Philadelphia Orchestra and National
            Symphony Orchestra. Now based in her hometown of St. Louis, MO,
            Rachel is a regularly featured artist with Early Music Missouri and
            frequently collaborates with the Collegium Vocale of St. Louis and
            American Kantorei concert series.
          </p>
          <p>
            An advocate for the psychological wellbeing of performers and
            pedagogues within the field of classical music, Rachel teaches
            workshops to musicians of all ages on performance psychology and
            audition preparation. In all, thousands of students have worked with
            Rachel throughout the United States, including at universities such
            as Texas A&amp;M, West Virginia University, and University of
            Missouri - St. Louis; at advanced youth programs like the St. Louis
            Symphony Youth Orchestra; and at dozens of schools across the
            country.
          </p>
          <p>
            Rachel received degrees in clarinet performance from the University
            of Minnesota, University of Southern California, and Rice
            University. Her primary teachers include Burt Hara, Yehuda Gilad and
            Tina Ward (clarinet), and Clea Galhano (recorder). Additionally, in
            2020 she was awarded a Fulbright to study in Helsinki, Finland. In
            addition to performing, you can read about Rachel&apos;s work as a
            psychotherapist in{" "}
            <Link href="/therapy/about" className="underline">
              the therapy section of this website
            </Link>
            .
          </p>
        </Stack>
        <Image
          src={headshot.src}
          alt={headshot.alt}
          width={headshot.width}
          height={headshot.height}
          className="w-48 md:w-2/5 h-auto shrink-0 rounded-lg"
        />
      </Stack>
    </Stack>
  );
}
