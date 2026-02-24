-- Optimizing for Real-time Matching (Kingdom Expansion Scale)
-- This file ensures that indexing is set up for high-performance lookups on status and ownership.

-- 1. Indexing 'ride_requests' for fast matching
CREATE INDEX IF NOT EXISTS idx_ride_requests_status ON ride_requests(status);
CREATE INDEX IF NOT EXISTS idx_ride_requests_rider_id ON ride_requests(rider_id);
CREATE INDEX IF NOT EXISTS idx_ride_requests_driver_id ON ride_requests(driver_id);

-- 2. Indexing 'notifications' for targeted real-time delivery
CREATE INDEX IF NOT EXISTS idx_notifications_user_id ON notifications(user_id);
CREATE INDEX IF NOT EXISTS idx_notifications_is_read ON notifications(is_read);

-- 3. Indexing 'ride_registrations' for spatial-ish lookups 
-- Note: In a production VPS, you'd likely use PostGIS, but for now we focus on status and ID performance.
CREATE INDEX IF NOT EXISTS idx_ride_registrations_user_id ON ride_registrations(user_id);
CREATE INDEX IF NOT EXISTS idx_ride_registrations_status ON ride_registrations(status);
CREATE INDEX IF NOT EXISTS idx_ride_registrations_type ON ride_registrations(type);
