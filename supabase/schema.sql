-- Wanderly Supabase Schema
-- Run this in Supabase SQL Editor (Dashboard → SQL Editor → New Query)

-- Enable UUID extension
create extension if not exists "uuid-ossp";

-- ============================================================
-- Users (extends Supabase Auth)
-- ============================================================
create table public.profiles (
    id uuid references auth.users on delete cascade primary key,
    display_name text not null default '',
    email text,
    avatar_url text,
    is_premium boolean not null default false,
    instagram_id text,  -- for future IG bot linking
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

create policy "Users can read own profile"
    on public.profiles for select using (auth.uid() = id);
create policy "Users can update own profile"
    on public.profiles for update using (auth.uid() = id);
create policy "Users can insert own profile"
    on public.profiles for insert with check (auth.uid() = id);

-- Auto-create profile on signup
create or replace function public.handle_new_user()
returns trigger as $$
begin
    insert into public.profiles (id, display_name, email)
    values (
        new.id,
        coalesce(new.raw_user_meta_data->>'full_name', 'Wanderly User'),
        new.email
    );
    return new;
end;
$$ language plpgsql security definer;

create trigger on_auth_user_created
    after insert on auth.users
    for each row execute procedure public.handle_new_user();

-- ============================================================
-- Places
-- ============================================================
create table public.places (
    id uuid primary key default uuid_generate_v4(),
    user_id uuid references public.profiles(id) on delete cascade not null,
    name text not null,
    address text not null default '',
    latitude double precision not null,
    longitude double precision not null,
    google_place_id text,
    category text not null default 'food',
    status text not null default 'wantToGo',
    rating double precision,
    note text,
    source_url text,
    source_platform text not null default 'other',
    source_image_url text,
    extracted_dishes text[] default '{}',
    price_range text,
    recommender text,
    google_rating double precision,
    google_price_level integer,
    opening_hours text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

alter table public.places enable row level security;

create policy "Users can read own places"
    on public.places for select using (auth.uid() = user_id);
create policy "Users can insert own places"
    on public.places for insert with check (auth.uid() = user_id);
create policy "Users can update own places"
    on public.places for update using (auth.uid() = user_id);
create policy "Users can delete own places"
    on public.places for delete using (auth.uid() = user_id);

create index idx_places_user_id on public.places(user_id);
create index idx_places_category on public.places(category);

-- ============================================================
-- Trips
-- ============================================================
create table public.trips (
    id uuid primary key default uuid_generate_v4(),
    user_id uuid references public.profiles(id) on delete cascade not null,
    name text not null,
    city text not null default '',
    start_date date,
    end_date date,
    is_optimized boolean not null default false,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

alter table public.trips enable row level security;

create policy "Users can read own trips"
    on public.trips for select using (auth.uid() = user_id);
create policy "Users can insert own trips"
    on public.trips for insert with check (auth.uid() = user_id);
create policy "Users can update own trips"
    on public.trips for update using (auth.uid() = user_id);
create policy "Users can delete own trips"
    on public.trips for delete using (auth.uid() = user_id);

create index idx_trips_user_id on public.trips(user_id);

-- ============================================================
-- Trip Stops
-- ============================================================
create table public.trip_stops (
    id uuid primary key default uuid_generate_v4(),
    trip_id uuid references public.trips(id) on delete cascade not null,
    place_id uuid references public.places(id) on delete set null,
    place_name text not null,
    day integer not null default 1,
    order_index integer not null default 0,
    start_time text,
    duration integer,  -- minutes
    note text,
    created_at timestamptz not null default now()
);

alter table public.trip_stops enable row level security;

create policy "Users can read own trip stops"
    on public.trip_stops for select
    using (exists (select 1 from public.trips where trips.id = trip_stops.trip_id and trips.user_id = auth.uid()));
create policy "Users can insert own trip stops"
    on public.trip_stops for insert
    with check (exists (select 1 from public.trips where trips.id = trip_stops.trip_id and trips.user_id = auth.uid()));
create policy "Users can update own trip stops"
    on public.trip_stops for update
    using (exists (select 1 from public.trips where trips.id = trip_stops.trip_id and trips.user_id = auth.uid()));
create policy "Users can delete own trip stops"
    on public.trip_stops for delete
    using (exists (select 1 from public.trips where trips.id = trip_stops.trip_id and trips.user_id = auth.uid()));

create index idx_trip_stops_trip_id on public.trip_stops(trip_id);

-- ============================================================
-- Collections
-- ============================================================
create table public.collections (
    id uuid primary key default uuid_generate_v4(),
    user_id uuid references public.profiles(id) on delete cascade not null,
    name text not null,
    emoji text not null default '📍',
    created_at timestamptz not null default now()
);

create table public.collection_places (
    collection_id uuid references public.collections(id) on delete cascade,
    place_id uuid references public.places(id) on delete cascade,
    primary key (collection_id, place_id)
);

alter table public.collections enable row level security;
alter table public.collection_places enable row level security;

create policy "Users can manage own collections"
    on public.collections for all using (auth.uid() = user_id);
create policy "Users can manage own collection places"
    on public.collection_places for all
    using (exists (select 1 from public.collections where collections.id = collection_places.collection_id and collections.user_id = auth.uid()));

-- ============================================================
-- Updated_at trigger
-- ============================================================
create or replace function public.update_updated_at()
returns trigger as $$
begin
    new.updated_at = now();
    return new;
end;
$$ language plpgsql;

create trigger update_profiles_updated_at before update on public.profiles
    for each row execute procedure public.update_updated_at();
create trigger update_places_updated_at before update on public.places
    for each row execute procedure public.update_updated_at();
create trigger update_trips_updated_at before update on public.trips
    for each row execute procedure public.update_updated_at();

-- ============================================================
-- IG Bot Account Linking
-- ============================================================
create table public.ig_bot_links (
    id uuid primary key default uuid_generate_v4(),
    user_id uuid references public.profiles(id) on delete cascade not null,
    ig_user_id text not null unique,      -- Instagram user ID from webhook
    ig_username text,
    verified boolean not null default false,
    verification_code text,               -- 6-digit code sent via DM
    created_at timestamptz not null default now(),
    verified_at timestamptz
);

alter table public.ig_bot_links enable row level security;

create policy "Users can read own ig links"
    on public.ig_bot_links for select using (auth.uid() = user_id);
create policy "Users can delete own ig links"
    on public.ig_bot_links for delete using (auth.uid() = user_id);
-- Insert/update done by backend service role only (webhook handler)

create index idx_ig_bot_links_ig_user_id on public.ig_bot_links(ig_user_id);
create index idx_ig_bot_links_user_id on public.ig_bot_links(user_id);

-- ============================================================
-- Performance Indexes
-- ============================================================

-- Geo bounding box queries (map viewport)
create index idx_places_lat_lng on public.places(latitude, longitude);

-- Full-text search on place name + address
create index idx_places_fts on public.places
    using gin(to_tsvector('english', coalesce(name, '') || ' ' || coalesce(address, '')));

-- Status filter (wantToGo / visited)
create index idx_places_status on public.places(user_id, status);
