export function onDemandRevalidation(
  env: Readonly<Record<string, string | undefined>>,
): boolean {
  return env.ON_DEMAND_REVALIDATION === "1";
}
