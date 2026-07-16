
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS btree_gist;

-- ================= ROLES =================
DO $$ BEGIN
  CREATE TYPE public.app_role AS ENUM ('owner','manager');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE TABLE IF NOT EXISTS public.user_roles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  role public.app_role NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, role)
);
GRANT SELECT ON public.user_roles TO authenticated;
GRANT ALL ON public.user_roles TO service_role;
ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.has_role(_user_id uuid, _role public.app_role)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$ SELECT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = _user_id AND role = _role) $$;
REVOKE EXECUTE ON FUNCTION public.has_role(uuid, public.app_role) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.has_role(uuid, public.app_role) TO authenticated, service_role;

CREATE POLICY "Users read own roles" ON public.user_roles FOR SELECT TO authenticated
  USING (auth.uid() = user_id OR public.has_role(auth.uid(),'owner'));

-- ================= ROOMS =================
CREATE TABLE IF NOT EXISTS public.rooms (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  room_number text NOT NULL UNIQUE,
  tier text NOT NULL,
  name text NOT NULL,
  description text NOT NULL,
  price_ngn integer NOT NULL,
  floor integer NOT NULL,
  bed text NOT NULL,
  size text NOT NULL,
  sleeps integer NOT NULL DEFAULT 2,
  image_slug text NOT NULL,
  features jsonb NOT NULL DEFAULT '[]'::jsonb,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT ON public.rooms TO anon, authenticated;
GRANT ALL ON public.rooms TO service_role;
ALTER TABLE public.rooms ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Public can view active rooms" ON public.rooms FOR SELECT TO anon, authenticated
  USING (is_active = true);
CREATE POLICY "Owner manages rooms" ON public.rooms FOR ALL TO authenticated
  USING (public.has_role(auth.uid(),'owner')) WITH CHECK (public.has_role(auth.uid(),'owner'));

-- ================= RESERVATIONS =================
CREATE TABLE IF NOT EXISTS public.reservations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  room_id uuid NOT NULL REFERENCES public.rooms(id) ON DELETE RESTRICT,
  guest_name text NOT NULL,
  guest_email text NOT NULL,
  guest_phone text NOT NULL,
  check_in date NOT NULL,
  check_out date NOT NULL,
  nights integer GENERATED ALWAYS AS ((check_out - check_in)) STORED,
  total_ngn integer NOT NULL,
  status text NOT NULL DEFAULT 'pending',
  source text NOT NULL DEFAULT 'online',
  payment_status text NOT NULL DEFAULT 'pending',
  payment_reference text,
  confirmation_code text NOT NULL DEFAULT upper(substr(replace(gen_random_uuid()::text,'-',''),1,8)),
  created_by uuid,
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (check_out > check_in),
  CHECK (char_length(guest_name) BETWEEN 2 AND 120),
  CHECK (guest_email ~* '^[^@]+@[^@]+\.[^@]+$'),
  CHECK (char_length(guest_phone) BETWEEN 6 AND 30),
  CHECK (status IN ('pending','confirmed','checked_in','checked_out','cancelled')),
  CHECK (source IN ('online','walk_in')),
  CHECK (payment_status IN ('pending','paid','failed','refunded')),
  EXCLUDE USING gist (
    room_id WITH =,
    daterange(check_in, check_out, '[)') WITH &&
  ) WHERE (status IN ('pending','confirmed','checked_in'))
);
GRANT SELECT, INSERT, UPDATE ON public.reservations TO anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.reservations TO authenticated;
GRANT ALL ON public.reservations TO service_role;
ALTER TABLE public.reservations ENABLE ROW LEVEL SECURITY;

-- Anon (public guest) policies: read + create + complete-payment on their own row.
-- The id is an unguessable UUID and is the access token for the fake-paystack flow.
CREATE POLICY "Anon can read reservations" ON public.reservations FOR SELECT TO anon
  USING (true);
CREATE POLICY "Anon can create online booking" ON public.reservations FOR INSERT TO anon
  WITH CHECK (
    source = 'online'
    AND created_by IS NULL
    AND status IN ('pending','confirmed')
    AND payment_status IN ('pending','paid')
  );
CREATE POLICY "Anon can settle payment" ON public.reservations FOR UPDATE TO anon
  USING (payment_status = 'pending' AND source = 'online')
  WITH CHECK (payment_status IN ('paid','failed') AND source = 'online');

-- Staff/owner
CREATE POLICY "Staff read reservations" ON public.reservations FOR SELECT TO authenticated
  USING (public.has_role(auth.uid(),'owner') OR public.has_role(auth.uid(),'manager'));
CREATE POLICY "Staff create reservations" ON public.reservations FOR INSERT TO authenticated
  WITH CHECK (public.has_role(auth.uid(),'owner') OR public.has_role(auth.uid(),'manager'));
