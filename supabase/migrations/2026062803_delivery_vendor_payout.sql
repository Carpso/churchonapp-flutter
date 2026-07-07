-- ALTER delivery_requests TABLE FOR VENDOR ESCROW DETAILS
ALTER TABLE delivery_requests ADD COLUMN IF NOT EXISTS vendor_phone TEXT;
ALTER TABLE delivery_requests ADD COLUMN IF NOT EXISTS vendor_name TEXT;
ALTER TABLE delivery_requests ADD COLUMN IF NOT EXISTS item_price DOUBLE PRECISION;
