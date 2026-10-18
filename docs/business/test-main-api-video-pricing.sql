-- Test environment only: expose the unique public MiniMax H3 model ID to
-- New API billing without changing the existing legacy model configuration.
-- PostgreSQL syntax; run against the isolated test database.

BEGIN;

UPDATE options
SET value = jsonb_set(
    value::jsonb,
    '{DKVX_MINIMAX_H3}',
    to_jsonb(COALESCE(
        value::jsonb ->> 'MINIMAX_H3',
        'tier("video", u("duration") * 0.09)'
    )),
    true
)
WHERE key = 'billing_setting.billing_expr';

UPDATE options
SET value = jsonb_set(
    value::jsonb,
    '{DKVX_MINIMAX_H3}',
    to_jsonb(COALESCE(
        value::jsonb ->> 'MINIMAX_H3',
        'tiered_expr'
    )),
    true
)
WHERE key = 'billing_setting.billing_mode';

COMMIT;
