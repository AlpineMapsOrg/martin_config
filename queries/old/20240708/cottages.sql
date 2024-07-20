
-- columns that are passed through
-- id, name, long,lat, geom, access, ele, operator, tourism, housenumber, description, capacity, opening_hours, reservation, electricity, shower, winter_room, phone, website, seasonal, internet_access, fee, city, street, postcode

-- -- view for cottages
DROP VIEW IF EXISTS cottages CASCADE;

CREATE VIEW cottages AS 
    -- general attributes (all features should have them)
    SELECT
        planet_osm_point.osm_id as id,
        planet_osm_point.name,
        ST_X(ST_TRANSFORM(planet_osm_point.way,4674)) AS long,
        ST_Y(ST_TRANSFORM(planet_osm_point.way,4674)) AS lat,
        planet_osm_point.way as geom,
        
        planet_osm_point.access,
        FLOOR(nullif(substring(ele FROM '[0-9]+'), '')::decimal)::int as ele,
        planet_osm_point.operator,
        planet_osm_point.tourism,
        planet_osm_point."addr:housenumber" as housenumber,

        

        planet_osm_point.tags->'description' as description,
        planet_osm_point.tags->'capacity' as capacity,
        planet_osm_point.tags->'opening_hours' as opening_hours,
        planet_osm_point.tags->'reservation' as reservation,
        planet_osm_point.tags->'electricity' as electricity,
        planet_osm_point.tags->'shower' as shower,
        planet_osm_point.tags->'winter_room' as winter_room,
        planet_osm_point.tags->'phone' as phone,
        planet_osm_point.tags->'website' as website,
        planet_osm_point.tags->'seasonal' as seasonal,
        planet_osm_point.tags->'internet_access' as internet_access,
        planet_osm_point.tags->'fee' as fee,
        planet_osm_point.tags->'addr:city' as city,
        planet_osm_point.tags->'addr:street' as street,
        planet_osm_point.tags->'addr:postcode' as postcode,

        -- the number of tags is used as a metric for the clustering algorithm
        -- -> more tags more important 
        COALESCE(array_length(avals(planet_osm_point.tags), 1),0) AS importance_metric


   FROM planet_osm_point
WHERE (
    planet_osm_point."tourism" = 'alpine_hut'::text or 
    planet_osm_point."tourism" = 'wilderness_hut'::text 
    -- planet_osm_point."tourism" = 'chalet'::text
) AND name IS NOT NULL
;

SELECT name from cottages LIMIT 30;






-- drop indices and materialized view as we are recreating them shortly
DROP INDEX distance_cottages_geom_idx;
DROP INDEX distance_cottages_zoom_idx;
DROP MATERIALIZED VIEW IF EXISTS distance_cottages;

CREATE MATERIALIZED VIEW distance_cottages AS
WITH cd AS (
    SELECT * from cluster_dists
    WHERE zoom = 8 -- min cluster zoom level is defined here
), all_distances as (
    SELECT
        a.id, a.name, a.long,a.lat, a.geom, a.access, a.ele, a.operator, a.tourism, a.housenumber, a.description, a.capacity, a.opening_hours, a.reservation, a.electricity, a.shower, a.winter_room, a.phone, a.website, a.seasonal, a.internet_access, a.fee, a.city, a.street, a.postcode,
        a.importance_metric,
        b.importance_metric as importance_metric_dist,
        
        -- this sets the distance to max for itself
        -- this way it will always be here if no taller cottages has been found in radius
        (CASE 
            WHEN a.id = b.id
            THEN cd.dist
            ELSE ST_Distance(a.geom, b.geom)
        END) as dist
    -- FROM search_distances sd, cottages a LEFT JOIN cottages b ON ST_DWithin(a.geom, b.geom, 208724)
    FROM cd CROSS JOIN cottages a LEFT JOIN cottages b ON ST_DWithin(a.geom, b.geom, cd.dist)
    ORDER BY importance_metric DESC, dist ASC, id ASC
)
SELECT
    all_distances.id, all_distances.name, all_distances.long,all_distances.lat, all_distances.geom, all_distances.access, all_distances.ele, all_distances.operator, all_distances.tourism, all_distances.housenumber, all_distances.description, all_distances.capacity, all_distances.opening_hours, all_distances.reservation, all_distances.electricity, all_distances.shower, all_distances.winter_room, all_distances.phone, all_distances.website, all_distances.seasonal, all_distances.internet_access, all_distances.fee, all_distances.city, all_distances.street, all_distances.postcode,

    cluster_dists.zoom,
    min(all_distances.dist) as mindist 
FROM cd, all_distances LEFT JOIN cluster_dists ON (cluster_dists.zoom >= 8 and cluster_dists.zoom < 22)
WHERE 
    -- only apply min to distances within cluster dist (or to itself for fallback if no other available)
    (all_distances.dist <= cluster_dists.dist or all_distances.dist = cd.dist)
    -- we are only interested in other POI if value is higher than self
    AND all_distances.importance_metric <= all_distances.importance_metric_dist
-- we are using min -> everything else has to be grouped



GROUP BY importance_metric, id, name, long,lat, geom, access, ele, operator, tourism, housenumber, description, capacity, opening_hours, reservation, electricity, shower, winter_room, phone, website, seasonal, internet_access, fee, city, street, postcode, cluster_dists.zoom
-- finally order by mindist and importance_metric
ORDER BY mindist DESC, importance_metric DESC
;


-- create index for faster geom lookups
CREATE INDEX distance_cottages_geom_idx
  ON distance_cottages
  USING GIST (geom);


CREATE INDEX distance_cottages_zoom_idx
  ON distance_cottages
  USING HASH (zoom);









DROP FUNCTION IF EXISTS cottage_tile;

CREATE OR REPLACE
    FUNCTION cottage_tile(z integer, x integer, y integer)
    RETURNS bytea AS $$
DECLARE
    mvt bytea;
BEGIN
    IF (z < 22) THEN
        -- highest cottages visible
        SELECT INTO mvt ST_AsMVT(tile, 'Cottage', 4096, 'geom', 'id') FROM (

            SELECT

            id, name, long,lat, access, ele, operator, tourism, housenumber, description, capacity, opening_hours, reservation, electricity, shower, winter_room, phone, website, seasonal, internet_access, fee, city, street, postcode,

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
    -- all cottages visible
        SELECT INTO mvt ST_AsMVT(tile, 'Cottage', 4096, 'geom', 'id') FROM (
            SELECT 
            
            id, name, long,lat, access, ele, operator, tourism, housenumber, description, capacity, opening_hours, reservation, electricity, shower, winter_room, phone, website, seasonal, internet_access, fee, city, street, postcode,
            
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