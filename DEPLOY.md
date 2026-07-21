# M8 Stone Solutions — Guia de Deploy (GitHub → Render → Supabase)

Aplicação estática (HTML + JS) com base de dados no **Supabase**, publicada no
**Render** a partir do **GitHub**. Não é preciso servidor próprio — o Supabase é
acedido diretamente do browser.

Ficheiros do projeto:
- `index.html` — a aplicação (dashboard com mapa, projetos, agendamentos, popup de frações…)
- `producao.html` — tab "Producao" (controlo de horas de maquina), aberta em iframe dentro do `index.html`
- `supabase-config.js` — onde colocas as chaves do Supabase (partilhado pelas duas apps)
- `schema.sql` — o esquema da base de dados
- `DEPLOY.md` — este guia

A tab **Producao** grava a grelha de maquinas e a lista de espera na tabela
`producao_state` do Supabase (mesma logica da `app_state`), com fallback para
`localStorage` quando o Supabase nao esta configurado. O botao "Importar Excel"
dentro dessa tab continua a funcionar para carregar o teu `Controlo_Maquinas_2026.xlsx`
— depois de importado, os dados sao guardados automaticamente online.

---

## 1. Supabase (base de dados)

1. Cria conta em **https://supabase.com** → **New project** (escolhe uma password
   para a base de dados e uma região próxima, ex. *West EU / Frankfurt*).
2. Espera ~2 min até o projeto ficar pronto.
3. No menu lateral: **SQL Editor → New query**. Cola todo o conteúdo de
   `schema.sql` e carrega em **Run**. Isto cria as tabelas `contas` (logins) e
   `app_state`, as funções de autenticação e as políticas de acesso.
4. Vai a **Project Settings → API** e copia:
   - **Project URL** (ex. `https://abcdefgh.supabase.co`)
   - Chave **anon / public** (a longa que começa por `eyJ...`) — **não** a `service_role`.
5. Abre `supabase-config.js` e cola os dois valores:
   ```js
   window.M8_CONFIG = {
     SUPABASE_URL: 'https://abcdefgh.supabase.co',
     SUPABASE_ANON_KEY: 'eyJhbGciOi...'
   };
   ```
   > Enquanto estes campos estiverem vazios, a app corre em **modo demonstração**
   > (dados de exemplo em memória + contas predefinidas, perdidos ao recarregar).
   > Assim que os preencheres, os **logins passam a ser validados na tabela
   > `contas`** do Supabase e os dados são carregados/gravados automaticamente.
   >
   > ⚠️ Usa a chave **anon / public** (começa por `eyJ...`). **Não** uses a chave
   > secreta (`sb_secret_...` / `service_role`) no browser — dá acesso total à BD.

---

## 2. GitHub (código)

1. Cria um repositório novo em **https://github.com/new** (ex. `m8-stone`), podes
   mantê-lo privado.
2. Envia os ficheiros. Pela linha de comandos, na pasta do projeto:
   ```bash
   git init
   git add index.html producao.html supabase-config.js schema.sql DEPLOY.md
   git commit -m "M8 Stone Solutions"
   git branch -M main
   git remote add origin https://github.com/<o-teu-utilizador>/m8-stone.git
   git push -u origin main
   ```
   (ou usa **Add file → Upload files** no site do GitHub e arrasta os ficheiros).

> ⚠️ A chave **anon** fica visível no browser — é normal e seguro **desde que**
> tenhas RLS ativo (o `schema.sql` já ativa). Nunca coloques a chave
> `service_role` no repositório.

---

## 3. Render (publicação)

1. Cria conta em **https://render.com** e liga a tua conta GitHub.
2. **New + → Static Site** → escolhe o repositório `m8-stone`.
3. Configura:
   - **Build Command**: *(deixa vazio)*
   - **Publish Directory**: `.` (ponto — a raiz do repositório)
4. **Create Static Site**. Em ~1 min ficas com um URL público
   (ex. `https://m8-stone.onrender.com`).
5. Cada `git push` para `main` volta a publicar automaticamente.

---

## 4. Verificação

- Abre o URL do Render. O ecrã de login valida as credenciais **contra a tabela
  `contas`** do Supabase (função `verificar_login`). Usa uma das contas criadas
  pelo `schema.sql`:
  - `admin@m8stone.pt` / `admin123`
  - `desenho@m8stone.pt` / `d123`
  - `tecnico@m8stone.pt` / `t123`
- Cria/edita/remove contas no painel **Contas** (como admin) — as alterações são
  gravadas na tabela `contas` do Supabase.
- Cria um cliente/projeto, recarrega a página: os dados devem **persistir**
  (guardados na tabela `app_state`).
- Se o login falhar com "Erro de ligacao ao servidor", confirma o passo 1.4/1.5
  (URL completo + chave **anon**) e vê a consola do browser por avisos `[Supabase]`.

---

## Atualizar uma instalação já existente (proteção contra perda de dados)

Se já tinhas o Supabase configurado antes desta versão, volta a **SQL Editor → New query**,
cola de novo todo o `schema.sql` e corre. É seguro repetir — só acrescenta as tabelas novas
`app_state_history` e `producao_state_history` (histórico de versões, para recuperação em
caso de erro) sem tocar nos dados existentes.

## Notas de segurança

- A **Opção A** do `schema.sql` (política aberta à chave anon) é adequada a uma
  ferramenta **interna/privada**. Para uso mais aberto, ativa **Supabase Auth** e
  troca para a política de utilizador autenticado (Opção B, comentada no SQL).
- As passwords das contas estão, nesta versão, guardadas em texto simples dentro
  do estado da app (herdado do protótipo). Para produção recomenda-se migrar o
  login para **Supabase Auth**.
