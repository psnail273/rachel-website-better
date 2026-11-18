"use client";

import Link from "next/link";
import { useEffect, useId, useRef, useState } from "react";
import type { KeyboardEvent } from "react";
import {
  contactLink,
  homeLink,
  performingMenu,
  therapyMenu,
} from "../../lib/navigation";
import type { NavLink, NavMenu } from "../../lib/navigation";
import { PageShell } from "./layout/components";

function Icon({ path }: { path: string }) {
  return (
    <svg
      aria-hidden="true"
      fill="none"
      height="20"
      stroke="currentColor"
      strokeWidth="1.5"
      viewBox="0 0 20 20"
      width="20"
    >
      <path d={path} />
    </svg>
  );
}

export function MobileMenu({ pathname }: { pathname: string | null }) {
  const [open, setOpen] = useState(false);
  const dialogId = useId();
  const therapyLabelId = useId();
  const performingLabelId = useId();
  const buttonRef = useRef<HTMLButtonElement>(null);
  const dialogRef = useRef<HTMLDialogElement>(null);
  const closeRef = useRef<HTMLButtonElement>(null);
  const wasOpen = useRef(false);

  useEffect(() => {
    if (open) {
      dialogRef.current?.showModal();
      closeRef.current?.focus();
    } else if (wasOpen.current) {
      buttonRef.current?.focus();
    }
    wasOpen.current = open;
  }, [open]);

  function close() {
    setOpen(false);
  }

  function onKeyDown(event: KeyboardEvent<HTMLDialogElement>) {
    if (event.key === "Escape") {
      event.preventDefault();
      close();
      return;
    }
    if (event.key !== "Tab") {
      return;
    }
    const focusable =
      event.currentTarget.querySelectorAll<HTMLElement>("button, a[href]");
    const first = focusable[0];
    const last = focusable[focusable.length - 1];
    if (event.shiftKey && event.target === first) {
      event.preventDefault();
      last.focus();
    } else if (!event.shiftKey && event.target === last) {
      event.preventDefault();
      first.focus();
    }
  }

  function renderLink(link: NavLink) {
    return (
      <Link
        href={link.href}
        className="type-sheet-link"
        aria-current={pathname === link.href ? "page" : undefined}
        onClick={close}
      >
        {link.label}
      </Link>
    );
  }

  function renderGroup(menu: NavMenu, labelId: string) {
    return (
      <div role="group" aria-labelledby={labelId} data-menu-group="">
        <p id={labelId} className="type-label" data-menu-label="">
          {menu.label}
        </p>
        <ul>
          {menu.links.map((link) => (
            <li key={link.href}>{renderLink(link)}</li>
          ))}
        </ul>
      </div>
    );
  }

  return (
    <div className="md:hidden">
      <button
        ref={buttonRef}
        type="button"
        aria-label="Menu"
        aria-expanded={open}
        aria-controls={dialogId}
        aria-haspopup="dialog"
        data-menu-button=""
        onClick={() => {
          setOpen(true);
        }}
      >
        <Icon path="M0 7h20M0 13h20" />
      </button>
      {open ? (
        <dialog
          ref={dialogRef}
          id={dialogId}
          aria-label="Menu"
          data-menu=""
          onKeyDown={onKeyDown}
          onCancel={(event) => {
            event.preventDefault();
            close();
          }}
          onClose={close}
        >
          <div data-menu-head="">
            <PageShell>
              <span className="type-brand" data-menu-brand="">
                Rachel Siegel
              </span>
              <button
                ref={closeRef}
                type="button"
                aria-label="Close"
                data-menu-close=""
                onClick={close}
              >
                <Icon path="M1 1l18 18M19 1L1 19" />
              </button>
            </PageShell>
          </div>
          <PageShell>
            <div data-menu-links="">
              {renderLink(homeLink)}
              {renderGroup(therapyMenu, therapyLabelId)}
              {renderGroup(performingMenu, performingLabelId)}
              {renderLink(contactLink)}
            </div>
          </PageShell>
        </dialog>
      ) : null}
    </div>
  );
}
