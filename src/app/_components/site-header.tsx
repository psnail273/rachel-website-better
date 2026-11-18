import Link from "next/link";
import { contactLink, performingMenu, therapyMenu } from "../../lib/navigation";
import { MobileMenu } from "./mobile-menu";
import { NavDropdown } from "./nav-dropdown";

export function SiteHeader() {
  return (
    <header className="relative flex items-center justify-between gap-4 border-b border-line px-6 py-4">
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
    </header>
  );
}
