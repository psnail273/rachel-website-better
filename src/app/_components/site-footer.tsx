import Link from "next/link";
import {
  contactLink,
  performingMenu,
  therapyMenu,
  type NavMenu,
} from "@/lib/navigation";
import { siteConfig } from "@/lib/site-config";
import { PageShell } from "./layout/components";

const linkClass =
  "flex min-h-[2.25rem] items-center whitespace-nowrap text-on-band no-underline hover:underline hover:decoration-1";
const labelClass = "type-label text-band-accent";

function Column({ menu }: { menu: NavMenu }) {
  return (
    <nav aria-label={`${menu.label} pages`}>
      <p className={labelClass}>{menu.label}</p>
      <ul>
        {menu.links.map((link) => (
          <li key={link.href}>
            <Link href={link.href} className={linkClass}>
              {link.label}
            </Link>
          </li>
        ))}
      </ul>
    </nav>
  );
}

export async function SiteFooter() {
  "use cache";
  return Promise.resolve(
    <footer className="[--accent:var(--on-band)] bg-band py-block text-on-band type-small">
      <PageShell className="grid gap-block lg:grid-cols-[minmax(0,5fr)_minmax(0,7fr)]">
        <div>
          <p className="type-footer-name">Rachel Siegel</p>
          <p className="mt-tight text-balance">
            Licensed psychotherapist, clarinetist, recorder player
          </p>
          <p className="text-balance text-on-band-muted">St. Louis, MO</p>
        </div>
        <div className="grid gap-block sm:grid-cols-[repeat(3,minmax(0,1fr))] sm:gap-x-flow">
          <Column menu={therapyMenu} />
          <Column menu={performingMenu} />
          <div>
            <p className={labelClass}>Contact</p>
            <ul>
              <li>
                <a
                  href={siteConfig.wellnessAllianceUrl}
                  target="_blank"
                  rel="noopener noreferrer"
                  className={linkClass}
                >
                  Wellness Alliance
                </a>
              </li>
              <li>
                <a href={`mailto:${siteConfig.email}`} className={linkClass}>
                  Email
                </a>
              </li>
              <li>
                <Link href={contactLink.href} className={linkClass}>
                  Contact page
                </Link>
              </li>
            </ul>
          </div>
        </div>
        <p className="text-on-band-muted lg:col-span-2">
          © {new Date().getFullYear()} Rachel Siegel
        </p>
      </PageShell>
    </footer>,
  );
}
