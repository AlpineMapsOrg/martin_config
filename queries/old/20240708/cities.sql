
-- columns that are passed through
-- id,name,long,lat,geom,place,population


-- view for cities
DROP VIEW IF EXISTS cities;

CREATE VIEW cities AS 
    -- general attributes (all features should have them)
    SELECT 
    planet_osm_point.osm_id as id,
    planet_osm_point.name,
    ST_X(ST_TRANSFORM(planet_osm_point.way,4674)) AS long,
    ST_Y(ST_TRANSFORM(planet_osm_point.way,4674)) AS lat,
    planet_osm_point.way as geom,
    planet_osm_point.place,
    -- this makes sure that the value is a valid number and at least 0 (-> necessary for correct ordering)
    COALESCE(substring(planet_osm_point.population FROM '[0-9]+')::int, 0) as population
    
    -- tags."wikidata",
    -- tags."wikipedia",
    -- tags."population:date"

   FROM planet_osm_point
WHERE (
    planet_osm_point."place" = 'city'::text 
    or planet_osm_point."place" = 'town'::text
    or planet_osm_point."place" = 'village'::text
    or planet_osm_point."place" = 'hamlet'::text
) AND name IS NOT NULL
;

--   SELECT * from cities WHERE name = 'Möllersdorf'
-- ;








-- drop indices and materialized view as we are recreating them shortly
DROP INDEX distance_cities_geom_idx;
DROP INDEX distance_cities_zoom_idx;
DROP MATERIALIZED VIEW IF EXISTS distance_cities;

CREATE MATERIALIZED VIEW distance_cities AS
WITH cd AS (
    SELECT * from cluster_dists
    WHERE zoom = 8 -- min cluster zoom level is defined here
), all_distances as (
    SELECT
        a.id,a.name,a.long,a.lat,a.place,a.population,a.geom,
        b.population as population_dist,
        
        -- this sets the distance to max for itself
        -- this way it will always be here if no taller cities has been found in radius
        (CASE 
            WHEN a.id = b.id
            THEN cd.dist
            ELSE ST_Distance(a.geom, b.geom)
        END) as dist
    -- FROM search_distances sd, cities a LEFT JOIN cities b ON ST_DWithin(a.geom, b.geom, 208724)
    FROM cd CROSS JOIN cities a LEFT JOIN cities b ON ST_DWithin(a.geom, b.geom, cd.dist)
    -- WHERE a.name = 'Kleiner Burgstall'
    ORDER BY population DESC, id ASC, dist ASC
)
SELECT
    all_distances.id,all_distances.name,all_distances.long,all_distances.lat,all_distances.place,all_distances.population,all_distances.geom,
    cluster_dists.zoom,
    min(all_distances.dist) as mindist 
FROM cd, all_distances LEFT JOIN cluster_dists ON (cluster_dists.zoom >= 8 and cluster_dists.zoom < 22)
WHERE 
    -- only apply min to distances within cluster dist (or to itself for fallback if no other available)
    (all_distances.dist <= cluster_dists.dist or all_distances.dist = cd.dist)
    -- we are only interested in other POI if value is higher than self
    AND all_distances.population <= all_distances.population_dist
-- we are using min -> everything else has to be grouped
GROUP BY id,name,long,lat,place,population,geom, cluster_dists.zoom
-- finally order by mindist and population since we prefer them as populated as possible
ORDER BY mindist DESC, population DESC
;


-- create index for faster geom lookups
CREATE INDEX distance_cities_geom_idx
  ON distance_cities
  USING GIST (geom);


CREATE INDEX distance_cities_zoom_idx
  ON distance_cities
  USING HASH (zoom);










DROP FUNCTION IF EXISTS city_tile;

CREATE OR REPLACE
    FUNCTION city_tile(z integer, x integer, y integer)
    RETURNS bytea AS $$
DECLARE
    mvt bytea;
BEGIN
    IF (z < 22) THEN
        -- highest cities visible
        SELECT INTO mvt ST_AsMVT(tile, 'City', 4096, 'geom', 'id') FROM (

            SELECT

            id,name,long,lat,place,population,

            
            ST_AsMVTGeom(
                ST_Transform(distance_cities.geom, 3857),
                ST_TileEnvelope(z,x,y),
                4096, 0, true
            ) as geom
            FROM distance_cities
            WHERE zoom = z AND ST_TRANSFORM(distance_cities.geom,4674) && ST_Transform(ST_TileEnvelope(z,x,y), 4674)
            LIMIT 4
        ) as tile;
    ELSE
    -- all cities visible
        SELECT INTO mvt ST_AsMVT(tile, 'City', 4096, 'geom', 'id') FROM (
            SELECT 
            id,name,long,lat,place,population,

            ST_AsMVTGeom(
                ST_Transform(cities.geom, 3857),
                ST_TileEnvelope(z,x,y),
                4096, 0, true
            ) as geom
            FROM cities
            WHERE ST_TRANSFORM(cities.geom,4674) && ST_Transform(ST_TileEnvelope(z,x,y), 4674)
        ) as tile;

    END IF;


  RETURN mvt;
END
$$ LANGUAGE plpgsql IMMUTABLE STRICT PARALLEL SAFE;