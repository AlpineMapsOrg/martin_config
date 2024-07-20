
-- change TEMPLATENAME with your desired name (e.g. peaks)
-- Then follow TODOs

-- drop everything we dont need
DROP FUNCTION IF EXISTS TEMPLATENAME_tile;
DROP INDEX distance_TEMPLATENAME_geom_idx;
DROP INDEX distance_TEMPLATENAME_zoom_idx;
DROP INDEX TEMPLATENAME_geom_idx;
DROP INDEX TEMPLATENAME_importance_metric_idx;
DROP MATERIALIZED VIEW IF EXISTS distance_TEMPLATENAME;
DROP MATERIALIZED VIEW IF EXISTS TEMPLATENAME;

-- view for TEMPLATENAME
-- CREATE VIEW TEMPLATENAME AS 
CREATE MATERIALIZED VIEW TEMPLATENAME AS
    -- general attributes (all features should have them)
    SELECT osm_id as id,
        planet_osm_point.name,
        ST_X(ST_TRANSFORM(planet_osm_point.way,4674)) AS long,
        ST_Y(ST_TRANSFORM(planet_osm_point.way,4674)) AS lat,
        planet_osm_point.way as geom,

        -- TODO set your desired value as importance_metric (alternative use the number of tags)
        -- xxx as importance_metric,
        -- alternative importance metric -> number of tags in hstore
        COALESCE(array_length(avals(planet_osm_point.tags), 1),0) AS importance_metric,

        slice( -- only extracts attributes defined by array
            -- TODO optional add additional values to the hstore (e.g. elevation as outlined below)
            planet_osm_point.tags,
            -- planet_osm_point.tags || hstore('ele', FLOOR(nullif(substring(ele FROM '[0-9]+'), '')::decimal)::int::text),
            ARRAY[
                'name:de',
                'wikipedia',
                'wikidata'
                -- TODO add elements you want to extract
            ]
        ) as data

    FROM planet_osm_point
    -- TODO filter the type to anything you want example:
        -- WHERE planet_osm_point."natural" = 'peak'::text AND name IS NOT NULL AND ele IS NOT NULL
    ORDER BY importance_metric desc;


CREATE INDEX TEMPLATENAME_geom_idx
  ON TEMPLATENAME
  USING GIST (geom);

CREATE INDEX TEMPLATENAME_importance_metric_idx
  ON TEMPLATENAME(importance_metric);  -- automatcially uses b-tree


-- we want to prioritize POIs with the higher distances to other POIs where the importance_metric is higher than itself.
-- e.g. Kleinglockner is near Großglockner (small distance -> will only be shown very late although it has a high altitude)
-- the following materialized view calculates those distances to each POI within a certain radius (search radius defined in cluster_dist as 1/3 of tile width and currently starting to search with zoom level 8)
-- all_distances calculates the min_dist to better POI
-- whereas the final select creates a list for each individual zoom level and orders those results by importance_metric
CREATE MATERIALIZED VIEW distance_TEMPLATENAME AS
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
        -- this way it will always be here if no taller TEMPLATENAME has been found in radius
        min((CASE 
            WHEN a.id = b.id
            THEN cd.dist
            ELSE ST_Distance(a.geom, b.geom)
        END)) as min_dist
    FROM cd CROSS JOIN TEMPLATENAME a LEFT JOIN TEMPLATENAME b ON (ST_DWithin(a.geom, b.geom, cd.dist) and b.importance_metric >= a.importance_metric)
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
CREATE INDEX distance_TEMPLATENAME_geom_idx
  ON distance_TEMPLATENAME
  USING GIST (geom);


CREATE INDEX distance_TEMPLATENAME_zoom_idx
  ON distance_TEMPLATENAME
  USING HASH (zoom);




CREATE OR REPLACE
    FUNCTION TEMPLATENAME_tile(z integer, x integer, y integer)
    RETURNS bytea AS $$
DECLARE
    mvt bytea;
BEGIN
    IF (z < 22) THEN
        -- only POIs with highest importance metric in vicinity visible
        SELECT INTO mvt ST_AsMVT(tile, 'TEMPLATENAME', 4096, 'geom', 'id') FROM (

            SELECT id, name, lat,long,importance,importance_metric,
            ST_AsMVTGeom(
                ST_Transform(distance_TEMPLATENAME.geom, 3857),
                ST_TileEnvelope(z,x,y),
                4096, 0, true
            ) as geom,

            -- TODO extract the custom data fields here (and add them in config.yaml)
            data->'name:de' as de_name,
            data->'wikipedia' as wikipedia,
            data->'wikidata' as wikidata

            FROM distance_TEMPLATENAME
            WHERE zoom = z AND ST_TRANSFORM(distance_TEMPLATENAME.geom,4674) && ST_Transform(ST_TileEnvelope(z,x,y), 4674)
            LIMIT 4
        ) as tile;
    ELSE
    -- all POIs visible
        SELECT INTO mvt ST_AsMVT(tile, 'TEMPLATENAME', 4096, 'geom', 'id') FROM (
            SELECT id, name, lat,long,importance,importance_metric,
            ST_AsMVTGeom(
                ST_Transform(TEMPLATENAME.geom, 3857),
                ST_TileEnvelope(z,x,y),
                4096, 0, true
            ) as geom,

            -- TODO extract the custom data fields here (and add them in config.yaml)
            data->'name:de' as de_name,
            data->'wikipedia' as wikipedia,
            data->'wikidata' as wikidata

            FROM TEMPLATENAME
            WHERE ST_TRANSFORM(TEMPLATENAME.geom,4674) && ST_Transform(ST_TileEnvelope(z,x,y), 4674)
        ) as tile;

    END IF;


  RETURN mvt;
END
$$ LANGUAGE plpgsql IMMUTABLE STRICT PARALLEL SAFE;