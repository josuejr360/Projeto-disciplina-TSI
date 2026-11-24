-- ACADEMEY UFAL · esquema completo do MVP (Módulo do Aluno)

CREATE TABLE IF NOT EXISTS cursos (
  id                SERIAL PRIMARY KEY,
  nome              VARCHAR(120) NOT NULL UNIQUE,
  creditos_totais   INTEGER      NOT NULL DEFAULT 180
);

ALTER TABLE cursos ADD COLUMN IF NOT EXISTS creditos_totais INTEGER NOT NULL DEFAULT 180;

CREATE TABLE IF NOT EXISTS usuarios (
  id                BIGSERIAL PRIMARY KEY,
  nome              VARCHAR(150) NOT NULL,
  matricula         VARCHAR(20)  NOT NULL UNIQUE,
  email             VARCHAR(254) NOT NULL,
  senha_hash        VARCHAR(100) NOT NULL,
  curso_id          INTEGER REFERENCES cursos(id) ON DELETE SET NULL,
  perfil            VARCHAR(20)  NOT NULL DEFAULT 'aluno'
                    CHECK (perfil IN ('aluno', 'professor', 'admin')),
  ativo             BOOLEAN      NOT NULL DEFAULT TRUE,
  termos_aceitos_em TIMESTAMPTZ,
  criado_em         TIMESTAMPTZ  NOT NULL DEFAULT now(),
  ultimo_login      TIMESTAMPTZ
);

ALTER TABLE usuarios ADD COLUMN IF NOT EXISTS termos_aceitos_em TIMESTAMPTZ;

CREATE UNIQUE INDEX IF NOT EXISTS usuarios_email_uq ON usuarios (lower(email));
CREATE INDEX IF NOT EXISTS usuarios_curso_idx ON usuarios (curso_id);

