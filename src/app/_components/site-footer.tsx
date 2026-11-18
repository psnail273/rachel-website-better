import { PageShell } from "./layout/components";

export async function SiteFooter() {
  "use cache";
  return Promise.resolve(
    <footer className="py-8 text-center text-sm">
      <PageShell>© {new Date().getFullYear()} Rachel Siegel</PageShell>
    </footer>,
  );
}
