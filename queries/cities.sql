-- for TU WIEN change 
-- planet_osm_point.population 
-- planet_osm_point.tags->'population'


-- drop everything we dont need
DROP FUNCTION IF EXISTS metahelper_cities;
DROP FUNCTION IF EXISTS cities_tile;
DROP INDEX distance_cities_geom_idx;
DROP INDEX cities_geom_idx;
DROP INDEX cities_importance_metric_idx;
DROP MATERIALIZED VIEW IF EXISTS distance_cities;
DROP MATERIALIZED VIEW IF EXISTS cities_temp;

-- view for cities
-- CREATE VIEW cities AS 
CREATE MATERIALIZED VIEW cities_temp AS
    -- general attributes (all features should have them)
    SELECT osm_id as id,
        COALESCE(planet_osm_point.tags->'name:de', planet_osm_point.name) as name, -- prefer german name
        ST_X(ST_TRANSFORM(planet_osm_point.way,4674)) AS long,
        ST_Y(ST_TRANSFORM(planet_osm_point.way,4674)) AS lat,
        planet_osm_point.way as geom,

        -- set population as importance_metric
        -- COALESCE(substring(planet_osm_point.population FROM '[0-9]+')::int, 0) as importance_metric,
        COALESCE(substring(planet_osm_point.population FROM '[0-9]+')::int, 0) as importance_metric,

        slice( -- only extracts attributes defined by array
            planet_osm_point.tags 
                    -- || hstore('population', COALESCE(substring(planet_osm_point.population FROM '[0-9]+')::int, 0)::text)
                    || hstore('population', COALESCE(substring(planet_osm_point.population FROM '[0-9]+')::int, 0)::text)
                    || hstore('place',  planet_osm_point.place),
            ARRAY[
                'wikipedia',
                'wikidata',
                'population',
                'place',
                'population:date',
                'website',
                'population:source',
                'postal_code'
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
  ON cities_temp
  USING GIST (geom);

CREATE INDEX cities_importance_metric_idx
  ON cities_temp(importance_metric);  -- automatcially uses b-tree


-- we want to prioritize POIs with the higher distances to other POIs where the importance_metric is higher than itself.
-- e.g. Kleinglockner is near Großglockner (small distance -> will only be shown very late although it has a high altitude)
-- the following materialized view calculates those distances to each POI within a certain radius (search radius defined in cluster_dist as 1/3 of tile width and zoom level 8)
-- the select calculates the min_dist to better POI (saved as importance which is the normalized distance [0,1] interval)
CREATE MATERIALIZED VIEW distance_cities AS
WITH cd AS (
    SELECT * from cluster_dists
    WHERE zoom = 8 -- cluster zoom level is defined here
)
SELECT a.id,
    a.name,
    a.data,
    a.importance_metric as importance_metric,
    a.geom,
    a.long,
    a.lat,
    -- this sets the distance to max for itself
    -- this way it will always be here if no better cities have been found in the radius
    min(
    (CASE 
        WHEN a.id = b.id
        THEN 1.0
        ELSE LEAST(ST_Distance(a.geom, b.geom)::real / cd.dist::real, 1.0)::real
    END)) as importance -- =normalized min_dist
FROM cd CROSS JOIN cities_temp a LEFT JOIN cities_temp b ON (ST_DWithin(a.geom, b.geom, cd.dist) and b.importance_metric >= a.importance_metric)
GROUP BY a.id, a.name, a.data, a.geom, a.long, a.lat, a.importance_metric
ORDER BY importance DESC, importance_metric DESC
;



-- create index for faster geom lookups
CREATE INDEX distance_cities_geom_idx
  ON distance_cities
  USING GIST (geom);





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

            data->'wikipedia' as wikipedia,
            data->'wikidata' as wikidata,
            (data->'population')::int as population,
            data->'place' as place,
            data->'population:date' as population_date,
            data->'population:source' as population_source,
            data->'postal_code' as website,
            data->'website' as website


            FROM distance_cities
            WHERE ST_TRANSFORM(distance_cities.geom,4674) && ST_Transform(ST_TileEnvelope(z,x,y), 4674)
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

            data->'wikipedia' as wikipedia,
            data->'wikidata' as wikidata,
            (data->'population')::int as population,
            data->'place' as place,
            data->'population:date' as population_date,
            data->'population:source' as population_source,
            data->'postal_code' as website,
            data->'website' as website

            FROM distance_cities
            WHERE ST_TRANSFORM(distance_cities.geom,4674) && ST_Transform(ST_TileEnvelope(z,x,y), 4674)
        ) as tile;
    END IF;


  RETURN mvt;
END
$$ LANGUAGE plpgsql IMMUTABLE STRICT PARALLEL SAFE;



------------------------
-- Helper function to understand the data encapsulated by the underlying table better
------------------------

CREATE OR REPLACE
    FUNCTION metahelper_cities(min_amount_with_key integer, max_values_per_key integer) 
  returns table(keys text, entries_with_values integer, distinct_value_amount integer, value text[]) 
as $$

  WITH source as (
    SELECT planet_osm_point.tags as tags
    FROM planet_osm_point
    WHERE (
        planet_osm_point."place" = 'city'::text 
        or planet_osm_point."place" = 'town'::text
        or planet_osm_point."place" = 'village'::text
        or planet_osm_point."place" = 'hamlet'::text
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
-- SELECT * from metahelper_cities(10,10)
-- ORDER BY entries_with_values DESC;

