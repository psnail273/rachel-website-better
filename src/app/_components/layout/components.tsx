import type { ReactNode } from "react";
import type { SiteImage } from "../../../lib/images";

type WithChildren = { children?: ReactNode; className?: string };

export const PageShell: (props: WithChildren) => ReactNode = () => null;

export type SectionProps = { children?: ReactNode } & (
  { labelledBy: string; label?: never } | { label: string; labelledBy?: never }
);
export const Section: (props: SectionProps) => ReactNode = () => null;

export type SectionHeadingProps = {
  level: 1 | 2;
  id?: string;
  children?: ReactNode;
};
export const SectionHeading: (props: SectionHeadingProps) => ReactNode = () =>
  null;

export type StackProps = WithChildren & {
  space: "block" | "heading" | "flow" | "tight";
  as?: "div" | "section" | "ul" | "figure";
};
export const Stack: (props: StackProps) => ReactNode = () => null;

export type ClusterProps = WithChildren & { align: "start" | "center" };
export const Cluster: (props: ClusterProps) => ReactNode = () => null;

export type SidebarProps = {
  side: "lead" | "trail";
  head: ReactNode;
  aside: ReactNode;
  children?: ReactNode;
};
export const Sidebar: (props: SidebarProps) => ReactNode = () => null;

export type SwitcherProps = {
  kind: "pair" | "label" | "run";
  children: readonly [ReactNode, ReactNode];
};
export const Switcher: (props: SwitcherProps) => ReactNode = () => null;

export const Center: (props: { children?: ReactNode }) => ReactNode = () =>
  null;

export type ProseProps = { align: "start" | "center"; children?: ReactNode };
export const Prose: (props: ProseProps) => ReactNode = () => null;

export const Lead: (props: { children?: ReactNode }) => ReactNode = () => null;

export type PullQuoteProps = { quote: string; caption: ReactNode };
export const PullQuote: (props: PullQuoteProps) => ReactNode = () => null;

export const Photo: (props: { image: SiteImage }) => ReactNode = () => null;

export type ListProps = { variant: "panel" | "plain"; items: string[] };
export const List: (props: ListProps) => ReactNode = () => null;

export type RowsProps = { rows: { text: string; status?: string }[] };
export const Rows: (props: RowsProps) => ReactNode = () => null;

export type PhotoPageProps = {
  headingId: string;
  title: string;
  image: SiteImage;
  children?: ReactNode;
};
export const PhotoPage: (props: PhotoPageProps) => ReactNode = () => null;
