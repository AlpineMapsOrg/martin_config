
-- drop everything we dont need
DROP FUNCTION IF EXISTS cities_tile;
DROP INDEX distance_cities_geom_idx;
DROP INDEX distance_cities_zoom_idx;
DROP INDEX cities_geom_idx;
DROP INDEX cities_importance_metric_idx;
DROP MATERIALIZED VIEW IF EXISTS distance_cities;
DROP MATERIALIZED VIEW IF EXISTS cities;

-- view for cities
-- CREATE VIEW cities AS 
CREATE MATERIALIZED VIEW cities AS
    -- general attributes (all features should have them)
    SELECT osm_id as id,
        planet_osm_point.name,
        ST_X(ST_TRANSFORM(planet_osm_point.way,4674)) AS long,
        ST_Y(ST_TRANSFORM(planet_osm_point.way,4674)) AS lat,
        planet_osm_point.way as geom,

        -- set population as importance_metric
        COALESCE(substring(planet_osm_point.population FROM '[0-9]+')::int, 0) as importance_metric,

        slice( -- only extracts attributes defined by array
            planet_osm_point.tags 
                    || hstore('population', COALESCE(substring(planet_osm_point.population FROM '[0-9]+')::int, 0)::text)
                    || hstore('place',  planet_osm_point.place),
            ARRAY[
                'name:de',
                'wikipedia',
                'wikidata',
                'population',
                'place',
                'population:date',
                'website'
            ]
        ) as data

    FROM planet_osm_point
    WHERE (
        planet_osm_point."place" = 'city'::text 
        or planet_osm_point."place" = 'town'::text
        or planet_osm_point."place" = 'village'::text
        or planet_osm_point."place" = 'hamlet'::text
    ) AND name IS NOT NULL
    ORDER BY importance_metric desc;


CREATE INDEX cities_geom_idx
  ON cities
  USING GIST (geom);

CREATE INDEX cities_importance_metric_idx
  ON cities(importance_metric);  -- automatcially uses b-tree


-- we want to prioritize POIs with the higher distances to other POIs where the importance_metric is higher than itself.
-- e.g. Kleinglockner is near Großglockner (small distance -> will only be shown very late although it has a high altitude)
-- the following materialized view calculates those distances to each POI within a certain radius (search radius defined in cluster_dist as 1/3 of tile width and currently starting to search with zoom level 8)
-- all_distances calculates the min_dist to better POI
-- whereas the final select creates a list for each individual zoom level and orders those results by importance_metric
CREATE MATERIALIZED VIEW distance_cities AS
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
        -- this way it will always be here if no taller cities has been found in radius
        min((CASE 
            WHEN a.id = b.id
            THEN cd.dist
            ELSE ST_Distance(a.geom, b.geom)
        END)) as min_dist
    FROM cd CROSS JOIN cities a LEFT JOIN cities b ON (ST_DWithin(a.geom, b.geom, cd.dist) and b.importance_metric >= a.importance_metric)
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
CREATE INDEX distance_cities_geom_idx
  ON distance_cities
  USING GIST (geom);


CREATE INDEX distance_cities_zoom_idx
  ON distance_cities
  USING HASH (zoom);




CREATE OR REPLACE
    FUNCTION cities_tile(z integer, x integer, y integer)
    RETURNS bytea AS $$
DECLARE
    mvt bytea;
BEGIN
    IF (z < 22) THEN
        -- only POIs with highest importance metric in vicinity visible
        SELECT INTO mvt ST_AsMVT(tile, 'cities', 4096, 'geom', 'id') FROM (

            SELECT id, name, lat,long,importance,importance_metric,
            ST_AsMVTGeom(
                ST_Transform(distance_cities.geom, 3857),
                ST_TileEnvelope(z,x,y),
                4096, 0, true
            ) as geom,

            data->'name:de' as de_name,
            data->'wikipedia' as wikipedia,
            data->'wikidata' as wikidata,
            (data->'population')::int as population,
            data->'place' as place,
            data->'population:date' as population_date,
            data->'website' as website

            FROM distance_cities
            WHERE zoom = z AND ST_TRANSFORM(distance_cities.geom,4674) && ST_Transform(ST_TileEnvelope(z,x,y), 4674)
            LIMIT 4
        ) as tile;
    ELSE
    -- all POIs visible
        SELECT INTO mvt ST_AsMVT(tile, 'cities', 4096, 'geom', 'id') FROM (

            SELECT id, name, lat,long,importance,importance_metric,
            ST_AsMVTGeom(
                ST_Transform(distance_cities.geom, 3857),
                ST_TileEnvelope(z,x,y),
                4096, 0, true
            ) as geom,

            data->'name:de' as de_name,
            data->'wikipedia' as wikipedia,
            data->'wikidata' as wikidata,
            (data->'population')::int as population,
            data->'place' as place,
            data->'population:date' as population_date,
            data->'website' as website

            FROM distance_cities
            WHERE zoom = 21 AND ST_TRANSFORM(distance_cities.geom,4674) && ST_Transform(ST_TileEnvelope(z,x,y), 4674)
        ) as tile;
        
    END IF;


  RETURN mvt;
END
$$ LANGUAGE plpgsql IMMUTABLE STRICT PARALLEL SAFE;