import { revalidatePath } from "next/cache";

// On-demand revalidation: a POST marks every page for a fresh render on its next
// visit (revalidatePath("/", "layout")), so the Upcoming strip reads the feeds
// and the events cache again. Only a server whose environment sets
// ON_DEMAND_REVALIDATION=1 has it (the Scenarios' server:
// tools/verify/scenario-env); on any other it answers 404, as a missing route.
export function POST(): Response {
  if (process.env.ON_DEMAND_REVALIDATION !== "1") {
    return new Response(null, { status: 404 });
  }
  revalidatePath("/", "layout");
  return Response.json({ revalidated: true });
}
