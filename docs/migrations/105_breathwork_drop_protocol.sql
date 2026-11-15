-- Migration 105 — Drop colonne protocol après déploiement backend
--
-- ORDRE : exécuter APRÈS que le backend fusionné (plus aucune écriture ni lecture
-- de la colonne protocol) soit déployé en production.
--
-- Prérequis : migration 104 appliquée, code backend 104+ déployé.

ALTER TABLE breathwork_sessions DROP CONSTRAINT breathwork_sessions_protocol_check;
ALTER TABLE breathwork_sessions DROP COLUMN protocol;
