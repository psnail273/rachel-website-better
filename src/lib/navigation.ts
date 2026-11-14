export type NavLink = {
  label: string;
  href: string;
};

export type NavMenu = {
  label: string;
  links: NavLink[];
};

export const therapyMenu: NavMenu = {
  label: "Therapy",
  links: [
    { label: "About Me", href: "/therapy/about" },
    { label: "Services", href: "/therapy/services" },
    {
      label: "Education and Training",
      href: "/therapy/education-and-training",
    },
  ],
};

export const performingMenu: NavMenu = {
  label: "Performing",
  links: [
    { label: "Bio", href: "/performing/bio" },
    { label: "Media", href: "/performing/media" },
  ],
};

export const contactLink: NavLink = { label: "Contact", href: "/contact" };

export const homeLink: NavLink = { label: "Home", href: "/" };
