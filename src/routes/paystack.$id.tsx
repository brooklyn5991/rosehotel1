import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { useServerFn } from "@tanstack/react-start";
import { useQuery, useMutation } from "@tanstack/react-query";
import { getReservation, settleFakePayment } from "@/lib/hotel.functions";

const currency = (n: number) =>
  new Intl.NumberFormat("en-NG", { style: "currency", currency: "NGN", maximumFractionDigits: 0 }).format(n);

export const Route = createFileRoute("/paystack/$id")({
  head: () => ({ meta: [{ title: "Secure Payment — Paystack (Test)" }] }),
  component: FakePaystackPage,
});

function FakePaystackPage() {
  const { id } = Route.useParams();
  const navigate = useNavigate();
  const fetchRes = useServerFn(getReservation);
  const settle = useServerFn(settleFakePayment);

  const res = useQuery({ queryKey: ["reservation", id], queryFn: () => fetchRes({ data: { id } }) });

  const mut = useMutation({
    mutationFn: (outcome: "paid" | "failed") => settle({ data: { reservation_id: id, outcome } }),
    onSuccess: (_r, outcome) => {
      navigate({ to: "/reservation/$id", params: { id }, search: { paid: outcome === "paid" ? 1 : 0 } });
    },
  });

  if (res.isLoading) return <div className="min-h-screen bg-slate-100 flex items-center justify-center text-slate-600">Loading payment…</div>;
  if (!res.data) return <div className="min-h-screen bg-slate-100 flex items-center justify-center text-slate-600">Reservation not found</div>;
  const r = res.data as { total_ngn: number; guest_email: string; guest_name: string; confirmation_code: string; payment_status: string; check_in: string; check_out: string };

  const alreadyPaid = r.payment_status === "paid";

  return (
    <div className="min-h-screen bg-slate-100 font-sans">
      {/* Fake Paystack header */}
      <div className="bg-white border-b border-slate-200">
        <div className="max-w-2xl mx-auto px-6 py-4 flex items-center gap-2">
          <div className="w-8 h-8 rounded bg-[#0BA4DB] flex items-center justify-center text-white font-bold text-sm">P</div>
          <span className="font-semibold text-slate-800">Paystack</span>
          <span className="ml-auto text-xs text-amber-600 bg-amber-100 px-2 py-1 rounded">TEST MODE</span>
        </div>
      </div>

      <main className="max-w-2xl mx-auto px-6 py-10">
        <div className="bg-white rounded-lg shadow-sm border border-slate-200 overflow-hidden">
          <div className="bg-[#0BA4DB] text-white px-6 py-5">
            <p className="text-xs opacity-80 mb-1">Pay Garen&rsquo;s Garden Hotel</p>
            <p className="text-3xl font-bold">{currency(r.total_ngn)}</p>
            <p className="text-xs opacity-80 mt-2">{r.guest_email}</p>
          </div>

          <div className="p-6 space-y-4">
            <div className="grid grid-cols-2 gap-3 text-sm">
              <div><p className="text-slate-500 text-xs">Guest</p><p className="text-slate-800">{r.guest_name}</p></div>
              <div><p className="text-slate-500 text-xs">Confirmation</p><p className="text-slate-800 font-mono">{r.confirmation_code}</p></div>
              <div><p className="text-slate-500 text-xs">Check-in</p><p className="text-slate-800">{r.check_in}</p></div>
              <div><p className="text-slate-500 text-xs">Check-out</p><p className="text-slate-800">{r.check_out}</p></div>
            </div>

            {alreadyPaid ? (
              <div className="rounded bg-green-50 border border-green-200 p-4 text-sm text-green-800">
                This reservation has already been paid.
              </div>
            ) : (
              <>
                <div className="border-t border-slate-200 pt-4 space-y-3">
                  <p className="text-xs uppercase tracking-wider text-slate-500">Card details (test)</p>
                  <input readOnly value="4084 0840 8408 4081" className="w-full border border-slate-200 rounded px-3 py-2 text-slate-700 bg-slate-50" />
                  <div className="grid grid-cols-2 gap-3">
                    <input readOnly value="12 / 30" className="border border-slate-200 rounded px-3 py-2 text-slate-700 bg-slate-50" />
                    <input readOnly value="408" className="border border-slate-200 rounded px-3 py-2 text-slate-700 bg-slate-50" />
                  </div>
                </div>

                <button
                  onClick={() => mut.mutate("paid")}
                  disabled={mut.isPending}
                  className="w-full bg-[#0BA4DB] hover:bg-[#0994c5] text-white font-semibold py-3 rounded transition-colors disabled:opacity-50"
                >
                  {mut.isPending ? "Processing…" : `Pay ${currency(r.total_ngn)}`}
                </button>
                <button
                  onClick={() => mut.mutate("failed")}
                  disabled={mut.isPending}
                  className="w-full text-slate-500 hover:text-slate-700 text-sm py-2"
                >
                  Cancel payment
                </button>
                <p className="text-[10px] text-center text-slate-400 pt-2">
                  This is a simulated Paystack gateway for testing. No real charge is made.
                </p>
              </>
            )}
          </div>
        </div>
      </main>
    </div>
  );
}
