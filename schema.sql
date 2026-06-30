-- ============================================================
-- 工廠現場訪查排程系統 - 資料庫結構
-- 在 Supabase 專案的 SQL Editor 貼上整份執行一次即可
-- ============================================================

-- 1. 稽查案件（campaign）：例如「2026年六輕周邊工業區訪查」
create table campaigns (
  id uuid primary key default gen_random_uuid(),
  code text unique not null,            -- 短代碼，用於業者填寫連結，如 "liuching-2026q3"
  name text not null,                   -- 顯示名稱，如「六輕周邊工業區 2026 Q3 現場訪查」
  admin_password text not null,         -- 此案件的管理密碼（簡單防護，非正式帳號系統）
  am_label text not null default '上午', -- 上午時段顯示文字（可自訂，如 09:00-12:00）
  pm_label text not null default '下午', -- 下午時段顯示文字
  created_at timestamptz not null default now()
);

-- 2. 管理者開放的可選日期（每筆代表某案件某一天開放，業者可從中勾選上午/下午）
create table open_slots (
  id uuid primary key default gen_random_uuid(),
  campaign_id uuid not null references campaigns(id) on delete cascade,
  slot_date date not null,
  am_enabled boolean not null default true,  -- 該日上午是否開放給業者選
  pm_enabled boolean not null default true,  -- 該日下午是否開放給業者選
  created_at timestamptz not null default now(),
  unique (campaign_id, slot_date)
);

