export async function SiteFooter() {
  "use cache";
  return (
    <footer className="px-6 py-8 text-center text-sm">
      © {new Date().getFullYear()} Rachel Siegel
    </footer>
  );
}
