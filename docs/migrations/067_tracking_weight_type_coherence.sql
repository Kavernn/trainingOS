-- Migration 067: cohérence tracking_type ↔ weight_type endurance
-- Garantit que weight_type=endurance implique tracking_type=time et vice versa.
-- La migration 063 couvrait tracking_type=time → weight_type=endurance pour les données d'import.
-- Cette migration couvre les exercices créés ou importés entre-temps qui auraient glissé.

-- weight_type=endurance DOIT avoir tracking_type=time
UPDATE public.exercises
SET tracking_type = 'time'
WHERE weight_type = 'endurance'
  AND tracking_type IS DISTINCT FROM 'time';

-- tracking_type=time DOIT avoir weight_type=endurance
UPDATE public.exercises
SET weight_type = 'endurance'
WHERE tracking_type = 'time'
  AND weight_type IS DISTINCT FROM 'endurance';
