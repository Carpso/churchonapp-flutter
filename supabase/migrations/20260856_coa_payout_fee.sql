-- COA earns on payouts too: max(1% of payout, min K3), like the collection fee.
-- Deducted via FeeConfig.payoutNet() alongside Lipila's 1.5% disbursement fee.
INSERT INTO public.platform_settings (key, value)
VALUES ('coa_payout_fee_percent', '0.01')
ON CONFLICT (key) DO NOTHING;
