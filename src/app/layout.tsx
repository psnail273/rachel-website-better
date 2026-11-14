import type { Metadata } from "next";
import localFont from "next/font/local";
import { SiteFooter } from "./_components/site-footer";
import { SiteHeader } from "./_components/site-header";
import "./globals.css";

const fraunces = localFont({
  src: [
    { path: "./fonts/Fraunces-Variable.ttf", style: "normal" },
    { path: "./fonts/Fraunces-Italic-Variable.ttf", style: "italic" },
  ],
  weight: "100 900",
  variable: "--font-fraunces",
});

const sourceSans = localFont({
  src: [
    { path: "./fonts/SourceSans3-Variable.ttf", style: "normal" },
    { path: "./fonts/SourceSans3-Italic-Variable.ttf", style: "italic" },
  ],
  weight: "200 900",
  variable: "--font-source-sans",
});

export const metadata: Metadata = {
  title: { default: "Rachel Siegel", template: "%s · Rachel Siegel" },
  description:
    "Rachel Siegel, licensed psychotherapist, clarinetist and recorder player.",
};

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html
      lang="en"
      className={`${fraunces.variable} ${sourceSans.variable} antialiased`}
    >
      <body className="flex min-h-screen flex-col">
        <SiteHeader />
        <main className="flex-1 px-6 py-8">{children}</main>
        <SiteFooter />
      </body>
    </html>
  );
}
