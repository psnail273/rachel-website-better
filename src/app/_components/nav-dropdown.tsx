"use client";

import Link from "next/link";
import { useEffect, useId, useRef, useState } from "react";
import type { KeyboardEvent } from "react";
import type { NavMenu } from "../../lib/navigation";

const linkClass =
  "block rounded px-3 py-2 hover:text-accent focus-visible:text-accent focus-visible:outline-2 focus-visible:outline-accent";

export function NavDropdown({ menu }: { menu: NavMenu }) {
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
    if (
      event.key === "Enter" ||
      event.key === " " ||
      event.key === "ArrowDown"
    ) {
      event.preventDefault();
      openWithFocus();
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
    <div ref={rootRef} className="relative">
      <button
        ref={tabRef}
        type="button"
        aria-expanded={open}
        aria-controls={listId}
        onClick={() => {
          setOpen((wasOpen) => !wasOpen);
        }}
        onKeyDown={onTabKeyDown}
        onKeyUp={onTabKeyUp}
        className="cursor-pointer rounded px-3 py-2 hover:text-accent focus-visible:text-accent focus-visible:outline-2 focus-visible:outline-accent"
      >
        {menu.label} <span aria-hidden="true">▾</span>
      </button>
      {open ? (
        <ul
          ref={listRef}
          id={listId}
          onKeyDown={onListKeyDown}
          className="absolute right-0 z-10 mt-1 min-w-48 rounded-md border border-accent-soft bg-background p-1 shadow-md"
        >
          {menu.links.map((link) => (
            <li key={link.href}>
              <Link
                href={link.href}
                className={linkClass}
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
