/* ============================================================
   CONFIGURACAO SUPABASE — M8 Stone Solutions
   ------------------------------------------------------------
   Preencha os dois valores abaixo com os dados do seu projeto
   Supabase (Project Settings -> API):

     - Project URL   -> SUPABASE_URL
     - anon / public -> SUPABASE_ANON_KEY   (a chave "anon", NAO a "service_role")

   Enquanto estiverem vazios, a aplicacao corre em modo demonstracao
   (dados em memoria + seed de exemplo). Assim que forem preenchidos,
   os dados passam a ser carregados e guardados no Supabase.
   ============================================================ */
window.M8_CONFIG = {
  // A URL tem de ser o endereco completo do projeto:
  SUPABASE_URL: 'https://bbocluvrcdaqmvbtoind.supabase.co',

  // Chave PUBLICA (publishable / anon) — pode ir no browser.
  // NUNCA colocar aqui a chave secreta ("sb_secret_..." / service_role).
  SUPABASE_ANON_KEY: 'sb_publishable_0bOwfpXkjRfmjIi-ZUSO4A_ib8T9rW5'
};
