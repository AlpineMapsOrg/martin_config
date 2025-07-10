-- drop everything we dont need
DROP FUNCTION IF EXISTS metahelper_webcams;
DROP FUNCTION IF EXISTS webcams_tile;
DROP MATERIALIZED VIEW IF EXISTS distance_webcams;
DROP MATERIALIZED VIEW IF EXISTS webcams_temp;
DROP TABLE IF EXISTS "external_webcams";
