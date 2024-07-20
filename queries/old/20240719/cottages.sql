
-- change cottages with your desired name (e.g. peaks)


-- drop everything we dont need
DROP FUNCTION IF EXISTS cottages_tile;
DROP INDEX distance_cottages_geom_idx;
DROP INDEX distance_cottages_zoom_idx;
DROP INDEX cottages_geom_idx;
DROP INDEX cottages_importance_metric_idx;
DROP MATERIALIZED VIEW IF EXISTS distance_cottages;
DROP MATERIALIZED VIEW IF EXISTS cottages;

-- view for cottages
-- CREATE VIEW cottages AS 
CREATE MATERIALIZED VIEW cottages AS
    -- general attributes (all features should have them)
    SELECT osm_id as id,
        planet_osm_point.name,
        ST_X(ST_TRANSFORM(planet_osm_point.way,4674)) AS long,
        ST_Y(ST_TRANSFORM(planet_osm_point.way,4674)) AS lat,
        planet_osm_point.way as geom,

        -- the number of tags is used as a metric for the clustering algorithm
        -- -> more tags more important 
        COALESCE(array_length(avals(planet_osm_point.tags), 1),0) AS importance_metric,

        hstore_to_matrix ( -- output {{key1,value1},{key2,value2},...}
            slice( -- only extracts attributes defined by array
                -- add additional values to the hstore 
                planet_osm_point.tags 
                    || hstore('addr:housenumber',  planet_osm_point."addr:housenumber"::text)
                    || hstore('operator',  planet_osm_point.operator::text)
                    || hstore('type',  planet_osm_point.tourism::text)
                    || hstore('access',  planet_osm_point.access::text)
                    || hstore('ele', FLOOR(nullif(substring(ele FROM '[0-9]+'), '')::decimal)::int::text),
                ARRAY[
                    'name:de',
                    'wikipedia',
                    'wikidata',
                    'description',
                    'capacity',
                    'opening_hours',
                    'reservation',
                    'electricity',
                    'shower',
                    'winter_room',
                    'phone',
                    'website',
                    'seasonal',
                    'internet_access',
                    'fee',
                    'addr:city',
                    'addr:street',
                    'addr:postcode',

                    'addr:housenumber',
                    'operator',
                    'type',
                    'access',
                    'ele'
                ]
            )
        )::TEXT  as data

    FROM planet_osm_point
    WHERE (
        planet_osm_point."tourism" = 'alpine_hut'::text or 
        planet_osm_point."tourism" = 'wilderness_hut'::text 
        -- planet_osm_point."tourism" = 'chalet'::text
    ) AND name IS NOT NULL
    ORDER BY importance_metric desc;


CREATE INDEX cottages_geom_idx
  ON cottages
  USING GIST (geom);

CREATE INDEX cottages_importance_metric_idx
  ON cottages(importance_metric);  -- automatcially uses b-tree


-- we want to prioritize POIs with the higher distances to other POIs where the importance_metric is higher than itself.
-- e.g. Kleinglockner is near Großglockner (small distance -> will only be shown very late although it has a high altitude)
-- the following materialized view calculates those distances to each POI within a certain radius (search radius defined in cluster_dist as 1/3 of tile width and currently starting to search with zoom level 8)
-- all_distances calculates the min_dist to better POI
-- whereas the final select creates a list for each individual zoom level and orders those results by importance_metric
CREATE MATERIALIZED VIEW distance_cottages AS
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
        -- this way it will always be here if no taller cottages has been found in radius
        min((CASE 
            WHEN a.id = b.id
            THEN cd.dist
            ELSE ST_Distance(a.geom, b.geom)
        END)) as min_dist
    FROM cd CROSS JOIN cottages a LEFT JOIN cottages b ON (ST_DWithin(a.geom, b.geom, cd.dist) and b.importance_metric >= a.importance_metric)
    GROUP BY a.id, a.name, a.data, a.geom, a.long, a.lat, a.importance_metric
    ORDER BY importance_metric DESC, min_dist DESC
)
SELECT
    id, name, data, geom, long, lat,
    importance_metric,
    cluster_dists.zoom,
    --clamp min_dist to current zoom level cluster_dists.dist (this ensures that POI with short min_dist but higher importance_metric are more relevant if zoom level allows for it)
    LEAST(min_dist, cluster_dists.dist) as min_dist
FROM cd, all_distances LEFT JOIN cluster_dists ON (cluster_dists.zoom >= 8 and cluster_dists.zoom < 22)
ORDER BY min_dist DESC, importance_metric DESC
;



-- create index for faster geom lookups
CREATE INDEX distance_cottages_geom_idx
  ON distance_cottages
  USING GIST (geom);


CREATE INDEX distance_cottages_zoom_idx
  ON distance_cottages
  USING HASH (zoom);




CREATE OR REPLACE
    FUNCTION cottages_tile(z integer, x integer, y integer)
    RETURNS bytea AS $$
DECLARE
    mvt bytea;
BEGIN
    IF (z < 22) THEN
        -- only POIs with highest importance metric in vicinity visible
        SELECT INTO mvt ST_AsMVT(tile, 'cottages', 4096, 'geom', 'id') FROM (

            SELECT id, name, data, lat,long,importance_metric,
            ST_AsMVTGeom(
                ST_Transform(distance_cottages.geom, 3857),
                ST_TileEnvelope(z,x,y),
                4096, 0, true
            ) as geom
            FROM distance_cottages
            WHERE zoom = z AND ST_TRANSFORM(distance_cottages.geom,4674) && ST_Transform(ST_TileEnvelope(z,x,y), 4674)
            LIMIT 4
        ) as tile;
    ELSE
    -- all POIs visible
        SELECT INTO mvt ST_AsMVT(tile, 'cottages', 4096, 'geom', 'id') FROM (
            SELECT id, name, data, lat,long,importance_metric,
            ST_AsMVTGeom(
                ST_Transform(cottages.geom, 3857),
                ST_TileEnvelope(z,x,y),
                4096, 0, true
            ) as geom
            FROM cottages
            WHERE ST_TRANSFORM(cottages.geom,4674) && ST_Transform(ST_TileEnvelope(z,x,y), 4674)
        ) as tile;

    END IF;


  RETURN mvt;
END
$$ LANGUAGE plpgsql IMMUTABLE STRICT PARALLEL SAFE;