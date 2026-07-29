-- Rename 'Speed Demon' achievement to 'Lightning Fast' in DB
UPDATE achievements
SET title = 'Lightning Fast'
WHERE id = 'speed_demon';
