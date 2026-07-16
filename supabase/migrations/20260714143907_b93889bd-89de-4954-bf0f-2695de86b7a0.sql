
-- Enable btree_gist for exclusion constraint (date-range overlap protection)
CREATE EXTENSION IF NOT EXISTS btree_gist;

-- App roles enum
CREATE TYPE public.app_role AS ENUM ('owner', 'manager');

-- ---------------- user_roles ----------------
CREATE TABLE public.user_roles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role public.app_role NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(user_id, role)
);
GRANT SELECT ON public.user_roles TO authenticated;
GRANT ALL ON public.user_roles TO service_role;
ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.has_role(_user_id uuid, _role public.app_role)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = _user_id AND role = _role)
$$;

CREATE POLICY "users read own roles" ON public.user_roles
  FOR SELECT TO authenticated USING (auth.uid() = user_id);

-- ---------------- rooms ----------------
CREATE TABLE public.rooms (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  room_number text NOT NULL UNIQUE,
  floor int NOT NULL,
  tier text NOT NULL CHECK (tier IN ('Standard','Deluxe','Executive')),
  name text NOT NULL,
  description text NOT NULL,
  price_ngn int NOT NULL,
  bed text NOT NULL,
  size text NOT NULL,
  sleeps int NOT NULL,
  image_slug text NOT NULL,
  features jsonb NOT NULL DEFAULT '[]'::jsonb,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT ON public.rooms TO anon, authenticated;
GRANT ALL ON public.rooms TO service_role;
ALTER TABLE public.rooms ENABLE ROW LEVEL SECURITY;
CREATE POLICY "rooms are public" ON public.rooms FOR SELECT USING (true);
CREATE POLICY "owners manage rooms" ON public.rooms FOR ALL TO authenticated
  USING (public.has_role(auth.uid(),'owner')) WITH CHECK (public.has_role(auth.uid(),'owner'));

-- ---------------- reservations ----------------
CREATE TABLE public.reservations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  room_id uuid NOT NULL REFERENCES public.rooms(id) ON DELETE RESTRICT,
  guest_name text NOT NULL,
  guest_email text NOT NULL,
  guest_phone text NOT NULL,
  check_in date NOT NULL,
  check_out date NOT NULL,
  nights int GENERATED ALWAYS AS ((check_out - check_in)) STORED,
  total_ngn int NOT NULL,
  status text NOT NULL DEFAULT 'confirmed' CHECK (status IN ('confirmed','checked_in','checked_out','cancelled')),
  source text NOT NULL DEFAULT 'online' CHECK (source IN ('online','walk_in')),
  notes text,
  confirmation_code text NOT NULL UNIQUE DEFAULT upper(substr(md5(random()::text),1,8)),
  created_by uuid REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (check_out > check_in),
  -- Prevent overlapping active reservations for same room
  EXCLUDE USING gist (
    room_id WITH =,
    daterange(check_in, check_out, '[)') WITH &&
  ) WHERE (status IN ('confirmed','checked_in'))
);
GRANT SELECT, INSERT, UPDATE ON public.reservations TO authenticated;
GRANT INSERT ON public.reservations TO anon;
GRANT ALL ON public.reservations TO service_role;
ALTER TABLE public.reservations ENABLE ROW LEVEL SECURITY;

-- Anyone can create an online booking (server function validates)
CREATE POLICY "public can create online reservations" ON public.reservations
  FOR INSERT TO anon WITH CHECK (source = 'online');
CREATE POLICY "auth can create reservations" ON public.reservations
  FOR INSERT TO authenticated WITH CHECK (true);
-- Only staff can view reservations
CREATE POLICY "staff view reservations" ON public.reservations FOR SELECT TO authenticated
  USING (public.has_role(auth.uid(),'owner') OR public.has_role(auth.uid(),'manager'));
CREATE POLICY "staff update reservations" ON public.reservations FOR UPDATE TO authenticated
  USING (public.has_role(auth.uid(),'owner') OR public.has_role(auth.uid(),'manager'));