CREATE POLICY "Staff update reservations" ON public.reservations FOR UPDATE TO authenticated
  USING (public.has_role(auth.uid(),'owner') OR public.has_role(auth.uid(),'manager'))
  WITH CHECK (public.has_role(auth.uid(),'owner') OR public.has_role(auth.uid(),'manager'));
CREATE POLICY "Owner delete reservations" ON public.reservations FOR DELETE TO authenticated
  USING (public.has_role(auth.uid(),'owner'));

-- ================= COMPLAINTS =================
CREATE TABLE IF NOT EXISTS public.complaints (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  guest_name text NOT NULL,
  guest_contact text NOT NULL,
  subject text NOT NULL,
  message text NOT NULL,
  is_read boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (char_length(guest_name) BETWEEN 2 AND 120),
  CHECK (char_length(guest_contact) BETWEEN 3 AND 120),
  CHECK (char_length(subject) BETWEEN 2 AND 140),
  CHECK (char_length(message) BETWEEN 5 AND 4000)
);
GRANT INSERT ON public.complaints TO anon;
GRANT SELECT, INSERT, UPDATE ON public.complaints TO authenticated;
GRANT ALL ON public.complaints TO service_role;
ALTER TABLE public.complaints ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anon submit complaints" ON public.complaints FOR INSERT TO anon WITH CHECK (true);
CREATE POLICY "Staff submit complaints" ON public.complaints FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY "Owner reads complaints" ON public.complaints FOR SELECT TO authenticated
  USING (public.has_role(auth.uid(),'owner'));
CREATE POLICY "Owner updates complaints" ON public.complaints FOR UPDATE TO authenticated
  USING (public.has_role(auth.uid(),'owner')) WITH CHECK (public.has_role(auth.uid(),'owner'));

