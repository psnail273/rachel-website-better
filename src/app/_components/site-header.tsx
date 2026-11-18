import Link from "next/link";
import { contactLink, performingMenu, therapyMenu } from "../../lib/navigation";
import { PageShell } from "./layout/components";
import { MobileMenu } from "./mobile-menu";
import { NavDropdown } from "./nav-dropdown";

export function SiteHeader() {
  return (
    <header className="relative border-b border-line py-4">
      <PageShell className="flex items-center justify-between gap-4">
        <Link
          href="/"
          className="font-serif text-xl text-heading hover:text-accent"
        >
          Rachel Siegel
        </Link>
        <nav aria-label="Main" className="hidden items-center gap-2 md:flex">
          <NavDropdown menu={therapyMenu} />
          <NavDropdown menu={performingMenu} />
          <Link
            href={contactLink.href}
            className="rounded px-3 py-2 hover:text-accent"
          >
            {contactLink.label}
          </Link>
        </nav>
        <MobileMenu />
      </PageShell>
    </header>
  );
}
