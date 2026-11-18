import type { Metadata } from "next";
import Link from "next/link";

import { images } from "../../../../lib/images";
import { tieLast } from "../../../../lib/tie";
import { PhotoPage, Prose } from "../../../_components/layout/components";

export const metadata: Metadata = {
  title: "Bio",
  description:
    "Rachel Siegel is a clarinetist and recorder player on modern and historical instruments, a former member of the United States Marine Band, now based in St. Louis.",
};

const PARAGRAPHS = [
  "As a performer of modern and historical wind instruments, Rachel Siegel defies conventional classifications. Across 34 states and for more than two decades, she has played music that spans a millennium, from orchestral works to ancient folk songs, on various eras of clarinets and recorders—all reflecting her eclectic musical interests and experiences.",
  "From 2013-2017, Rachel served as a clarinetist in “The President’s Own” United States Marine Band in Washington, DC. In addition to her duties as a clarinetist and ceremonial musician, Rachel had the opportunity to perform Vivaldi’s Recorder Concerto in C minor with “The President’s Own” Chamber Orchestra. Since then, Rachel has performed (on clarinets of all sizes) with the St. Louis Symphony Orchestra, Washington National Opera Orchestra, Baltimore Symphony, and the Richmond Symphony. Additionally, since its debut in 2016, she has played recorder in the Harry Potter in Concert series with several orchestras, including the Philadelphia Orchestra and National Symphony Orchestra. Now based in her hometown of St. Louis, MO, Rachel is a regularly featured artist with Early Music Missouri and frequently collaborates with the Collegium Vocale of St. Louis and American Kantorei concert series.",
  "An advocate for the psychological wellbeing of performers and pedagogues within the field of classical music, Rachel teaches workshops to musicians of all ages on performance psychology and audition preparation. In all, thousands of students have worked with Rachel throughout the United States, including at universities such as Texas A&M, West Virginia University, and University of Missouri - St. Louis; at advanced youth programs like the St. Louis Symphony Youth Orchestra; and at dozens of schools across the country.",
];

const LAST_BEFORE_LINK =
  "Rachel received degrees in clarinet performance from the University of Minnesota, University of Southern California, and Rice University. Her primary teachers include Burt Hara, Yehuda Gilad and Tina Ward (clarinet), and Clea Galhano (recorder). Additionally, in 2020 she was awarded a Fulbright to study in Helsinki, Finland. In addition to performing, you can read about Rachel’s work as a psychotherapist in ";

export default function BioPage() {
  return (
    <PhotoPage
      headingId="bio-heading"
      title="Bio"
      image={images["headshot-clarinet"]}
    >
      <Prose align="start">
        {PARAGRAPHS.map((text) => (
          <p key={text}>{tieLast(text)}</p>
        ))}
        <p>
          {LAST_BEFORE_LINK}
          <Link href="/therapy/about">
            {tieLast("the therapy section of this website")}
          </Link>
          .
        </p>
      </Prose>
    </PhotoPage>
  );
}
