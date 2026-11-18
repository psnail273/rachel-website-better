import type { Metadata } from "next";
import localFont from "next/font/local";
import { PageShell } from "./_components/layout/components";
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
  fallback: ["Georgia", "serif"],
  adjustFontFallback: "Times New Roman",
});

export const metadata: Metadata = {
  title: { default: "Rachel Siegel", template: "%s · Rachel Siegel" },
  description:
    "Rachel Siegel, licensed psychotherapist, clarinetist and recorder player.",
};

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html lang="en" className={`${fraunces.variable} antialiased`}>
      <body className="flex min-h-screen flex-col">
        <a href="#main" data-skip-link="">
          Skip to content
        </a>
        <SiteHeader />
        <main id="main" tabIndex={-1}>
          <PageShell>{children}</PageShell>
        </main>
        <SiteFooter />
      </body>
    </html>
  );
}
