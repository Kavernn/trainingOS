-- 052_revoke_set_updated_at_rpc.sql
-- Security: set_updated_at is an internal trigger function, not a public RPC.
-- Revoke EXECUTE from public-facing Supabase roles so it cannot be called
-- via /rest/v1/rpc/set_updated_at by unauthenticated or authenticated users.
REVOKE EXECUTE ON FUNCTION public.set_updated_at() FROM anon, authenticated, PUBLIC;
