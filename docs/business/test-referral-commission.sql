-- Test-only, one-level referral commission settlement for PostgreSQL.
-- The inviter receives a configurable share of successful model consumption.

CREATE TABLE IF NOT EXISTS referral_commission_settings (
    id smallint PRIMARY KEY DEFAULT 1 CHECK (id = 1),
    enabled boolean NOT NULL DEFAULT true,
    rate_basis_points integer NOT NULL DEFAULT 1000 CHECK (rate_basis_points BETWEEN 0 AND 10000),
    updated_at bigint NOT NULL DEFAULT EXTRACT(EPOCH FROM now())::bigint
);

INSERT INTO referral_commission_settings (id, enabled, rate_basis_points)
VALUES (1, true, 1000)
ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS referral_commission_ledger (
    id bigserial PRIMARY KEY,
    source_log_id bigint NOT NULL UNIQUE,
    consumer_user_id bigint NOT NULL,
    inviter_user_id bigint NOT NULL,
    source_quota bigint NOT NULL CHECK (source_quota > 0),
    rate_basis_points integer NOT NULL CHECK (rate_basis_points BETWEEN 0 AND 10000),
    commission_quota bigint NOT NULL CHECK (commission_quota > 0),
    status varchar(16) NOT NULL DEFAULT 'settled',
    created_at bigint NOT NULL DEFAULT EXTRACT(EPOCH FROM now())::bigint
);

CREATE INDEX IF NOT EXISTS idx_referral_commission_inviter_created
ON referral_commission_ledger (inviter_user_id, created_at DESC);

CREATE OR REPLACE FUNCTION settle_referral_commission_from_log()
RETURNS trigger AS $$
DECLARE
    inviter bigint;
    configured_rate integer;
    reward bigint;
BEGIN
    IF NEW.type <> 2 OR NEW.quota <= 0 THEN
        RETURN NEW;
    END IF;

    SELECT inviter_id INTO inviter FROM users WHERE id = NEW.user_id;
    IF COALESCE(inviter, 0) = 0 OR inviter = NEW.user_id THEN
        RETURN NEW;
    END IF;

    SELECT rate_basis_points INTO configured_rate
    FROM referral_commission_settings
    WHERE id = 1 AND enabled = true;
    IF configured_rate IS NULL OR configured_rate <= 0 THEN
        RETURN NEW;
    END IF;

    reward := FLOOR(NEW.quota::numeric * configured_rate / 10000)::bigint;
    IF reward <= 0 THEN
        RETURN NEW;
    END IF;

    INSERT INTO referral_commission_ledger (
        source_log_id, consumer_user_id, inviter_user_id,
        source_quota, rate_basis_points, commission_quota
    ) VALUES (NEW.id, NEW.user_id, inviter, NEW.quota, configured_rate, reward)
    ON CONFLICT (source_log_id) DO NOTHING;

    IF FOUND THEN
        UPDATE users
        SET aff_quota = aff_quota + reward,
            aff_history = aff_history + reward
        WHERE id = inviter;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_settle_referral_commission ON logs;
CREATE TRIGGER trg_settle_referral_commission
AFTER INSERT ON logs
FOR EACH ROW EXECUTE FUNCTION settle_referral_commission_from_log();