-- 3. 業者填寫的資料
create table submissions (
  id uuid primary key default gen_random_uuid(),
  campaign_id uuid not null references campaigns(id) on delete cascade,
  control_no text not null,        -- 管制編號
  factory_name text not null,      -- 工廠名稱
  address text not null,           -- 住址
  contact_name text not null,      -- 聯絡人姓名
  contact_phone text not null,     -- 聯絡人電話
  contact_email text,              -- 聯絡人 email（選填）
  notes text,                      -- 備註（選填）
  availability jsonb not null default '[]'::jsonb,
  -- availability 範例: [{"date":"2026-07-06","am":true,"pm":false}, ...]
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index idx_open_slots_campaign on open_slots(campaign_id);
create index idx_submissions_campaign on submissions(campaign_id);

-- ============================================================
-- Row Level Security（權限規則）
-- 設計重點：
--  - 任何人都可以「讀」campaigns 的非敏感欄位 與 open_slots（業者填表頁需要）
--  - 任何人都可以「新增」submissions（業者送出表單）
--  - 「修改/刪除」submissions、「新增/修改/刪除」open_slots、
--    建立 campaigns，一律要求帶有正確的管理密碼（由前端呼叫時驗證）
-- 由於本系統使用「簡單密碼」而非正式帳號登入，安全性是中等強度，
-- 適合內部排程使用，不建議放置高度機敏資料。
-- ============================================================

alter table campaigns enable row level security;
alter table open_slots enable row level security;
alter table submissions enable row level security;

-- campaigns：允許任何人查詢（前端會自行過濾不顯示密碼用途以外的欄位），
-- 但密碼比對一律在資料庫端用 function 驗證，不直接把密碼明文回傳給未驗證的人。
-- 因此這裡用一個 view 排除 admin_password 欄位給「一般讀取」使用。

create view campaigns_public as
  select id, code, name, am_label, pm_label, created_at
  from campaigns;

grant select on campaigns_public to anon;

-- 驗證管理密碼用的 RPC（後端 function），回傳是否正確，不外洩密碼本身
create or replace function verify_campaign_password(p_code text, p_password text)
returns table(campaign_id uuid, campaign_name text, ok boolean)
language sql
security definer
set search_path = public
as $$
  select id, name,
    (admin_password = p_password) as ok
  from campaigns
  where code = p_code;
$$;

grant execute on function verify_campaign_password(text, text) to anon;

-- 建立新案件用的 RPC（需要知道一組「總管理密碼」才能建立，可在前端寫死或用環境變數，
-- 這裡先用一個簡單寫法：建立案件本身不設限，因為通常只有您自己會用到「新增案件」介面）
-- 若想更嚴謹，可自行調整 master_key 比對邏輯

-- open_slots 讀取：所有人可讀（業者填表要看開放日期）
create policy open_slots_select on open_slots
  for select using (true);

-- open_slots 新增/修改/刪除：交由前端先呼叫 verify_campaign_password 驗證通過後，
-- 使用帶有 service role 權限的 RPC 執行（更安全，避免 anon key 直接擁有寫入權）

create or replace function admin_upsert_open_slot(
  p_code text, p_password text, p_date date, p_am boolean, p_pm boolean
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_campaign_id uuid;
  v_ok boolean;
begin
  select id, (admin_password = p_password) into v_campaign_id, v_ok
  from campaigns where code = p_code;

  if v_campaign_id is null then
    raise exception '案件不存在';
  end if;
  if not v_ok then
    raise exception '密碼錯誤';
  end if;

  insert into open_slots (campaign_id, slot_date, am_enabled, pm_enabled)
  values (v_campaign_id, p_date, p_am, p_pm)
  on conflict (campaign_id, slot_date)
  do update set am_enabled = excluded.am_enabled, pm_enabled = excluded.pm_enabled;
end;
$$;

grant execute on function admin_upsert_open_slot(text, text, date, boolean, boolean) to anon;

create or replace function admin_delete_open_slot(
  p_code text, p_password text, p_date date
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_campaign_id uuid;
  v_ok boolean;
begin
  select id, (admin_password = p_password) into v_campaign_id, v_ok
  from campaigns where code = p_code;

  if v_campaign_id is null then
    raise exception '案件不存在';
  end if;
  if not v_ok then
    raise exception '密碼錯誤';
  end if;

  delete from open_slots where campaign_id = v_campaign_id and slot_date = p_date;
end;
$$;

grant execute on function admin_delete_open_slot(text, text, date) to anon;

-- submissions 新增：任何人皆可（業者送出表單），但限制只能寫入存在的案件
create policy submissions_insert on submissions
  for insert with check (true);

-- submissions 讀取：開放讀取（管理頁要顯示彙整列表；前端會用 campaign code 過濾）
-- 若要更嚴格，可改為僅透過 RPC 帶密碼讀取，下面提供 admin 版本 RPC 供管理頁使用
create policy submissions_select on submissions
  for select using (true);

-- 管理者修改/刪除 submissions 用的 RPC（需密碼驗證）
create or replace function admin_update_submission(
  p_code text, p_password text, p_id uuid,
  p_control_no text, p_factory_name text, p_address text,
  p_contact_name text, p_contact_phone text, p_contact_email text,
  p_notes text, p_availability jsonb
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_campaign_id uuid;
  v_ok boolean;
begin
  select id, (admin_password = p_password) into v_campaign_id, v_ok
  from campaigns where code = p_code;

  if v_campaign_id is null then
    raise exception '案件不存在';
  end if;
  if not v_ok then
    raise exception '密碼錯誤';
  end if;

  update submissions set
    control_no = p_control_no,
    factory_name = p_factory_name,
    address = p_address,
    contact_name = p_contact_name,
    contact_phone = p_contact_phone,
    contact_email = p_contact_email,
    notes = p_notes,
    availability = p_availability,
    updated_at = now()
  where id = p_id and campaign_id = v_campaign_id;
end;
$$;

grant execute on function admin_update_submission(
  text, text, uuid, text, text, text, text, text, text, text, jsonb
) to anon;

create or replace function admin_delete_submission(
  p_code text, p_password text, p_id uuid
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_campaign_id uuid;
  v_ok boolean;
begin
  select id, (admin_password = p_password) into v_campaign_id, v_ok
  from campaigns where code = p_code;

  if v_campaign_id is null then
    raise exception '案件不存在';
  end if;
  if not v_ok then
    raise exception '密碼錯誤';
  end if;

  delete from submissions where id = p_id and campaign_id = v_campaign_id;
end;
$$;

grant execute on function admin_delete_submission(text, text, uuid) to anon;

-- 建立新案件用的 RPC（不需密碼，因為案件本身尚不存在；
-- 建議：建立案件的網址您自行保管，不要公開分享）
create or replace function admin_create_campaign(
  p_code text, p_name text, p_password text
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  insert into campaigns (code, name, admin_password)
  values (p_code, p_name, p_password)
  returning id into v_id;
  return v_id;
end;
$$;

grant execute on function admin_create_campaign(text, text, text) to anon;
