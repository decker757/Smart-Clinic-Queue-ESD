ALTER TABLE payments.payments
    ADD COLUMN IF NOT EXISTS amount_cents INT,
    ADD COLUMN IF NOT EXISTS currency TEXT DEFAULT 'sgd';
