import { createFileRoute, useNavigate, Link } from "@tanstack/react-router";
import { useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { SiteNav } from "@/components/site-nav";
import { SiteFooter } from "@/components/site-footer";

export const Route = createFileRoute("/auth")({
  head: () => ({
    meta: [
      { title: "Staff Sign In — Garen's Garden" },
      { name: "description", content: "Staff and owner sign-in for Garen's Garden." },
    ],
  }),
  component: AuthPage,
});

function AuthPage() {
  const navigate = useNavigate();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    setLoading(true);
    try {
      const { error: sErr } = await supabase.auth.signInWithPassword({ email, password });
      if (sErr) throw sErr;
      navigate({ to: "/dashboard" });
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="bg-deep font-sans text-gold-light min-h-screen antialiased">
      <SiteNav />
      <main className="pt-32 pb-32 px-6 max-w-md mx-auto">
        <p className="text-[10px] uppercase tracking-[0.4em] text-gold mb-4">Staff Portal</p>
        <h1 className="font-serif text-4xl text-gold-light mb-2">Welcome back</h1>
        <p className="text-sm text-zinc-400 mb-8">
          Staff sign-in only. Accounts are managed by the hotel owner.
        </p>

        <form onSubmit={onSubmit} className="space-y-4 bg-warm/10 ring-1 ring-gold/20 p-6">
          <input
            type="email"
            placeholder="Email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            required
            className="w-full bg-deep border border-gold/30 text-gold-light px-3 py-2 focus:border-gold outline-none"
          />
          <input
            type="password"
            placeholder="Password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            required
            minLength={8}
            className="w-full bg-deep border border-gold/30 text-gold-light px-3 py-2 focus:border-gold outline-none"
          />
          {error && <p className="text-sm text-red-300">{error}</p>}
          <button
            type="submit"
            disabled={loading}
            className="w-full bg-gold text-deep py-3 text-sm font-medium hover:bg-gold-light transition-colors disabled:opacity-50"
          >
            {loading ? "Please wait…" : "Sign in"}
          </button>
        </form>

        <Link
          to="/"
          className="mt-6 block text-center text-[10px] uppercase tracking-[0.3em] text-gold/70 hover:text-gold"
        >
          ← Back to hotel
        </Link>
      </main>
      <SiteFooter />
    </div>
  );
}
