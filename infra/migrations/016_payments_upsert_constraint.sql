-- Allow ON CONFLICT (consultation_id, payment_intent_id) in payment-service consumer
-- so duplicate payment.pending / payment.completed events from retries are idempotent.
CREATE UNIQUE INDEX IF NOT EXISTS uq_payments_consultation_intent
    ON payments.payments (consultation_id, payment_intent_id)
    WHERE payment_intent_id IS NOT NULL;
