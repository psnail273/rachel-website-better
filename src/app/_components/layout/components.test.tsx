// @vitest-environment happy-dom
import Image from "next/image";
import type { ReactElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import { images } from "../../../lib/images";
import {
  Center,
  Cluster,
  Lead,
  List,
  Photo,
  PhotoPage,
  PageShell,
  Prose,
  PullQuote,
  Rows,
  Section,
  SectionHeading,
  Sidebar,
  Stack,
  Switcher,
} from "./components";

const NBSP = " ";
const ZWSP = "​";

function render(element: ReactElement): Element | null {
  const doc = new DOMParser().parseFromString(
    renderToStaticMarkup(element),
    "text/html",
  );
  return doc.body.firstElementChild;
}

function attrs(el: Element | null | undefined): Record<string, string> {
  return Object.fromEntries(
    Array.from(el?.attributes ?? []).map((attr) => [attr.name, attr.value]),
  );
}

function kids(el: Element | null | undefined): Element[] {
  return Array.from(el?.children ?? []);
}

function nth(
  el: Element | null | undefined,
  index: number,
): Element | undefined {
  return kids(el).at(index);
}

function tags(els: Element[]): string[] {
  return els.map((el) => el.tagName);
}

describe("layout components", () => {
  it("renders PageShell, Section and SectionHeading with their attributes", () => {
    const shell = render(
      <PageShell>
        <p>x</p>
      </PageShell>,
    );
    const shellWithClass = render(<PageShell className="flex">x</PageShell>);
    const labelled = render(<Section labelledBy="about-heading">x</Section>);
    const labelledByText = render(
      <Section label="A line from Rilke">x</Section>,
    );
    const h1 = render(
      <SectionHeading level={1} id="et-heading">
        Education and Training
      </SectionHeading>,
    );
    const h2 = render(
      <SectionHeading level={2}>Upcoming events</SectionHeading>,
    );

    expect(shell?.tagName).toBe("DIV");
    expect(attrs(shell)).toEqual({ "data-shell": "" });
    expect(tags(kids(shell))).toEqual(["P"]);
    expect(attrs(shellWithClass)).toEqual({ "data-shell": "", class: "flex" });
    expect(labelled?.tagName).toBe("SECTION");
    expect(attrs(labelled)).toEqual({
      "data-section": "",
      "aria-labelledby": "about-heading",
    });
    expect(labelledByText?.tagName).toBe("SECTION");
    expect(attrs(labelledByText)).toEqual({
      "data-section": "",
      "aria-label": "A line from Rilke",
    });
    expect(h1?.tagName).toBe("H1");
    expect(attrs(h1)).toEqual({
      "data-heading": "1",
      id: "et-heading",
      class: "type-h1",
    });
    expect(h1?.textContent).toBe(`Education${NBSP}and Training`);
    expect(h2?.tagName).toBe("H2");
    expect(attrs(h2)).toEqual({ "data-heading": "2", class: "type-h2" });
    expect(h2?.textContent).toBe("Upcoming events");
  });

  it("renders each Stack and Cluster variant", () => {
    const block = render(<Stack space="block">x</Stack>);
    const heading = render(<Stack space="heading">x</Stack>);
    const flow = render(<Stack space="flow">x</Stack>);
    const tight = render(<Stack space="tight">x</Stack>);
    const asSection = render(
      <Stack space="flow" as="section" className="max-w-3xl">
        x
      </Stack>,
    );
    const asList = render(
      <Stack space="tight" as="ul">
        <li>x</li>
      </Stack>,
    );
    const asFigure = render(
      <Stack space="tight" as="figure">
        x
      </Stack>,
    );
    const start = render(<Cluster align="start">x</Cluster>);
    const center = render(
      <Cluster align="center" className="flex-col">
        x
      </Cluster>,
    );

    expect([block, heading, flow, tight].map((el) => el?.tagName)).toEqual([
      "DIV",
      "DIV",
      "DIV",
      "DIV",
    ]);
    expect(attrs(block)).toEqual({ "data-stack": "block" });
    expect(attrs(heading)).toEqual({ "data-stack": "heading" });
    expect(attrs(flow)).toEqual({ "data-stack": "flow" });
    expect(attrs(tight)).toEqual({ "data-stack": "tight" });
    expect(asSection?.tagName).toBe("SECTION");
    expect(attrs(asSection)).toEqual({
      "data-stack": "flow",
      class: "max-w-3xl",
    });
    expect(asList?.tagName).toBe("UL");
    expect(attrs(asList)).toEqual({ "data-stack": "tight" });
    expect(asFigure?.tagName).toBe("FIGURE");
    expect(attrs(asFigure)).toEqual({ "data-stack": "tight" });
    expect(start?.tagName).toBe("DIV");
    expect(attrs(start)).toEqual({ "data-cluster": "start" });
    expect(center?.tagName).toBe("DIV");
    expect(attrs(center)).toEqual({
      "data-cluster": "center",
      class: "flex-col",
    });
  });

  it("renders Sidebar's head, slot and body in each variant's order", () => {
    const lead = render(
      <Sidebar
        side="lead"
        head={<h1>Head</h1>}
        aside={
          <Image src="/images/slot.jpg" alt="slot" width={10} height={10} />
        }
      >
        <p>Body</p>
      </Sidebar>,
    );
    const trail = render(
      <Sidebar
        side="trail"
        head={<h1>Head</h1>}
        aside={
          <Image src="/images/slot.jpg" alt="slot" width={10} height={10} />
        }
      >
        <p>Body</p>
      </Sidebar>,
    );

    expect(lead?.tagName).toBe("DIV");
    expect(attrs(lead)).toEqual({ "data-sidebar": "lead" });
    expect(tags(kids(lead))).toEqual(["DIV", "DIV", "DIV"]);
    expect(kids(lead).map(attrs)).toEqual([
      { "data-sidebar-head": "" },
      { "data-sidebar-aside": "" },
      { "data-sidebar-body": "" },
    ]);
    expect(kids(lead).map((el) => tags(kids(el)))).toEqual([
      ["H1"],
      ["IMG"],
      ["P"],
    ]);
    expect(attrs(trail)).toEqual({ "data-sidebar": "trail" });
    expect(tags(kids(trail))).toEqual(["DIV", "DIV", "DIV"]);
    expect(kids(trail).map(attrs)).toEqual([
      { "data-sidebar-head": "" },
      { "data-sidebar-body": "" },
      { "data-sidebar-aside": "" },
    ]);
    expect(kids(trail).map((el) => tags(kids(el)))).toEqual([
      ["H1"],
      ["P"],
      ["IMG"],
    ]);
  });

  it("renders exactly two children in Switcher, each in a div", () => {
    const pair = render(
      <Switcher kind="pair">
        <p>a</p>
        <p>b</p>
      </Switcher>,
    );
    const label = render(
      <Switcher kind="label">
        <p>a</p>
        <p>b</p>
      </Switcher>,
    );
    const run = render(
      <Switcher kind="run">
        <p>a</p>
        <p>b</p>
      </Switcher>,
    );
    const [a, b, c] = [<p key="a">a</p>, <p key="b">b</p>, <p key="c">c</p>];
    const three = renderToStaticMarkup(
      // prettier-ignore
      // @ts-expect-error Switcher takes exactly two children
      <Switcher kind="pair">{a}{b}{c}</Switcher>,
    );

    expect([pair, label, run].map((el) => el?.tagName)).toEqual([
      "DIV",
      "DIV",
      "DIV",
    ]);
    expect([pair, label, run].map(attrs)).toEqual([
      { "data-switcher": "pair" },
      { "data-switcher": "label" },
      { "data-switcher": "run" },
    ]);
    expect([pair, label, run].map((el) => tags(kids(el)))).toEqual([
      ["DIV", "DIV"],
      ["DIV", "DIV"],
      ["DIV", "DIV"],
    ]);
    expect([pair, label, run].map((el) => kids(el).map(attrs))).toEqual([
      [{}, {}],
      [{}, {}],
      [{}, {}],
    ]);
    expect(
      [pair, label, run].map((el) => kids(el).map((k) => tags(kids(k)))),
    ).toEqual([
      [["P"], ["P"]],
      [["P"], ["P"]],
      [["P"], ["P"]],
    ]);
    expect(
      [pair, label, run].map((el) => kids(el).map((k) => k.textContent)),
    ).toEqual([
      ["a", "b"],
      ["a", "b"],
      ["a", "b"],
    ]);
    expect(three).not.toContain(">c<");
  });

  it("renders Center, Prose and Lead with their attributes", () => {
    const center = render(<Center>x</Center>);
    const proseStart = render(<Prose align="start">x</Prose>);
    const proseCenter = render(<Prose align="center">x</Prose>);
    const lead = render(<Lead>For therapy, please reach out.</Lead>);

    expect(center?.tagName).toBe("DIV");
    expect(attrs(center)).toEqual({ "data-center": "" });
    expect(proseStart?.tagName).toBe("DIV");
    expect(attrs(proseStart)).toEqual({ "data-prose": "start" });
    expect(proseCenter?.tagName).toBe("DIV");
    expect(attrs(proseCenter)).toEqual({ "data-prose": "center" });
    expect(lead?.tagName).toBe("P");
    expect(attrs(lead)).toEqual({ "data-lead": "", class: "type-lead" });
    expect(lead?.textContent).toBe("For therapy, please reach out.");
  });

  it("renders Lead with the hairline under its statement", () => {
    const withRule = render(<Lead rule>Some words here.</Lead>);
    const bare = render(<Lead>Some words here.</Lead>);
    const lead = withRule?.children.item(0);
    const rule = withRule?.children.item(1);

    expect(withRule?.tagName).toBe("DIV");
    expect(attrs(withRule)).toEqual({});
    expect(withRule?.children).toHaveLength(2);
    expect(lead?.tagName).toBe("P");
    expect(attrs(lead)).toEqual({ "data-lead": "", class: "type-lead" });
    expect(lead?.textContent).toBe("Some words here.");
    expect(rule?.tagName).toBe("DIV");
    expect(attrs(rule)).toEqual({ "data-rule": "", "aria-hidden": "true" });
    expect(rule?.children).toHaveLength(0);
    expect(rule?.textContent).toBe("");
    expect(withRule?.querySelector("svg")).toBeNull();
    expect(withRule?.querySelector("circle")).toBeNull();
    expect(bare?.tagName).toBe("P");
    expect(attrs(bare)).toEqual({ "data-lead": "", class: "type-lead" });
    expect(bare?.querySelector("[data-rule]")).toBeNull();
  });

  it("renders PullQuote, Photo, List and Rows with their attributes and tied text", () => {
    const quote = render(
      <PullQuote
        quote="Just keep going. No feeling is final."
        caption={
          <>
            Rainer Maria Rilke, <cite>Letters to a Young Poet</cite>
          </>
        }
      />,
    );
    const photo = render(
      <Photo
        image={{
          src: "/images/test-photo.jpg",
          alt: "A test photo",
          width: 600,
          height: 800,
        }}
      />,
    );
    const panel = render(
      <List
        variant="panel"
        items={[
          "Identity development",
          "Work life balance/relationship issues",
        ]}
      />,
    );
    const plain = render(
      <List variant="plain" items={["Identity development"]} />,
    );
    const rows = render(
      <Rows
        rows={[
          { text: "Brahms Clarinet Quintet in B minor", status: "Coming soon" },
          { text: "Licensed Professional Counselor" },
        ]}
      />,
    );
    const photoImg = nth(photo, 0);
    const rowItems = kids(rows);

    expect(quote?.tagName).toBe("FIGURE");
    expect(attrs(quote)).toEqual({ "data-quote": "" });
    expect(tags(kids(quote))).toEqual(["BLOCKQUOTE", "FIGCAPTION"]);
    expect(kids(quote).map(attrs)).toEqual([
      { class: "type-quote" },
      { class: "type-small" },
    ]);
    expect(kids(quote).map((el) => el.textContent)).toEqual([
      `Just keep going. No feeling is${NBSP}final.`,
      "Rainer Maria Rilke, Letters to a Young Poet",
    ]);
    expect(tags(kids(nth(quote, 1)))).toEqual(["CITE"]);

    expect(photo?.tagName).toBe("FIGURE");
    expect(attrs(photo)).toEqual({ "data-photo": "" });
    expect(tags(kids(photo))).toEqual(["IMG"]);
    expect(photoImg?.getAttribute("alt")).toBe("A test photo");
    expect(photoImg?.getAttribute("width")).toBe("600");
    expect(photoImg?.getAttribute("height")).toBe("800");
    expect(photoImg?.getAttribute("sizes")).toBe(
      "(min-width: 640px) 24rem, 100vw",
    );

    expect(panel?.tagName).toBe("UL");
    expect(attrs(panel)).toEqual({ "data-list": "panel", class: "type-list" });
    expect(tags(kids(panel))).toEqual(["LI", "LI"]);
    expect(kids(panel).map(attrs)).toEqual([{}, {}]);
    expect(kids(panel).map((el) => el.textContent)).toEqual([
      "Identity development",
      `Work life balance/${ZWSP}relationship${NBSP}issues`,
    ]);
    expect(attrs(plain)).toEqual({ "data-list": "plain", class: "type-list" });

    expect(rows?.tagName).toBe("UL");
    expect(attrs(rows)).toEqual({ "data-rows": "", class: "type-list" });
    expect(tags(rowItems)).toEqual(["LI", "LI"]);
    expect(rowItems.map(attrs)).toEqual([{}, {}]);
    expect(tags(kids(rowItems[0]))).toEqual(["SPAN", "SPAN"]);
    expect(kids(rowItems[0]).map(attrs)).toEqual([{}, { "data-status": "" }]);
    expect(kids(rowItems[0]).map((el) => el.textContent)).toEqual([
      `Brahms Clarinet Quintet in B${NBSP}minor`,
      "Coming soon",
    ]);
    expect(tags(kids(rowItems[1]))).toEqual(["SPAN"]);
    expect(kids(rowItems[1]).map((el) => el.textContent)).toEqual([
      `Licensed${NBSP}Professional Counselor`,
    ]);
  });

  it("renders data-bleed on a Section only when it bleeds", () => {
    const bleeding = render(
      <Section bleed labelledBy="hero-heading">
        x
      </Section>,
    );
    const plain = render(
      <Section bleed={false} label="Upcoming">
        x
      </Section>,
    );

    expect(bleeding?.tagName).toBe("SECTION");
    expect(attrs(bleeding)).toEqual({
      "data-section": "",
      "data-bleed": "",
      "aria-labelledby": "hero-heading",
    });
    expect(plain?.tagName).toBe("SECTION");
    expect(attrs(plain)).toEqual({
      "data-section": "",
      "aria-label": "Upcoming",
    });
  });

  it("composes PhotoPage as Section > Sidebar lead", () => {
    const page = render(
      <PhotoPage
        headingId="bio-heading"
        title="Bio"
        image={images["headshot-clarinet"]}
      >
        <p>copy</p>
      </PhotoPage>,
    );
    const sidebar = nth(page, 0);
    const [head, aside, body] = [
      nth(sidebar, 0),
      nth(sidebar, 1),
      nth(sidebar, 2),
    ];

    expect(page?.tagName).toBe("SECTION");
    expect(attrs(page)).toEqual({
      "data-section": "",
      "aria-labelledby": "bio-heading",
    });
    expect(tags(kids(page))).toEqual(["DIV"]);
    expect(attrs(sidebar)).toEqual({ "data-sidebar": "lead" });
    expect(tags(kids(head))).toEqual(["H1"]);
    expect(attrs(nth(head, 0))).toEqual({
      "data-heading": "1",
      id: "bio-heading",
      class: "type-h1",
    });
    expect(nth(head, 0)?.textContent).toBe("Bio");
    expect(tags(kids(aside))).toEqual(["FIGURE"]);
    expect(attrs(nth(aside, 0))).toHaveProperty("data-photo");
    expect(nth(nth(aside, 0), 0)?.getAttribute("alt")).toBe(
      images["headshot-clarinet"].alt,
    );
    expect(tags(kids(body))).toEqual(["P"]);
    expect(nth(body, 0)?.textContent).toBe("copy");
  });
});
