"use client";

import Link from "next/link";
import { useEffect, useId, useRef, useState } from "react";
import type { KeyboardEvent } from "react";
import type { NavMenu } from "../../lib/navigation";

export function NavDropdown({
  menu,
  current,
  pathname,
}: {
  menu: NavMenu;
  current: boolean;
  pathname: string | null;
}) {
  const [open, setOpen] = useState(false);
  const listId = useId();
  const rootRef = useRef<HTMLDivElement>(null);
  const tabRef = useRef<HTMLButtonElement>(null);
  const listRef = useRef<HTMLUListElement>(null);
  const focusFirst = useRef(false);

  useEffect(() => {
    function closeOnOutsidePointer(event: PointerEvent) {
      if (
        event.target instanceof Node &&
        !rootRef.current?.contains(event.target)
      ) {
        setOpen(false);
      }
    }
    document.addEventListener("pointerdown", closeOnOutsidePointer);
    return () => {
      document.removeEventListener("pointerdown", closeOnOutsidePointer);
    };
  }, []);

  useEffect(() => {
    if (open && focusFirst.current) {
      focusFirst.current = false;
      listRef.current?.querySelector("a")?.focus();
    }
  }, [open]);

  function openWithFocus() {
    focusFirst.current = true;
    setOpen(true);
  }

  function onTabKeyDown(event: KeyboardEvent<HTMLButtonElement>) {
    if (event.key === "Escape" && open) {
      event.preventDefault();
      setOpen(false);
      return;
    }
    if (
      event.key === "Enter" ||
      event.key === " " ||
      event.key === "ArrowDown"
    ) {
      event.preventDefault();
      if (open) {
        listRef.current?.querySelector("a")?.focus();
      } else {
        openWithFocus();
      }
    }
  }

  function onTabKeyUp(event: KeyboardEvent<HTMLButtonElement>) {
    // Firefox fires a button's click on Space keyup; without this it would
    // toggle the dropdown shut right after keydown opened it.
    if (event.key === " ") {
      event.preventDefault();
    }
  }

  function onListKeyDown(event: KeyboardEvent<HTMLUListElement>) {
    if (event.key === "Escape") {
      event.preventDefault();
      setOpen(false);
      tabRef.current?.focus();
      return;
    }
    if (event.key !== "ArrowDown" && event.key !== "ArrowUp") {
      return;
    }
    event.preventDefault();
    const links = Array.from(listRef.current?.querySelectorAll("a") ?? []);
    const current = links.findIndex((link) => link === document.activeElement);
    const step = event.key === "ArrowDown" ? 1 : -1;
    const next = (current + step + links.length) % links.length;
    links[next]?.focus();
  }

  return (
    <div ref={rootRef} data-dropdown="">
      <button
        ref={tabRef}
        type="button"
        aria-expanded={open}
        aria-controls={listId}
        aria-current={current ? "true" : undefined}
        data-nav-tab=""
        onClick={() => {
          setOpen((wasOpen) => !wasOpen);
        }}
        onKeyDown={onTabKeyDown}
        onKeyUp={onTabKeyUp}
        className="type-nav"
      >
        <span data-nav-label="">{menu.label}</span>
        <svg
          aria-hidden="true"
          data-chevron=""
          width="10"
          height="10"
          viewBox="0 0 10 10"
          fill="none"
          stroke="currentColor"
          strokeWidth="1.5"
        >
          <path d="M1 3.5 5 7.5 9 3.5" />
        </svg>
      </button>
      {open ? (
        <ul
          ref={listRef}
          id={listId}
          onKeyDown={onListKeyDown}
          data-dropdown-panel=""
        >
          {menu.links.map((link) => (
            <li key={link.href}>
              <Link
                href={link.href}
                className="type-nav-item"
                aria-current={link.href === pathname ? "page" : undefined}
                onClick={() => {
                  setOpen(false);
                }}
              >
                {link.label}
              </Link>
            </li>
          ))}
        </ul>
      ) : null}
    </div>
  );
}
