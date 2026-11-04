-- Content tables are rebuilt from the content/ folder by `npm run content:import`.
create table languages (
  code text primary key,
  native text not null,
  sort int not null default 0
);

create table translations (
  lang text not null,
  key text not null,
  value text not null,
  primary key (lang, key)
);

create table citizenships (
  id text primary key,
  grp text not null,
  names jsonb not null,
  status text not null default 'demo',
  note text
);

create table situations (
  id text primary key,
  sort int not null default 0,
  names jsonb not null
);

create table cities (
  id text primary key,
  name text not null,
  region text not null,
  lat double precision not null,
  lon double precision not null,
  aliases text[] not null default '{}',
  pilot boolean not null default false,
  districts jsonb
);

create table documents (
  id text primary key,
  sort int not null default 0,
  situations text[] not null default '{}',
  necessity text not null check (necessity in ('mandatory','conditional','service')),
  status text not null check (status in ('verified','demo','draft')),
  checked_at date,
  rules jsonb not null,
  title jsonb not null,
  summary jsonb not null,
  details jsonb not null default '{}',
  deadline jsonb,
  cost jsonb,
  sources jsonb not null default '[]',
  where_kind text not null default 'institutions' check (where_kind in ('institutions','self','none')),
  where_note text,
  official_search jsonb
);

create table institutions (
  id text primary key,
  city_id text not null references cities(id),
  name jsonb not null,
  services text[] not null default '{}',
  mode text not null check (mode in ('in_person','online','both')),
  address text,
  map_query text,
  lat double precision,
  lon double precision,
  hours text,
  phone text,
  site text,
  booking_url text,
  serves jsonb not null,
  citizenships text[],
  status text not null check (status in ('verified','demo','draft')),
  checked_at date,
  sources jsonb not null default '[]',
  note text
);

create table tips (
  id text primary key,
  topic text not null,
  city_id text references cities(id),
  kind text not null default 'editorial',
  status text not null check (status in ('verified','demo','draft')),
  updated_at date not null,
  title jsonb not null,
  body jsonb not null,
  source jsonb
);

create table settings (
  key text primary key,
  value jsonb not null
);

create table users (
  id bigserial primary key,
  email text not null unique,
  password_hash text not null,
  display_name text,
  role text not null default 'user' check (role in ('user','moderator')),
  created_at timestamptz not null default now()
);

create table sessions (
  token_hash text primary key,
  user_id bigint not null references users(id) on delete cascade,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null
);

create table listings (
  id bigserial primary key,
  author_id bigint not null references users(id),
  category text not null check (category in ('work','housing','market','services','free')),
  title text not null,
  body text not null,
  lang text not null,
  city_id text not null references cities(id),
  price text,
  extra jsonb not null default '{}',
  duration_days int not null default 14,
  status text not null check (status in ('pending','published','withdrawn','hidden','rejected')),
  moderation_note text,
  reviewed_at timestamptz,
  reviewed_by bigint references users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  published_at timestamptz,
  expires_at timestamptz
);
create index listings_public_idx on listings (status, category, city_id, expires_at);

create table listing_responses (
  id bigserial primary key,
  listing_id bigint not null references listings(id) on delete cascade,
  from_user_id bigint not null references users(id),
  message text not null,
  contact text,
  created_at timestamptz not null default now()
);

create table reports (
  id bigserial primary key,
  listing_id bigint not null references listings(id) on delete cascade,
  reporter_id bigint not null references users(id),
  reason text not null,
  status text not null default 'open' check (status in ('open','dismissed','actioned')),
  created_at timestamptz not null default now(),
  unique (listing_id, reporter_id)
);

create table moderation_log (
  id bigserial primary key,
  listing_id bigint references listings(id) on delete set null,
  moderator_id bigint references users(id),
  action text not null,
  reason text,
  created_at timestamptz not null default now()
);