CREATE TABLE IF NOT EXISTS password_reset_tokens (
  id          BIGSERIAL PRIMARY KEY,
  usuario_id  BIGINT      NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
  token_hash  VARCHAR(64) NOT NULL UNIQUE,
  expira_em   TIMESTAMPTZ NOT NULL,
  usado_em    TIMESTAMPTZ,
  criado_em   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS password_reset_usuario_idx ON password_reset_tokens (usuario_id);

-- Períodos letivos e janela de matrícula (RN01)
CREATE TABLE IF NOT EXISTS periodos_letivos (
  id               SERIAL PRIMARY KEY,
  codigo           VARCHAR(20) NOT NULL UNIQUE,
  ativo            BOOLEAN     NOT NULL DEFAULT FALSE,
  matricula_inicio TIMESTAMPTZ NOT NULL,
  matricula_fim    TIMESTAMPTZ NOT NULL
);

-- Catálogo de disciplinas e pré-requisitos (HU07, RN02)
CREATE TABLE IF NOT EXISTS disciplinas (
  id            SERIAL PRIMARY KEY,
  codigo        VARCHAR(20)  NOT NULL UNIQUE,
  nome          VARCHAR(140) NOT NULL,
  creditos      INTEGER      NOT NULL CHECK (creditos > 0),
  carga_horaria INTEGER      NOT NULL CHECK (carga_horaria > 0),
  curso_id      INTEGER      REFERENCES cursos(id) ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS disciplina_pre_requisitos (
  disciplina_id     INTEGER NOT NULL REFERENCES disciplinas(id) ON DELETE CASCADE,
  pre_requisito_id  INTEGER NOT NULL REFERENCES disciplinas(id) ON DELETE CASCADE,
  PRIMARY KEY (disciplina_id, pre_requisito_id),
  CHECK (disciplina_id <> pre_requisito_id)
);

-- Turmas ofertadas no período (HU08 choque de horário, HU10 controle de vagas)
CREATE TABLE IF NOT EXISTS turmas (
  id              BIGSERIAL PRIMARY KEY,
  disciplina_id   INTEGER      NOT NULL REFERENCES disciplinas(id) ON DELETE CASCADE,
  periodo_id      INTEGER      NOT NULL REFERENCES periodos_letivos(id) ON DELETE CASCADE,
  codigo_turma    VARCHAR(20)  NOT NULL,
  professor_nome  VARCHAR(120) NOT NULL,
  horario         VARCHAR(80)  NOT NULL,
  vagas           INTEGER      NOT NULL CHECK (vagas > 0),
  vagas_ocupadas  INTEGER      NOT NULL DEFAULT 0 CHECK (vagas_ocupadas >= 0 AND vagas_ocupadas <= vagas),
  UNIQUE (disciplina_id, periodo_id, codigo_turma)
);

CREATE INDEX IF NOT EXISTS turmas_periodo_idx ON turmas (periodo_id);

-- Matrículas e histórico acadêmico (HU04, HU09, HU10, HU11, HU12)
CREATE TABLE IF NOT EXISTS matriculas (
  id          BIGSERIAL PRIMARY KEY,
  usuario_id  BIGINT       NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
  turma_id    BIGINT       NOT NULL REFERENCES turmas(id) ON DELETE CASCADE,
  status      VARCHAR(20)  NOT NULL DEFAULT 'ativa'
              CHECK (status IN ('ativa', 'cancelada', 'aprovada', 'reprovada')),
  nota_final  NUMERIC(4,2) CHECK (nota_final IS NULL OR (nota_final >= 0 AND nota_final <= 10)),
  frequencia  NUMERIC(5,2) CHECK (frequencia IS NULL OR (frequencia >= 0 AND frequencia <= 100)),
  criado_em   TIMESTAMPTZ  NOT NULL DEFAULT now(),
  atualizado_em TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (usuario_id, turma_id)
);

CREATE INDEX IF NOT EXISTS matriculas_usuario_idx ON matriculas (usuario_id);

-- Resumo acadêmico calculado pelo Worker Python (HU06, HU11, RN06)
CREATE TABLE IF NOT EXISTS aluno_resumos (
  usuario_id           BIGINT PRIMARY KEY REFERENCES usuarios(id) ON DELETE CASCADE,
  cr                   NUMERIC(4,2) NOT NULL DEFAULT 0.00,
  creditos_concluidos  INTEGER      NOT NULL DEFAULT 0,
  atualizado_em        TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- Requerimentos com protocolo único (HU14, HU15, HU16, RN04, RN05)
CREATE SEQUENCE IF NOT EXISTS requerimento_protocolo_seq START 1;

CREATE TABLE IF NOT EXISTS requerimentos (
  id            BIGSERIAL PRIMARY KEY,
  usuario_id    BIGINT       NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
  protocolo     VARCHAR(32)  NOT NULL UNIQUE,
  tipo          VARCHAR(60)  NOT NULL,
  assunto       VARCHAR(160) NOT NULL,
  descricao     TEXT         NOT NULL,
  status        VARCHAR(20)  NOT NULL DEFAULT 'em_analise'
                CHECK (status IN ('em_analise', 'deferido', 'indeferido')),
  parecer       TEXT,
  criado_em     TIMESTAMPTZ  NOT NULL DEFAULT now(),
  atualizado_em TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS requerimentos_usuario_idx ON requerimentos (usuario_id);

-- Fila Transactional Outbox Node.js <-> Worker Python (FOR UPDATE SKIP LOCKED + Lease/Fencing)
CREATE TABLE IF NOT EXISTS outbox_jobs (
  id            BIGSERIAL PRIMARY KEY,
  job_type      VARCHAR(40) NOT NULL,
  aggregate_id  VARCHAR(60) NOT NULL,
  payload       JSONB       NOT NULL DEFAULT '{}'::jsonb,
  status        VARCHAR(20) NOT NULL DEFAULT 'pending'
                CHECK (status IN ('pending', 'processing', 'completed', 'failed')),
  attempts      INTEGER     NOT NULL DEFAULT 0,
  max_attempts  INTEGER     NOT NULL DEFAULT 5,
  available_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  locked_until  TIMESTAMPTZ,
  lock_version  BIGINT      NOT NULL DEFAULT 0,
  result        JSONB,
  error_message TEXT,
  criado_em     TIMESTAMPTZ NOT NULL DEFAULT now(),
  atualizado_em TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS outbox_jobs_pending_idx
  ON outbox_jobs (available_at, id)
  WHERE status = 'pending';

-- Armazenamento de boletins PDF gerados pelo Worker Python (HU13)
CREATE TABLE IF NOT EXISTS boletins_pdf (
  id              BIGSERIAL PRIMARY KEY,
  usuario_id      BIGINT      NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
  job_id          BIGINT      REFERENCES outbox_jobs(id) ON DELETE SET NULL,
  nome_arquivo    VARCHAR(120) NOT NULL,
  conteudo_base64 TEXT        NOT NULL,
  criado_em       TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS boletins_usuario_idx ON boletins_pdf (usuario_id, criado_em DESC);
