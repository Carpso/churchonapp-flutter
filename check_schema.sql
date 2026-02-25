SELECT table_schema, column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'churches'
ORDER BY table_schema, column_name;

SELECT table_schema, column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'profiles'
ORDER BY table_schema, column_name;
