-- Seed default emergency contacts for Zambia
INSERT INTO public.emergency_contacts (name, phone, icon, category, sort_order)
VALUES 
  ('Police', '911', 'shield', 'emergency_service', 1),
  ('Ambulance', '992', 'ambulance', 'emergency_service', 2),
  ('Fire Brigade', '993', 'flame', 'emergency_service', 3),
  ('Victim Support Unit', '933', 'heart', 'emergency_service', 4),
  ('Child Helpline', '116', 'baby', 'emergency_service', 5)
ON CONFLICT DO NOTHING;

-- Seed default discipleship plans
INSERT INTO public.discipleship_plans (title, description, "order")
VALUES 
  ('Water Baptism', 'Understanding and receiving water baptism', 1),
  ('Bible Reading Plan', 'Daily Bible reading habit', 2),
  ('Prayer Foundation', 'Building a prayer life', 3),
  ('Church Membership', 'Understanding church membership', 4),
  ('Spiritual Gifts', 'Discover your spiritual gifts', 5),
  ('Worship Lifestyle', 'Living a life of worship', 6),
  ('Evangelism Training', 'Sharing your faith', 7),
  ('Leadership Development', 'Growing as a leader', 8)
ON CONFLICT DO NOTHING;
