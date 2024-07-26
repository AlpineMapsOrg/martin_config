

-- drop everything we dont need
DROP FUNCTION IF EXISTS peak_tile;
DROP INDEX distance_peaks_geom_idx;
DROP INDEX distance_peaks_zoom_idx;
DROP INDEX peaks_geom_idx;
DROP INDEX peaks_importance_metric_idx;
DROP MATERIALIZED VIEW IF EXISTS distance_peaks;
DROP MATERIALIZED VIEW IF EXISTS peaks_temp;

-- view for peaks
-- CREATE VIEW peaks AS 
CREATE MATERIALIZED VIEW peaks_temp AS
    -- general attributes (all features should have them)
    SELECT osm_id as id,
        planet_osm_point.name,
        ST_X(ST_TRANSFORM(planet_osm_point.way,4674)) AS long,
        ST_Y(ST_TRANSFORM(planet_osm_point.way,4674)) AS lat,
        planet_osm_point.way as geom,

        -- FLOOR(nullif(substring(ele FROM '[0-9]+'), '')::decimal)::int as importance_metric,
        FLOOR(nullif(substring(planet_osm_point.tags->'ele' FROM '[0-9]+'), '')::decimal)::int as importance_metric,

        slice( -- only extracts attributes defined by array
            -- add ele to data field
            planet_osm_point.tags || hstore('ele', FLOOR(nullif(substring(planet_osm_point.tags->'ele' FROM '[0-9]+'), '')::decimal)::int::text),
            ARRAY[
                'name:de',
                'wikipedia',
                'wikidata',
                'importance',
                'prominence',
                'summit:cross',
                'summit:register',
                'ele'
            ]
        ) as data

    FROM planet_osm_point
      WHERE planet_osm_point."natural" = 'peak'::text AND name IS NOT NULL AND planet_osm_point.tags->'ele' IS NOT NULL
      ORDER BY importance_metric desc;


CREATE INDEX peaks_geom_idx
  ON peaks_temp
  USING GIST (geom);

CREATE INDEX peaks_importance_metric_idx
  ON peaks_temp(importance_metric);  -- automatcially uses b-tree


-- we want to prioritize POIs with the higher distances to other POIs where the importance_metric is higher than itself.
-- e.g. Kleinglockner is near Großglockner (small distance -> will only be shown very late although it has a high altitude)
-- the following materialized view calculates those distances to each POI within a certain radius (search radius defined in cluster_dist as 1/3 of tile width and currently starting to search with zoom level 8)
-- all_distances calculates the min_dist to better POI
-- whereas the final select creates a list for each individual zoom level and orders those results by importance_metric
CREATE MATERIALIZED VIEW distance_peaks AS
WITH cd AS (
    SELECT * from cluster_dists
    WHERE zoom = 8 -- min cluster zoom level is defined here
), all_distances as (
    SELECT a.id,
        a.name,
        a.data,
        a.importance_metric as importance_metric,
        a.geom,
        a.long,
        a.lat,
        -- this sets the distance to max for itself
        -- this way it will always be here if no taller peaks has been found in radius
        min(
        (CASE 
            WHEN a.id = b.id
            THEN cd.dist
            ELSE ST_Distance(a.geom, b.geom)
        END)) as min_dist
    FROM cd CROSS JOIN peaks_temp a LEFT JOIN peaks_temp b ON (ST_DWithin(a.geom, b.geom, cd.dist) and b.importance_metric >= a.importance_metric)
    GROUP BY a.id, a.name, a.data, a.geom, a.long, a.lat, a.importance_metric
    ORDER BY importance_metric DESC, min_dist DESC
)
SELECT
    id, name, data, geom, long, lat,
    importance_metric,
    cluster_dists.zoom,
    -- importance: in interval [0,1] 1 means that it has the max importances (= max distance to POIs with higher metric than itself)
    LEAST(min_dist::decimal / cd.dist::decimal, 1.0) as importance
FROM cd, all_distances LEFT JOIN cluster_dists ON (cluster_dists.zoom >= 8 and cluster_dists.zoom < 22)
ORDER BY importance DESC, importance_metric DESC
;



-- create index for faster geom lookups
CREATE INDEX distance_peaks_geom_idx
  ON distance_peaks
  USING GIST (geom);


CREATE INDEX distance_peaks_zoom_idx
  ON distance_peaks
  USING HASH (zoom);




CREATE OR REPLACE
    FUNCTION peak_tile(z integer, x integer, y integer)
    RETURNS bytea AS $$
DECLARE
    mvt bytea;
BEGIN
    IF (z < 22) THEN
        -- highest peaks visible
        SELECT INTO mvt ST_AsMVT(tile, 'Peak', 4096, 'geom', 'id') FROM (

            SELECT id, name, lat,long,importance,importance_metric,
            ST_AsMVTGeom(
                ST_Transform(distance_peaks.geom, 3857),
                ST_TileEnvelope(z,x,y),
                4096, 0, true
            ) as geom,

            data->'name:de' as de_name,
            data->'wikipedia' as wikipedia,
            data->'wikidata' as wikidata,
            data->'importance' as importance_osm,
            data->'prominence' as prominence,
            data->'summit:cross' as summit_cross,
            data->'summit:register' as summit_register,
            (data->'ele')::int as ele

            FROM distance_peaks
            WHERE zoom = z AND ST_TRANSFORM(distance_peaks.geom,4674) && ST_Transform(ST_TileEnvelope(z,x,y), 4674)
            LIMIT 4
        ) as tile;
    ELSE
    -- all peaks visible
        SELECT INTO mvt ST_AsMVT(tile, 'Peak', 4096, 'geom', 'id') FROM (
            SELECT id, name, lat,long,importance,importance_metric,
            ST_AsMVTGeom(
                ST_Transform(distance_peaks.geom, 3857),
                ST_TileEnvelope(z,x,y),
                4096, 0, true
            ) as geom,

            data->'name:de' as de_name,
            data->'wikipedia' as wikipedia,
            data->'wikidata' as wikidata,
            data->'importance' as importance_osm,
            data->'prominence' as prominence,
            data->'summit:cross' as summit_cross,
            data->'summit:register' as summit_register,
            (data->'ele')::int as ele

            FROM distance_peaks
            WHERE zoom = 21 AND ST_TRANSFORM(distance_peaks.geom,4674) && ST_Transform(ST_TileEnvelope(z,x,y), 4674)
        ) as tile;
    END IF;


  RETURN mvt;
END
$$ LANGUAGE plpgsql IMMUTABLE STRICT PARALLEL SAFE;