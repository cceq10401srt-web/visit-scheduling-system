// 請將下面兩個值換成您自己 Supabase 專案的設定
// 取得方式：Supabase 專案 → Project Settings → API
//   SUPABASE_URL      對應「Project URL」
//   SUPABASE_ANON_KEY 對應「anon public」金鑰（不是 service_role！）

window.SCHEDULER_CONFIG = {
  SUPABASE_URL: "https://pgobqyazlyccrtphuzme.supabase.co",
  SUPABASE_ANON_KEY: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBnb2JxeWF6bHljY3J0cGh1em1lIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODI4MDAyNTcsImV4cCI6MjA5ODM3NjI1N30.5eRIQAVBU8zACQpNGIPhWVYWJgEp4BQI0qZLy5hg6b4",

  // 選填：若業者填寫連結不帶 ?case= 參數時，預設使用的案件代碼
  DEFAULT_CAMPAIGN_CODE: ""
};
