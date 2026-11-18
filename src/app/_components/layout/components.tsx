import Image from "next/image";
import type { ReactNode } from "react";
import type { SiteImage } from "../../../lib/images";
import { tieItem, tieLabel } from "../../../lib/tie";

type WithChildren = { children?: ReactNode; className?: string };

export function PageShell({ children, className }: WithChildren): ReactNode {
  return (
    <div data-shell="" className={className}>
      {children}
    </div>
  );
}

export type SectionProps = { children?: ReactNode } & (
  { labelledBy: string; label?: never } | { label: string; labelledBy?: never }
);

export function Section({
  children,
  labelledBy,
  label,
}: SectionProps): ReactNode {
  return (
    <section data-section="" aria-labelledby={labelledBy} aria-label={label}>
      {children}
    </section>
  );
}

export type SectionHeadingProps = {
  level: 1 | 2;
  id?: string;
  children?: ReactNode;
};

export function SectionHeading({
  level,
  id,
  children,
}: SectionHeadingProps): ReactNode {
  const content = typeof children === "string" ? tieLabel(children) : children;
  return level === 1 ? (
    <h1 data-heading="1" id={id} className="type-h1">
      {content}
    </h1>
  ) : (
    <h2 data-heading="2" id={id} className="type-h2">
      {content}
    </h2>
  );
}

export type StackProps = WithChildren & {
  space: "block" | "heading" | "flow" | "tight";
  as?: "div" | "section" | "ul" | "figure";
};

export function Stack({
  space,
  as: Tag = "div",
  className,
  children,
}: StackProps): ReactNode {
  return (
    <Tag data-stack={space} className={className}>
      {children}
    </Tag>
  );
}

export type ClusterProps = WithChildren & { align: "start" | "center" };

export function Cluster({
  align,
  className,
  children,
}: ClusterProps): ReactNode {
  return (
    <div data-cluster={align} className={className}>
      {children}
    </div>
  );
}

export type SidebarProps = {
  side: "lead" | "trail";
  head: ReactNode;
  aside: ReactNode;
  children?: ReactNode;
};

export function Sidebar({
  side,
  head,
  aside,
  children,
}: SidebarProps): ReactNode {
  const asideSlot = <div data-sidebar-aside="">{aside}</div>;
  const body = <div data-sidebar-body="">{children}</div>;
  return (
    <div data-sidebar={side}>
      <div data-sidebar-head="">{head}</div>
      {side === "lead" ? asideSlot : body}
      {side === "lead" ? body : asideSlot}
    </div>
  );
}

export type SwitcherProps = {
  kind: "pair" | "label" | "run";
  children: readonly [ReactNode, ReactNode];
};

export function Switcher({ kind, children }: SwitcherProps): ReactNode {
  return (
    <div data-switcher={kind}>
      <div>{children[0]}</div>
      <div>{children[1]}</div>
    </div>
  );
}

export function Center({ children }: { children?: ReactNode }): ReactNode {
  return <div data-center="">{children}</div>;
}

export type ProseProps = { align: "start" | "center"; children?: ReactNode };

export function Prose({ align, children }: ProseProps): ReactNode {
  return <div data-prose={align}>{children}</div>;
}

export function Lead({ children }: { children?: ReactNode }): ReactNode {
  return (
    <p data-lead="" className="type-lead">
      {children}
    </p>
  );
}

export type PullQuoteProps = { quote: string; caption: ReactNode };

export function PullQuote({ quote, caption }: PullQuoteProps): ReactNode {
  return (
    <figure data-quote="">
      <blockquote className="type-quote">{tieLabel(quote)}</blockquote>
      <figcaption className="type-small">{caption}</figcaption>
    </figure>
  );
}

export function Photo({ image }: { image: SiteImage }): ReactNode {
  return (
    <figure data-photo="">
      <Image
        src={image.src}
        alt={image.alt}
        width={image.width}
        height={image.height}
        sizes="(min-width: 640px) 24rem, 100vw"
      />
    </figure>
  );
}

export type ListProps = { variant: "panel" | "plain"; items: string[] };

export function List({ variant, items }: ListProps): ReactNode {
  return (
    <ul data-list={variant} className="type-list">
      {items.map((item, index) => (
        <li key={index}>{tieItem(item)}</li>
      ))}
    </ul>
  );
}

export type RowsProps = { rows: { text: string; status?: string }[] };

export function Rows({ rows }: RowsProps): ReactNode {
  return (
    <ul data-rows="" className="type-list">
      {rows.map((row, index) => (
        <li key={index}>
          <span>{tieItem(row.text)}</span>
          {row.status === undefined ? null : (
            <span data-status="">{row.status}</span>
          )}
        </li>
      ))}
    </ul>
  );
}

export type PhotoPageProps = {
  headingId: string;
  title: string;
  image: SiteImage;
  children?: ReactNode;
};

export function PhotoPage({
  headingId,
  title,
  image,
  children,
}: PhotoPageProps): ReactNode {
  return (
    <Section labelledBy={headingId}>
      <Sidebar
        side="lead"
        head={
          <SectionHeading level={1} id={headingId}>
            {title}
          </SectionHeading>
        }
        aside={<Photo image={image} />}
      >
        {children}
      </Sidebar>
    </Section>
  );
}