-- ================= SEED 21 ROOMS =================
INSERT INTO public.rooms (room_number, tier, name, description, price_ngn, floor, bed, size, sleeps, image_slug, features) VALUES
('101','Standard','Garden Standard','A calm, well-appointed room with garden-facing view and warm brass finishes.',45000,0,'Queen','24 m²',2,'standard','["Free Wi-Fi","55\" Smart TV","Air conditioning","En-suite bathroom","Complimentary breakfast"]'),
('102','Standard','Garden Standard','A calm, well-appointed room with garden-facing view and warm brass finishes.',45000,0,'Queen','24 m²',2,'standard','["Free Wi-Fi","55\" Smart TV","Air conditioning","En-suite bathroom","Complimentary breakfast"]'),
('103','Standard','Garden Standard','A calm, well-appointed room with garden-facing view and warm brass finishes.',45000,0,'Queen','24 m²',2,'standard','["Free Wi-Fi","55\" Smart TV","Air conditioning","En-suite bathroom","Complimentary breakfast"]'),
('104','Standard','Garden Standard','A calm, well-appointed room with garden-facing view and warm brass finishes.',45000,0,'Queen','24 m²',2,'standard','["Free Wi-Fi","55\" Smart TV","Air conditioning","En-suite bathroom","Complimentary breakfast"]'),
('105','Standard','Garden Standard','A calm, well-appointed room with garden-facing view and warm brass finishes.',45000,0,'Queen','24 m²',2,'standard','["Free Wi-Fi","55\" Smart TV","Air conditioning","En-suite bathroom","Complimentary breakfast"]'),
('106','Standard','Garden Standard','A calm, well-appointed room with garden-facing view and warm brass finishes.',45000,0,'Queen','24 m²',2,'standard','["Free Wi-Fi","55\" Smart TV","Air conditioning","En-suite bathroom","Complimentary breakfast"]'),
('107','Standard','Garden Standard','A calm, well-appointed room with garden-facing view and warm brass finishes.',45000,0,'Queen','24 m²',2,'standard','["Free Wi-Fi","55\" Smart TV","Air conditioning","En-suite bathroom","Complimentary breakfast"]'),
('108','Standard','Garden Standard','A calm, well-appointed room with garden-facing view and warm brass finishes.',45000,0,'Queen','24 m²',2,'standard','["Free Wi-Fi","55\" Smart TV","Air conditioning","En-suite bathroom","Complimentary breakfast"]'),
('201','Deluxe','Deluxe Retreat','A spacious deluxe suite with a king bed, seating area, and marble bathroom.',75000,1,'King','34 m²',2,'deluxe','["Free Wi-Fi","65\" Smart TV","Air conditioning","Marble bathroom","Mini bar","Complimentary breakfast","In-room safe"]'),
('202','Deluxe','Deluxe Retreat','A spacious deluxe suite with a king bed, seating area, and marble bathroom.',75000,1,'King','34 m²',2,'deluxe','["Free Wi-Fi","65\" Smart TV","Air conditioning","Marble bathroom","Mini bar","Complimentary breakfast","In-room safe"]'),
('203','Deluxe','Deluxe Retreat','A spacious deluxe suite with a king bed, seating area, and marble bathroom.',75000,1,'King','34 m²',2,'deluxe','["Free Wi-Fi","65\" Smart TV","Air conditioning","Marble bathroom","Mini bar","Complimentary breakfast","In-room safe"]'),
('204','Deluxe','Deluxe Retreat','A spacious deluxe suite with a king bed, seating area, and marble bathroom.',75000,1,'King','34 m²',2,'deluxe','["Free Wi-Fi","65\" Smart TV","Air conditioning","Marble bathroom","Mini bar","Complimentary breakfast","In-room safe"]'),
('205','Deluxe','Deluxe Retreat','A spacious deluxe suite with a king bed, seating area, and marble bathroom.',75000,1,'King','34 m²',2,'deluxe','["Free Wi-Fi","65\" Smart TV","Air conditioning","Marble bathroom","Mini bar","Complimentary breakfast","In-room safe"]'),
('206','Deluxe','Deluxe Retreat','A spacious deluxe suite with a king bed, seating area, and marble bathroom.',75000,1,'King','34 m²',2,'deluxe','["Free Wi-Fi","65\" Smart TV","Air conditioning","Marble bathroom","Mini bar","Complimentary breakfast","In-room safe"]'),
('207','Deluxe','Deluxe Retreat','A spacious deluxe suite with a king bed, seating area, and marble bathroom.',75000,1,'King','34 m²',2,'deluxe','["Free Wi-Fi","65\" Smart TV","Air conditioning","Marble bathroom","Mini bar","Complimentary breakfast","In-room safe"]'),
('208','Deluxe','Deluxe Retreat','A spacious deluxe suite with a king bed, seating area, and marble bathroom.',75000,1,'King','34 m²',2,'deluxe','["Free Wi-Fi","65\" Smart TV","Air conditioning","Marble bathroom","Mini bar","Complimentary breakfast","In-room safe"]'),
('209','Standard','Garden Standard','A calm, well-appointed room with garden-facing view and warm brass finishes.',45000,1,'Queen','24 m²',2,'standard','["Free Wi-Fi","55\" Smart TV","Air conditioning","En-suite bathroom","Complimentary breakfast"]'),
('210','Standard','Garden Standard','A calm, well-appointed room with garden-facing view and warm brass finishes.',45000,1,'Queen','24 m²',2,'standard','["Free Wi-Fi","55\" Smart TV","Air conditioning","En-suite bathroom","Complimentary breakfast"]'),
('211','Standard','Garden Standard','A calm, well-appointed room with garden-facing view and warm brass finishes.',45000,1,'Queen','24 m²',2,'standard','["Free Wi-Fi","55\" Smart TV","Air conditioning","En-suite bathroom","Complimentary breakfast"]'),
('212','Standard','Garden Standard','A calm, well-appointed room with garden-facing view and warm brass finishes.',45000,1,'Queen','24 m²',2,'standard','["Free Wi-Fi","55\" Smart TV","Air conditioning","En-suite bathroom","Complimentary breakfast"]'),
('213','Executive','Executive Suite','Our flagship suite: private lounge, king bed, panoramic view, and premium amenities.',180000,1,'King','62 m²',3,'executive','["Free Wi-Fi","75\" Smart TV","Private lounge","Air conditioning","Marble bathroom with tub","Premium mini bar","Butler service","Complimentary breakfast","In-room safe","Airport pickup"]');

-- ================= HOTEL OWNER ACCOUNT =================
INSERT INTO auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at,
  raw_app_meta_data, raw_user_meta_data,
  is_super_admin, confirmation_token, email_change, email_change_token_new, recovery_token
)
SELECT
  '00000000-0000-0000-0000-000000000000'::uuid,
  gen_random_uuid(),
  'authenticated','authenticated',
  'omoruyirosemary@yahoo.com',
  crypt('Hotel1best$424', gen_salt('bf')),
  now(), now(), now(),
  '{"provider":"email","providers":["email"]}'::jsonb,
  '{}'::jsonb,
  false, '', '', '', ''
WHERE NOT EXISTS (SELECT 1 FROM auth.users WHERE email = 'omoruyirosemary@yahoo.com');

INSERT INTO auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
SELECT gen_random_uuid(), u.id, u.id::text,
  jsonb_build_object('sub', u.id::text, 'email', u.email, 'email_verified', true),
  'email', now(), now(), now()
FROM auth.users u
WHERE u.email = 'omoruyirosemary@yahoo.com'
  AND NOT EXISTS (SELECT 1 FROM auth.identities i WHERE i.user_id = u.id AND i.provider = 'email');

INSERT INTO public.user_roles (user_id, role)
SELECT u.id, 'owner'::public.app_role FROM auth.users u
WHERE u.email = 'omoruyirosemary@yahoo.com'
ON CONFLICT (user_id, role) DO NOTHING;
