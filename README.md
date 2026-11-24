# ACADEMEY UFAL (Node.js + Python + PostgreSQL + Vercel)

Portal acadêmico com arquitetura híbrida:
- **Backend / API principal:** Node.js (Express)
- **Camada de banco de dados & manutenção:** Python (`pg8000` + `db/python/` + Serverless `/api/db-python`)
- **Banco de dados:** PostgreSQL (Neon / Vercel Postgres)
- **UX de entrada:** baseada nos princípios de Don Norman (*The Design of Everyday Things*: descobribilidade, affordances/significantes, mapeamento natural, modelo conceitual, prevenção de erros e feedback imediato).

Requisitos: Node 20.6+, Python 3.11+ e PostgreSQL 13+.

## Rodando localmente

```bash
npm install
pip install -r requirements.txt
cp .env.example .env        # configure DATABASE_URL e JWT_SECRET

# Inicialização do banco (via Python ou Node.js)
npm run py:db:init          # ou: npm run db:init
npm run py:db:seed          # ou: npm run seed
npm run py:db:status        # verifica cursos e usuários ativos via Python

npm run dev
```

Acesse `http://localhost:3000` (ou `https://projeto-tsi.vercel.app`):
- `/` — Tela de entrada/login
- `/cadastro` — Criação de conta pelo próprio usuário (LGPD + checklist de senha forte ao vivo)
- `/recuperar-senha` — Solicitação e redefinição de senha
- `/inicio` — Página inicial autenticada ("ACADEMEY UFAL")

## Deploy na Vercel

1. Rode `npx vercel login` e `npx vercel --prod` (os arquivos `.env` e `node_modules` são ignorados pelo `.vercelignore`).
2. Configure em **Settings → Environment Variables** na Vercel:
   - `DATABASE_URL` (ou `POSTGRES_URL`)
   - `JWT_SECRET` (mínimo 32 caracteres aleatórios)
   - `NODE_ENV=production`
   - `APP_URL=https://projeto-tsi.vercel.app`
   - `FRONTEND_ORIGIN=https://projeto-tsi.vercel.app`
   - *(Opcional)* `RESEND_API_KEY` e `MAIL_FROM` para envio real de e-mails de recuperação

## Rotas da API

- `GET /api/health` (Node.js) — Verifica conexão com o PostgreSQL
- `GET /api/db-python` (Python Serverless) — Métricas agregadas do PostgreSQL via `pg8000`
- `GET /api/cursos` — Lista cursos disponíveis para cadastro
- `POST /api/register` — Cria usuário (`perfil = aluno`, senha forte + aceite LGPD) e inicia sessão
- `POST /api/login` — Autentica matrícula/e-mail e grava cookie `HttpOnly`
- `GET /api/me` — Retorna dados do usuário autenticado
- `POST /api/logout` — Encerra sessão limpando o cookie
- `POST /api/forgot-password` — Gera token SHA-256 com validade de 30 min
- `POST /api/reset-password` — Redefine a senha usando token de uso único
