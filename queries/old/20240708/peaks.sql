

-- drop everything we dont need
DROP FUNCTION IF EXISTS peak_tile;
DROP INDEX distance_peaks_geom_idx;
DROP INDEX distance_peaks_zoom_idx;
DROP INDEX peaks_geom_idx;
DROP INDEX peaks_importance_metric_idx;
DROP MATERIALIZED VIEW IF EXISTS distance_peaks;
DROP MATERIALIZED VIEW IF EXISTS peaks;

-- view for peaks
-- CREATE VIEW peaks AS 
CREATE MATERIALIZED VIEW peaks AS
    -- general attributes (all features should have them)
    SELECT osm_id as id,
    planet_osm_point.name,
    ST_X(ST_TRANSFORM(planet_osm_point.way,4674)) AS long,
    ST_Y(ST_TRANSFORM(planet_osm_point.way,4674)) AS lat,
    planet_osm_point.way as geom,

    -- feature specific
    -- note for elevation:
        -- ->trim resolves issues where meter is specified (e.g. "602 m")
        -- ->decimal cast and flooring resolves issues where number was in decimal (e.g. "1060.0")
        -- TODO what if instead of metres it is declared in feet
    -- FLOOR(nullif(trim(trailing 'm' from ele), '')::decimal)::int as ele
    FLOOR(nullif(substring(ele FROM '[0-9]+'), '')::decimal)::int as ele,
    FLOOR(nullif(substring(ele FROM '[0-9]+'), '')::decimal)::int as importance_metric

   FROM planet_osm_point
  WHERE planet_osm_point."natural" = 'peak'::text AND name IS NOT NULL AND ele IS NOT NULL
  ORDER BY importance_metric desc;


CREATE INDEX peaks_geom_idx
  ON peaks
  USING GIST (geom);

CREATE INDEX peaks_importance_metric_idx
  ON peaks(importance_metric);  -- automatcially uses b-tree


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
        a.ele as ele,
        a.importance_metric as importance_metric,
        -- b.importance_metric as importance_metric_dist,
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
    FROM cd CROSS JOIN peaks a LEFT JOIN peaks b ON (ST_DWithin(a.geom, b.geom, cd.dist) and b.importance_metric >= a.importance_metric)
    GROUP BY a.id, a.name, a.ele, a.geom, a.long, a.lat, a.importance_metric
    ORDER BY importance_metric DESC, min_dist DESC
)
SELECT
    id, name, ele, geom, long, lat,
    importance_metric,
    cluster_dists.zoom,
    LEAST(min_dist, cluster_dists.dist)
    -- min_dist -- todo clamp min_dist to current zoom level cluster_dists.dist (this ensures that POI with short min_dist but higher importance_metric are more relevant if zoom level allows for it)
    -- min(all_distances.dist) as mindist 
FROM cd, all_distances LEFT JOIN cluster_dists ON (cluster_dists.zoom >= 8 and cluster_dists.zoom < 22)
-- WHERE 
    -- only apply min to distances within cluster dist (or to itself for fallback if no other available)
    -- (all_distances.min_dist <= cluster_dists.dist or all_distances.min_dist = cd.dist)
    -- we are only interested in other POI if value is higher than self
    -- AND all_distances.importance_metric <= all_distances.importance_metric_dist
-- we are using min -> everything else has to be grouped
-- GROUP BY id, name, ele, geom, long, lat, cluster_dists.zoom, importance_metric
-- finally order by mindist and importance_metric since we prefer them as high as possible
ORDER BY min_dist DESC, importance_metric DESC
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

            SELECT id, name, ele, lat,long,
            ST_AsMVTGeom(
                ST_Transform(distance_peaks.geom, 3857),
                ST_TileEnvelope(z,x,y),
                4096, 0, true
            ) as geom
            FROM distance_peaks
            WHERE zoom = z AND ST_TRANSFORM(distance_peaks.geom,4674) && ST_Transform(ST_TileEnvelope(z,x,y), 4674)
            LIMIT 4
        ) as tile;
    ELSE
    -- all peaks visible
        SELECT INTO mvt ST_AsMVT(tile, 'Peak', 4096, 'geom', 'id') FROM (
            SELECT id, name, ele, lat,long,
            ST_AsMVTGeom(
                ST_Transform(peaks.geom, 3857),
                ST_TileEnvelope(z,x,y),
                4096, 0, true
            ) as geom
            FROM peaks
            WHERE ST_TRANSFORM(peaks.geom,4674) && ST_Transform(ST_TileEnvelope(z,x,y), 4674)
        ) as tile;

    END IF;


  RETURN mvt;
END
$$ LANGUAGE plpgsql IMMUTABLE STRICT PARALLEL SAFE;