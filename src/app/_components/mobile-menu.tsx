"use client";

import Link from "next/link";
import { useId, useRef, useState } from "react";
import type { KeyboardEvent } from "react";
import {
  contactLink,
  homeLink,
  performingMenu,
  therapyMenu,
} from "../../lib/navigation";
import type { NavMenu } from "../../lib/navigation";

const linkClass =
  "block rounded px-3 py-2 hover:text-accent focus-visible:text-accent focus-visible:outline-2 focus-visible:outline-accent";

export function MobileMenu() {
  const [open, setOpen] = useState(false);
  const panelId = useId();
  const labelPrefix = useId();
  const buttonRef = useRef<HTMLButtonElement>(null);

  function close() {
    setOpen(false);
  }

  function onKeyDown(event: KeyboardEvent<HTMLDivElement>) {
    if (event.key === "Escape" && open) {
      event.preventDefault();
      setOpen(false);
      buttonRef.current?.focus();
    }
  }

  function renderGroup(menu: NavMenu, key: string) {
    const labelId = `${labelPrefix}-${key}`;
    return (
      <div role="group" aria-labelledby={labelId}>
        <p id={labelId} className="px-3 py-2 font-serif text-heading">
          {menu.label}
        </p>
        <ul>
          {menu.links.map((link) => (
            <li key={link.href}>
              <Link href={link.href} className={linkClass} onClick={close}>
                {link.label}
              </Link>
            </li>
          ))}
        </ul>
      </div>
    );
  }

  return (
    <div className="md:hidden" onKeyDown={onKeyDown}>
      <button
        ref={buttonRef}
        type="button"
        aria-label="Menu"
        aria-expanded={open}
        aria-controls={panelId}
        onClick={() => {
          if (open) {
            buttonRef.current?.focus();
          }
          setOpen((wasOpen) => !wasOpen);
        }}
        className="flex cursor-pointer flex-col gap-1 rounded px-3 py-3 hover:text-accent focus-visible:outline-2 focus-visible:outline-accent"
      >
        <span aria-hidden="true" className="block h-0.5 w-5 bg-current" />
        <span aria-hidden="true" className="block h-0.5 w-5 bg-current" />
        <span aria-hidden="true" className="block h-0.5 w-5 bg-current" />
      </button>
      {open ? (
        <div
          id={panelId}
          className="absolute inset-x-0 top-full z-10 border-b border-accent-soft bg-background p-2 shadow-md"
        >
          <Link href={homeLink.href} className={linkClass} onClick={close}>
            {homeLink.label}
          </Link>
          {renderGroup(therapyMenu, "therapy")}
          {renderGroup(performingMenu, "performing")}
          <Link href={contactLink.href} className={linkClass} onClick={close}>
            {contactLink.label}
          </Link>
        </div>
      ) : null}
    </div>
  );
}
