"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useEffect, useState } from "react";
import {
  contactLink,
  currentSection,
  performingMenu,
  therapyMenu,
} from "../../lib/navigation";
import { PageShell } from "./layout/components";
import { MobileMenu } from "./mobile-menu";
import { NavDropdown } from "./nav-dropdown";

const scrolledPast = 24;

export function SiteHeader() {
  const pathname = usePathname();
  const section = currentSection(pathname);
  const [scrolled, setScrolled] = useState(false);

  useEffect(() => {
    function update() {
      setScrolled(window.scrollY > scrolledPast);
    }
    update();
    window.addEventListener("scroll", update, { passive: true });
    return () => {
      window.removeEventListener("scroll", update);
    };
  }, []);

  return (
    <header data-scrolled={scrolled ? "" : undefined}>
      <PageShell>
        <Link href="/" data-brand="" className="type-brand">
          Rachel Siegel
        </Link>
        <nav aria-label="Main" data-nav="">
          <NavDropdown
            menu={therapyMenu}
            current={section === "therapy"}
            pathname={pathname}
          />
          <NavDropdown
            menu={performingMenu}
            current={section === "performing"}
            pathname={pathname}
          />
          <Link
            href={contactLink.href}
            data-nav-tab=""
            className="type-nav"
            aria-current={section === "contact" ? "page" : undefined}
          >
            <span data-nav-label="">{contactLink.label}</span>
          </Link>
        </nav>
        <MobileMenu pathname={pathname} />
      </PageShell>
    </header>
  );
}
