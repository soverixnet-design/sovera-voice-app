-- Internal cutover guards. No user IDs or wallet balances belong in this file.
CREATE SCHEMA IF NOT EXISTS sovera_migration;
REVOKE ALL ON SCHEMA sovera_migration FROM PUBLIC,anon,authenticated,service_role;
GRANT USAGE ON SCHEMA sovera_migration TO service_role;
CREATE TABLE IF NOT EXISTS sovera_migration.wallet_snapshots(
 user_id uuid PRIMARY KEY REFERENCES public.sovera_wallets(user_id),
 snapshot_id uuid NOT NULL UNIQUE DEFAULT gen_random_uuid(),
 payload jsonb NOT NULL,
 captured_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE sovera_migration.wallet_snapshots ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE sovera_migration.wallet_snapshots FROM PUBLIC,anon,authenticated,service_role;
GRANT SELECT ON TABLE sovera_migration.wallet_snapshots TO service_role;
CREATE OR REPLACE FUNCTION sovera_migration.guard_wallet_write()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE target uuid; old_target uuid; new_target uuid; wallet_state text;
BEGIN
 IF TG_OP IN ('UPDATE','DELETE') THEN old_target:=OLD.user_id; END IF;
 IF TG_OP IN ('INSERT','UPDATE') THEN new_target:=NEW.user_id; END IF;
 FOR target IN SELECT DISTINCT value FROM unnest(ARRAY[old_target,new_target]) AS t(value) WHERE value IS NOT NULL ORDER BY value LOOP
  SELECT status INTO wallet_state FROM public.sovera_wallets WHERE user_id=target FOR UPDATE;
  IF EXISTS(SELECT 1 FROM sovera_migration.wallet_snapshots WHERE user_id=target) THEN
   RAISE EXCEPTION 'Wallet moved to Sovera server; legacy wallet is read-only' USING ERRCODE='55000';
  END IF;
  IF TG_TABLE_NAME='sovera_wallet_entries' AND (wallet_state IS NULL OR wallet_state='frozen') THEN
   RAISE EXCEPTION 'Wallet frozen or missing' USING ERRCODE='55000';
  END IF;
 END LOOP;
 IF TG_OP='DELETE' THEN RETURN OLD; END IF;
 RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION sovera_migration.guard_wallet_write() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION sovera_migration.guard_wallet_write() TO service_role;
CREATE OR REPLACE FUNCTION sovera_migration.guard_wallet_truncate()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
BEGIN
 RAISE EXCEPTION 'Legacy financial history cannot be truncated during cutover' USING ERRCODE='55000';
 RETURN NULL;
END $$;
REVOKE ALL ON FUNCTION sovera_migration.guard_wallet_truncate() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION sovera_migration.guard_wallet_truncate() TO service_role;
DROP TRIGGER IF EXISTS sovera_legacy_ledger_guard ON public.sovera_wallet_entries;
CREATE TRIGGER sovera_legacy_ledger_guard BEFORE INSERT OR UPDATE OR DELETE ON public.sovera_wallet_entries FOR EACH ROW EXECUTE FUNCTION sovera_migration.guard_wallet_write();
DROP TRIGGER IF EXISTS sovera_legacy_wallet_guard ON public.sovera_wallets;
CREATE TRIGGER sovera_legacy_wallet_guard BEFORE UPDATE OR DELETE ON public.sovera_wallets FOR EACH ROW EXECUTE FUNCTION sovera_migration.guard_wallet_write();
DROP TRIGGER IF EXISTS sovera_legacy_ledger_truncate_guard ON public.sovera_wallet_entries;
CREATE TRIGGER sovera_legacy_ledger_truncate_guard BEFORE TRUNCATE ON public.sovera_wallet_entries FOR EACH STATEMENT EXECUTE FUNCTION sovera_migration.guard_wallet_truncate();
DROP TRIGGER IF EXISTS sovera_legacy_wallet_truncate_guard ON public.sovera_wallets;
CREATE TRIGGER sovera_legacy_wallet_truncate_guard BEFORE TRUNCATE ON public.sovera_wallets FOR EACH STATEMENT EXECUTE FUNCTION sovera_migration.guard_wallet_truncate();
