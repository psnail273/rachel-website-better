export async function SiteFooter() {
  "use cache";
  return Promise.resolve(
    <footer className="px-6 py-8 text-center text-sm">
      © {new Date().getFullYear()} Rachel Siegel
    </footer>,
  );
}
