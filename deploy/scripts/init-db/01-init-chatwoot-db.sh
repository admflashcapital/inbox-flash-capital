#!/bin/bash
# ═══════════════════════════════════════════════════════════════════
# Init do Postgres da central (STORY-1.1 / STORY-1.2 — AD-9)
# ═══════════════════════════════════════════════════════════════════
# Roda UMA vez, no primeiro start (volume vazio), via
# docker-entrypoint-initdb.d. Cria:
#   - o usuário do Chatwoot (não-superusuário, dono do banco)
#   - o banco da central
#   - as 5 extensões que o schema.rb do Chatwoot exige
#
# Por que pré-criar as extensões: `pg_stat_statements` NÃO é uma
# extensão "trusted" — só um superusuário a cria. As migrações do
# Chatwoot rodam como o usuário `chatwoot` (não-superusuário, por
# AD-9/menor privilégio) e fariam `CREATE EXTENSION` → permission
# denied. Criando-as aqui como superusuário, o `enable_extension` da
# migração vira `CREATE EXTENSION IF NOT EXISTS` sobre algo que já
# existe: no-op, sem exigir privilégio.
#
# Senhas vêm das env vars do serviço postgres — nunca hardcoded.
# ═══════════════════════════════════════════════════════════════════
set -euo pipefail

# APP_DB_* e não POSTGRES_* de propósito: para a imagem oficial do Postgres,
# `POSTGRES_PASSWORD` é a senha do SUPERUSUÁRIO; para o Chatwoot, é a do usuário
# da aplicação. Usar o mesmo nome para as duas coisas colide.
DB="${APP_DB_NAME:?APP_DB_NAME não definida}"
USER_APP="${APP_DB_USER:?APP_DB_USER não definida}"
PASS_APP="${APP_DB_PASSWORD:?APP_DB_PASSWORD não definida}"

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname postgres <<-EOSQL
	CREATE USER ${USER_APP} WITH PASSWORD '${PASS_APP}';
	CREATE DATABASE ${DB} OWNER ${USER_APP};
	GRANT ALL PRIVILEGES ON DATABASE ${DB} TO ${USER_APP};
EOSQL

# Extensões exigidas pelo schema do Chatwoot (db/schema.rb).
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$DB" <<-EOSQL
	CREATE EXTENSION IF NOT EXISTS "pg_stat_statements";
	CREATE EXTENSION IF NOT EXISTS "pg_trgm";
	CREATE EXTENSION IF NOT EXISTS "pgcrypto";
	CREATE EXTENSION IF NOT EXISTS "plpgsql";
	CREATE EXTENSION IF NOT EXISTS "vector";
EOSQL

echo "init-db: banco ${DB} pronto (dono ${USER_APP}; extensões pgvector/trgm/pgcrypto/stat_statements)."
