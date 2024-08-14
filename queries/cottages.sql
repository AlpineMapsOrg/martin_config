-- for TU WIEN change 
-- planet_osm_point.ele 
-- planet_osm_point.tags->'ele'

-- drop everything we dont need
DROP FUNCTION IF EXISTS metahelper_cottages;
DROP FUNCTION IF EXISTS cottages_tile;
DROP INDEX distance_cottages_geom_idx;
DROP INDEX distance_cottages_zoom_idx;
DROP INDEX cottages_geom_idx;
DROP INDEX cottages_importance_metric_idx;
DROP MATERIALIZED VIEW IF EXISTS distance_cottages;
DROP MATERIALIZED VIEW IF EXISTS cottages_temp;

-- view for cottages
-- CREATE VIEW cottages AS 
CREATE MATERIALIZED VIEW cottages_temp AS
    -- general attributes (all features should have them)
    SELECT osm_id as id,
        COALESCE(planet_osm_point.tags->'name:de', planet_osm_point.name) as name, -- prefer german name
        ST_X(ST_TRANSFORM(planet_osm_point.way,4674)) AS long,
        ST_Y(ST_TRANSFORM(planet_osm_point.way,4674)) AS lat,
        planet_osm_point.way as geom,

        -- the number of tags is used as a metric for the clustering algorithm
        -- -> more tags more important 
        COALESCE(array_length(avals(planet_osm_point.tags), 1),0) AS importance_metric,

        slice( -- only extracts attributes defined by array
            -- add additional values to the hstore 
            planet_osm_point.tags 
                || hstore('addr:housenumber',  planet_osm_point."addr:housenumber"::text)
                || hstore('type',  planet_osm_point.tourism::text)
                || hstore('ele', FLOOR(nullif(substring(planet_osm_point.ele FROM '[0-9]+'), '')::decimal)::int::text)
                -- combine similar data fields
                || hstore('email', COALESCE(planet_osm_point.tags->'contact:email', 'email')::text)
                || hstore('website', COALESCE(planet_osm_point.tags->'contact:website', 'website')::text)
                || hstore('phone', COALESCE(planet_osm_point.tags->'contact:phone', 'phone')::text),
            ARRAY[
                'wikipedia',
                'wikidata',
                'description',
                'capacity',
                'opening_hours',
                'shower',
                'phone',
                'email',
                'website',
                'internet_access',
                'addr:city',
                'addr:street',
                'addr:postcode',

                'addr:housenumber',
                'operator',
                'type',
                'access',
                'ele'
            ]
        ) as data

    FROM planet_osm_point
    WHERE (
        planet_osm_point."tourism" = 'alpine_hut'::text or 
        planet_osm_point."tourism" = 'wilderness_hut'::text 
        -- planet_osm_point."tourism" = 'chalet'::text
    ) AND name IS NOT NULL
    ORDER BY importance_metric desc;


CREATE INDEX cottages_geom_idx
  ON cottages_temp
  USING GIST (geom);

CREATE INDEX cottages_importance_metric_idx
  ON cottages_temp(importance_metric);  -- automatcially uses b-tree


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
    FROM cd CROSS JOIN cottages_temp a LEFT JOIN cottages_temp b ON (ST_DWithin(a.geom, b.geom, cd.dist) and b.importance_metric >= a.importance_metric)
    GROUP BY a.id, a.name, a.data, a.geom, a.long, a.lat, a.importance_metric
    ORDER BY importance_metric DESC, min_dist DESC
)
SELECT
    id, name, data, geom, long, lat,
    importance_metric,
    cluster_dists.zoom,
    -- importance: in interval [0,1] 1 means that it has the max importances (= max distance to POIs with higher metric than itself)
    LEAST(min_dist::real / cd.dist::real, 1.0)::real as importance
