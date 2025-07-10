-- drop everything we dont need
DROP FUNCTION IF EXISTS metahelper_peaks;
DROP FUNCTION IF EXISTS peak_tile;
DROP MATERIALIZED VIEW IF EXISTS distance_peaks;
DROP MATERIALIZED VIEW IF EXISTS peaks_temp;
