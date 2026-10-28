// بيانات مشروع Supabase.
// مفتاح anon عام بطبيعته ولا مشكلة في وضعه هنا.
// ممنوع منعًا باتًا وضع مفتاح service_role في أي ملف من التطبيق.
const String kSupabaseUrl = 'https://nvzagojbthyjbavrxynj.supabase.co';
const String kSupabaseAnonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im52emFnb2pidGh5amJhdnJ4eW5qIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTMyMjM3OTAsImV4cCI6MjEwODc5OTc5MH0.wT_hjQ9EZiUyF2ICm5ffa1L2GsR2oxN_2MKm1PNKPE8';

bool get isConfigured =>
    kSupabaseUrl.startsWith('https://') && !kSupabaseAnonKey.startsWith('PUT_');