FROM cd, all_distances LEFT JOIN cluster_dists ON (cluster_dists.zoom >= 8 and cluster_dists.zoom < 22)
ORDER BY importance DESC, importance_metric DESC
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

            SELECT id, name, lat,long,importance,importance_metric,
            ST_AsMVTGeom(
                ST_Transform(distance_cottages.geom, 3857),
                ST_TileEnvelope(z,x,y),
                4096, 0, true
            ) as geom,

            data->'wikipedia' as wikipedia,
            data->'wikidata' as wikidata,
            data->'description' as description,
            data->'capacity' as capacity,
            data->'opening_hours' as opening_hours,
            data->'shower' as shower,
            data->'phone' as phone,
            data->'email' as email,
            data->'website' as website,
            data->'internet_access' as internet_access,
            data->'addr:city' as addr_city,
            data->'addr:street' as addr_street,
            data->'addr:postcode' as addr_postcode,
            data->'addr:housenumber' as addr_housenumber,
            data->'operator' as operator,
            data->'type' as type,
            data->'access' as access,
            (data->'ele')::int as ele

            FROM distance_cottages
            WHERE zoom = z AND ST_TRANSFORM(distance_cottages.geom,4674) && ST_Transform(ST_TileEnvelope(z,x,y), 4674)
            LIMIT 4
        ) as tile;
    ELSE
    -- all POIs visible
        SELECT INTO mvt ST_AsMVT(tile, 'cottages', 4096, 'geom', 'id') FROM (
            SELECT id, name, lat,long,importance,importance_metric,
            ST_AsMVTGeom(
                ST_Transform(distance_cottages.geom, 3857),
                ST_TileEnvelope(z,x,y),
                4096, 0, true
            ) as geom,

            data->'wikipedia' as wikipedia,
            data->'wikidata' as wikidata,
            data->'description' as description,
            data->'capacity' as capacity,
            data->'opening_hours' as opening_hours,
            data->'shower' as shower,
            data->'phone' as phone,
            data->'email' as email,
            data->'website' as website,
            data->'internet_access' as internet_access,
            data->'addr:city' as addr_city,
            data->'addr:street' as addr_street,
            data->'addr:postcode' as addr_postcode,
            data->'addr:housenumber' as addr_housenumber,
            data->'operator' as operator,
            data->'type' as type,
            data->'access' as access,
            (data->'ele')::int as ele

            FROM distance_cottages
            WHERE zoom = 21 AND ST_TRANSFORM(distance_cottages.geom,4674) && ST_Transform(ST_TileEnvelope(z,x,y), 4674)
        ) as tile;

    END IF;


  RETURN mvt;
END
$$ LANGUAGE plpgsql IMMUTABLE STRICT PARALLEL SAFE;

------------------------
-- Helper function to understand the data encapsulated by the underlying table better
------------------------

CREATE OR REPLACE
    FUNCTION metahelper_cottages(min_amount_with_key integer, max_values_per_key integer) 
  returns table(keys text, entries_with_values integer, distinct_value_amount integer, value text[]) 
as $$

  WITH source as (
    SELECT planet_osm_point.tags as tags
    FROM planet_osm_point
    WHERE (
        planet_osm_point."tourism" = 'alpine_hut'::text or 
        planet_osm_point."tourism" = 'wilderness_hut'::text 
        -- planet_osm_point."tourism" = 'chalet'::text
    ) AND name IS NOT NULL
  )
  SELECT keys,
    entries_with_values,
    array_length(vals, 1) as distinct_value_amount, -- how many distinct values are there
    (CASE 
        WHEN array_length(vals, 1) > max_values_per_key
        THEN array[vals[1], vals[max_values_per_key/2]]::text[] -- too many different values -> return two example value
        ELSE vals
    END) as value
  FROM (
    SELECT keys, entries_with_values, array_agg(DISTINCT source.tags->keys) as vals
    FROM source, (
      SELECT skeys(tags) as keys,
       count(*) as entries_with_values -- how many POIs have the key
      FROM source
      GROUP BY keys
    ) as distinct_keys
    WHERE entries_with_values > min_amount_with_key -- only propagate if at least 10 POIs has the key
    GROUP BY distinct_keys.keys, distinct_keys.entries_with_values
  ) as keys_with_values

$$ language sql;


-- HOW TO USE ABOVE FUNCTION:
-- SELECT * from metahelper_cottages(10,10)
-- ORDER BY entries_with_values DESC;
