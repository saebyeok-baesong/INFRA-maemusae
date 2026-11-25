-- ops 인스턴스에 마스터 사용자(maemusae)로 한 번 실행한다. 실행 방법은 docs/architecture.md "ops DB 역할 만들기"
-- 다시 실행해도 같은 상태가 된다. 비밀번호 없는 역할이라 IAM 토큰으로만 로그인한다
\set ON_ERROR_STOP on

DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'incident_app') THEN
    CREATE ROLE incident_app LOGIN;
  END IF;
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'security_app') THEN
    CREATE ROLE security_app LOGIN;
  END IF;
END
$$;

GRANT rds_iam TO incident_app;
GRANT rds_iam TO security_app;

-- PG16 부터 CREATE DATABASE ... OWNER 는 실행하는 사용자가 그 역할의 멤버여야 한다
GRANT incident_app TO maemusae;
GRANT security_app TO maemusae;

-- CREATE DATABASE 는 IF NOT EXISTS 가 없고 트랜잭션 블록 안에서 돌 수 없어 \gexec 로 없을 때만 실행한다
SELECT 'CREATE DATABASE incident OWNER incident_app'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'incident')\gexec
SELECT 'CREATE DATABASE security OWNER security_app'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'security')\gexec

REVOKE CONNECT ON DATABASE incident FROM PUBLIC;
REVOKE CONNECT ON DATABASE security FROM PUBLIC;
GRANT CONNECT ON DATABASE incident TO incident_app;
GRANT CONNECT ON DATABASE security TO security_app;
