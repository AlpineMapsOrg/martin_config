




-- SELECT * from metahelper_webcams(10,10) ORDER BY entries_with_values DESC;


-- SELECT distinct skeys(data) from webcams_temp;
SELECT distinct data->'surveillance:zone' from webcams_temp;