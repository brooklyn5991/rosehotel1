-- 1) Restrict SECURITY DEFINER has_role from anon/public (authenticated still needs it for RLS)
REVOKE EXECUTE ON FUNCTION public.has_role(uuid, app_role) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.has_role(uuid, app_role) FROM anon;

-- 2) Replace overly permissive authenticated INSERT policy on reservations
DROP POLICY IF EXISTS "auth can create reservations" ON public.reservations;
CREATE POLICY "staff create reservations"
  ON public.reservations
  FOR INSERT
  TO authenticated
  WITH CHECK (public.has_role(auth.uid(), 'owner'::app_role) OR public.has_role(auth.uid(), 'manager'::app_role));

-- 3) Validation constraints on complaints (prevents oversized/empty spam payloads)
ALTER TABLE public.complaints
  ADD CONSTRAINT complaints_guest_name_len CHECK (char_length(guest_name) BETWEEN 2 AND 120),
  ADD CONSTRAINT complaints_guest_contact_len CHECK (char_length(guest_contact) BETWEEN 3 AND 120),
  ADD CONSTRAINT complaints_subject_len CHECK (char_length(subject) BETWEEN 2 AND 140),
  ADD CONSTRAINT complaints_message_len CHECK (char_length(message) BETWEEN 5 AND 4000);

-- 4) Validation constraints + tightened anon insert policy on reservations
ALTER TABLE public.reservations
  ADD CONSTRAINT reservations_guest_name_len CHECK (char_length(guest_name) BETWEEN 2 AND 120),
  ADD CONSTRAINT reservations_guest_email_fmt CHECK (guest_email ~* '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'),
  ADD CONSTRAINT reservations_guest_phone_len CHECK (char_length(guest_phone) BETWEEN 6 AND 30),
  ADD CONSTRAINT reservations_dates_valid CHECK (check_out > check_in),
  ADD CONSTRAINT reservations_total_nonneg CHECK (total_ngn >= 0);

DROP POLICY IF EXISTS "public can create online reservations" ON public.reservations;
CREATE POLICY "public can create online reservations"
  ON public.reservations
  FOR INSERT
  TO anon
  WITH CHECK (
    source = 'online'
    AND status = 'confirmed'
    AND created_by IS NULL
  );

-- 5) Add owner-only DELETE policy so reservations have full lifecycle coverage
CREATE POLICY "owners delete reservations"
  ON public.reservations
  FOR DELETE
  TO authenticated
  USING (public.has_role(auth.uid(), 'owner'::app_role));