CREATE INDEX ON public.reservations(room_id, check_in, check_out);
CREATE INDEX ON public.reservations(status);

-- ---------------- complaints ----------------
CREATE TABLE public.complaints (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  guest_name text NOT NULL,
  guest_contact text NOT NULL,
  subject text NOT NULL,
  message text NOT NULL,
  is_read boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT INSERT ON public.complaints TO anon, authenticated;
GRANT SELECT, UPDATE ON public.complaints TO authenticated;
GRANT ALL ON public.complaints TO service_role;
ALTER TABLE public.complaints ENABLE ROW LEVEL SECURITY;
CREATE POLICY "anyone submits complaints" ON public.complaints FOR INSERT WITH CHECK (true);
CREATE POLICY "owner reads complaints" ON public.complaints FOR SELECT TO authenticated
  USING (public.has_role(auth.uid(),'owner'));
CREATE POLICY "owner updates complaints" ON public.complaints FOR UPDATE TO authenticated
  USING (public.has_role(auth.uid(),'owner'));

-- ---------------- seed rooms ----------------
-- 12 Standard, 8 Deluxe, 1 Executive. Ground floor 101-108, first floor 201-213.
INSERT INTO public.rooms (room_number, floor, tier, name, description, price_ngn, bed, size, sleeps, image_slug, features) VALUES
-- Ground floor: 101-108 Standard
('101',1,'Standard','Standard Room 101','Ground-floor standard room with courtyard-side window, warm wood floors, and a considered en-suite.',45000,'Queen orthopedic','22 m²',2,'room-standard','["Queen orthopedic mattress","Split-unit air conditioning","Smart TV with DSTV","En-suite hot-water bath","Tea & coffee kettle","Fiber Wi-Fi"]'::jsonb),
('102',1,'Standard','Standard Room 102','Quiet standard room facing the interior garden path.',45000,'Queen orthopedic','22 m²',2,'room-standard','["Queen orthopedic mattress","Split-unit AC","Smart TV","En-suite bath","Kettle","Fiber Wi-Fi"]'::jsonb),
('103',1,'Standard','Standard Room 103','Compact and quiet, ideal for a single business traveller.',45000,'Queen orthopedic','22 m²',2,'room-standard','["Queen orthopedic","Split AC","Smart TV","En-suite","Kettle","Wi-Fi"]'::jsonb),
('104',1,'Standard','Standard Room 104','Standard comfort with a workstation and reading chair.',45000,'Queen orthopedic','22 m²',2,'room-standard','["Queen orthopedic","Split AC","Smart TV","En-suite","Kettle","Wi-Fi"]'::jsonb),
('105',1,'Standard','Standard Room 105','Ground floor, easy access from the reception lobby.',45000,'Queen orthopedic','22 m²',2,'room-standard','["Queen orthopedic","Split AC","Smart TV","En-suite","Kettle","Wi-Fi"]'::jsonb),
('106',1,'Standard','Standard Room 106','A warm, quiet standard with soft gold lighting.',45000,'Queen orthopedic','22 m²',2,'room-standard','["Queen orthopedic","Split AC","Smart TV","En-suite","Kettle","Wi-Fi"]'::jsonb),
('107',1,'Standard','Standard Room 107','Standard room close to the garden courtyard.',45000,'Queen orthopedic','22 m²',2,'room-standard','["Queen orthopedic","Split AC","Smart TV","En-suite","Kettle","Wi-Fi"]'::jsonb),
('108',1,'Standard','Standard Room 108','Corner standard, extra window and additional daylight.',45000,'Queen orthopedic','22 m²',2,'room-standard','["Queen orthopedic","Split AC","Smart TV","En-suite","Kettle","Wi-Fi"]'::jsonb),
-- First floor: 201-208 Deluxe, 209-212 Standard, 213 Executive
('201',2,'Deluxe','Deluxe Room 201','Upstairs deluxe with king bed and walk-in glass shower.',68000,'King orthopedic','30 m²',2,'room-deluxe','["King orthopedic","Split AC","Smart TV","Walk-in shower","Kettle","Fiber Wi-Fi","Work desk"]'::jsonb),
('202',2,'Deluxe','Deluxe Room 202','Larger footprint deluxe with garden-view balcony.',68000,'King orthopedic','30 m²',2,'room-deluxe','["King orthopedic","Split AC","Smart TV","Walk-in shower","Kettle","Wi-Fi","Balcony"]'::jsonb),
('203',2,'Deluxe','Deluxe Room 203','Our most-requested layout — balanced space and quiet.',68000,'King orthopedic','30 m²',2,'room-deluxe','["King orthopedic","Split AC","Smart TV","Walk-in shower","Kettle","Wi-Fi"]'::jsonb),
('204',2,'Deluxe','Deluxe Room 204','Deluxe with reading lounge chair and executive desk.',68000,'King orthopedic','30 m²',2,'room-deluxe','["King orthopedic","Split AC","Smart TV","Walk-in shower","Kettle","Wi-Fi","Lounge chair"]'::jsonb),
('205',2,'Deluxe','Deluxe Room 205','Deluxe with soft gold accents and a wide window.',68000,'King orthopedic','30 m²',2,'room-deluxe','["King orthopedic","Split AC","Smart TV","Walk-in shower","Kettle","Wi-Fi"]'::jsonb),
('206',2,'Deluxe','Deluxe Room 206','Deluxe with rain-shower fitting and heated towel bar.',68000,'King orthopedic','30 m²',2,'room-deluxe','["King orthopedic","Split AC","Smart TV","Rain shower","Kettle","Wi-Fi"]'::jsonb),
('207',2,'Deluxe','Deluxe Room 207','Deluxe with corner window and generous wardrobe.',68000,'King orthopedic','30 m²',2,'room-deluxe','["King orthopedic","Split AC","Smart TV","Walk-in shower","Kettle","Wi-Fi","Wardrobe"]'::jsonb),
('208',2,'Deluxe','Deluxe Room 208','Deluxe overlooking the courtyard — evening favourite.',68000,'King orthopedic','30 m²',2,'room-deluxe','["King orthopedic","Split AC","Smart TV","Walk-in shower","Kettle","Wi-Fi","Courtyard view"]'::jsonb),
('209',2,'Standard','Standard Room 209','Upstairs standard, quieter than the ground floor.',45000,'Queen orthopedic','22 m²',2,'room-standard','["Queen orthopedic","Split AC","Smart TV","En-suite","Kettle","Wi-Fi"]'::jsonb),
('210',2,'Standard','Standard Room 210','Upstairs standard with wide window and desk.',45000,'Queen orthopedic','22 m²',2,'room-standard','["Queen orthopedic","Split AC","Smart TV","En-suite","Kettle","Wi-Fi"]'::jsonb),
('211',2,'Standard','Standard Room 211','Standard with corridor-side privacy and blackout blinds.',45000,'Queen orthopedic','22 m²',2,'room-standard','["Queen orthopedic","Split AC","Smart TV","En-suite","Blackout blinds","Wi-Fi"]'::jsonb),
('212',2,'Standard','Standard Room 212','Corner standard, extra window and additional daylight.',45000,'Queen orthopedic','22 m²',2,'room-standard','["Queen orthopedic","Split AC","Smart TV","En-suite","Kettle","Wi-Fi"]'::jsonb),
('213',2,'Executive','Executive Suite 213','Our signature executive suite — lounge area, walk-in wardrobe, and private balcony overlooking the garden.',120000,'California king','45 m²',3,'room-executive','["California king","Split AC","55\" Smart TV","Rain shower","Bathtub","Kettle","Espresso machine","Balcony","Lounge area","Wardrobe","Fiber Wi-Fi"]'::jsonb);
