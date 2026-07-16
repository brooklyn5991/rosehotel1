import { createFileRoute, Link } from "@tanstack/react-router";
import { useServerFn } from "@tanstack/react-start";
import { useQuery } from "@tanstack/react-query";
import { z } from "zod";
import { SiteNav } from "@/components/site-nav";
import { SiteFooter } from "@/components/site-footer";
import { getReservation } from "@/lib/hotel.functions";

const currency = (n: number) =>
  new Intl.NumberFormat("en-NG", { style: "currency", currency: "NGN", maximumFractionDigits: 0 }).format(n);

export const Route = createFileRoute("/reservation/$id")({
  validateSearch: (s) => z.object({ paid: z.coerce.number().optional() }).parse(s),
  head: () => ({ meta: [{ title: "Reservation — Garen's Garden" }] }),
  component: ReservationPage,
});

function ReservationPage() {
  const { id } = Route.useParams();
  const search = Route.useSearch();
  const fetchRes = useServerFn(getReservation);
  const res = useQuery({ queryKey: ["reservation", id], queryFn: () => fetchRes({ data: { id } }) });

  const r = res.data as
    | {
        confirmation_code: string;
        total_ngn: number;
        check_in: string;
        check_out: string;
        payment_status: string;
        status: string;
        guest_name: string;
        rooms: { room_number: string; name: string } | null;
      }
    | undefined;

  const paid = search.paid === 1 || r?.payment_status === "paid";

  return (
    <div className="bg-deep font-sans text-gold-light min-h-screen antialiased">
      <SiteNav />
      <main className="pt-32 pb-32 px-6 max-w-2xl mx-auto">
        {res.isLoading || !r ? (
          <p className="text-center text-zinc-400">Loading…</p>
        ) : (
          <div className="bg-warm/10 ring-1 ring-gold/20 p-8 text-center">
            <p className="text-[10px] uppercase tracking-[0.4em] text-gold mb-4">
              {paid ? "Reservation Confirmed" : "Payment Pending"}
            </p>
            <p className="font-serif text-5xl text-gold-light tracking-widest mb-6">{r.confirmation_code}</p>

            <div className="border-y border-gold/10 py-6 mb-6 space-y-2 text-left">
              <Row label="Guest" value={r.guest_name} />
              <Row label="Room" value={`Room ${r.rooms?.room_number ?? ""} · ${r.rooms?.name ?? ""}`} />
              <Row label="Check-in" value={r.check_in} />
              <Row label="Check-out" value={r.check_out} />
              <Row label="Total" value={currency(r.total_ngn)} />
              <Row label="Payment" value={r.payment_status.toUpperCase()} />
              <Row label="Status" value={r.status.toUpperCase()} />
            </div>

            {paid ? (
              <p className="text-sm text-green-300">
                Your room is locked and reserved. See you at check-in (3:00 PM).
              </p>
            ) : (
              <p className="text-sm text-amber-300">Payment was not completed. This reservation has been cancelled.</p>
            )}

            <Link to="/rooms" className="inline-block mt-8 text-[10px] uppercase tracking-[0.3em] text-gold border-b border-gold/40 pb-1">
              Back to rooms →
            </Link>
          </div>
        )}
      </main>
      <SiteFooter />
    </div>
  );
}

function Row({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex justify-between text-sm">
      <span className="text-gold/70 uppercase tracking-[0.2em] text-[10px]">{label}</span>
      <span className="text-zinc-200">{value}</span>
    </div>
  );
}
