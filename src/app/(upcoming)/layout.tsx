import type { ReactNode } from "react";

export default async function UpcomingLayout({
  children,
}: Readonly<{ children: ReactNode }>) {
  return <>{children}</>;
}
