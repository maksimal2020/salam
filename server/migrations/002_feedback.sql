-- Обратная связь от пользователей: сообщения о неточностях и пожелания, что добавить.
-- Отправить может кто угодно (аккаунт не обязателен); если пользователь вошёл — запоминаем его.
create table feedback (
  id bigserial primary key,
  user_id bigint references users(id) on delete set null,
  email text,
  message text not null,
  lang text,
  status text not null default 'new' check (status in ('new', 'resolved')),
  created_at timestamptz not null default now()
);
create index feedback_status_idx on feedback (status, created_at desc);
