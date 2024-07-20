-------------------------------------------------
-------------------------------------------------
----------------     VIEWS    -------------------
-------------------------------------------------
-------------------------------------------------

-- view for peaks
-- DROP VIEW IF EXISTS peaks;
CREATE VIEW peaks AS 
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
    FLOOR(nullif(substring(ele FROM '[0-9]+'), '')::decimal)::int as ele

   FROM planet_osm_point
  WHERE planet_osm_point."natural" = 'peak'::text AND name IS NOT NULL AND ele IS NOT NULL
  ORDER BY ele desc;













-- -- HELPER Query to show the x/y extents of various tiles and calculate cluster_dist
-- WITH 
--     pts as (SELECT * from (VALUES 
--         (5, ST_TileEnvelope(5,17,11)),
--         (6, ST_TileEnvelope(6,34,22)),
--         (7, ST_TileEnvelope(7,68,44)),
--         (8, ST_TileEnvelope(8,137,89)),
--         (9, ST_TileEnvelope(9,274,179)),
--         (10, ST_TileEnvelope(10,548,359)),
--         (11, ST_TileEnvelope(11,1096,719)),
--         (12, ST_TileEnvelope(12,2192,1439)),
--         (13, ST_TileEnvelope(13,4384,2878)),
--         (14, ST_TileEnvelope(14,8769,5757)),
--         (15, ST_TileEnvelope(15,17539,11515)),
--         (16, ST_TileEnvelope(16,35078,23030)),
--         (17, ST_TileEnvelope(17,70157,46061)),
--         (18, ST_TileEnvelope(18,140315,92123)))
--      as p(zoom, geom))
-- SELECT 
--       zoom,
--       -- cluster dist is 1/3 of a tile width/height
--       (ST_XMax(geom)-ST_XMin(geom))/3 as cluster_dist,

--       -- show width and height of each tile
--       -- ST_XMax(geom)-ST_XMin(geom) as w,
--       -- ST_YMax(geom)-ST_YMin(geom) as h
--       from pts
-- ;







DROP INDEX distance_peaks_geom_idx;
DROP INDEX distance_peaks_zoom_idx;

DROP MATERIALIZED VIEW distance_peaks;

CREATE MATERIALIZED VIEW distance_peaks AS
WITH search_distances as (SELECT * from (VALUES
-- values from above helper query
    -- (5, 17448.0904747757),
    -- (6, 208724.04523738846),

    (7, 104362.0226186936),
    (8, 52181.0113093468),
    (9, 26090.505654674023),
    (10, 13045.252827337632),
    (11, 6522.626413668196),
    (12, 3261.313206834098),
    (13, 1630.656603417049)
    -- (14, 815.3283017079035),
    -- (15, 407.66415085395175),
    -- (16, 203.83207542697588),
    -- (17, 101.91603771348794),
    -- (18, 50.95801885674397)
    )as x(zoom, dist)
), all_distances as (
        SELECT a.id,
            a.name,
            a.ele as ele,
            b.ele as ele_dist,
            a.geom,
            sd.zoom,
            a.long,
            a.lat,
            -- this sets the distance to max for itself
            -- this way it will always be here if no taller peaks has been found in radius
            (CASE 
                WHEN a.id = b.id
                THEN sd.dist
                ELSE ST_Distance(a.geom, b.geom)
            END) as dist
        -- FROM search_distances sd, peaks a LEFT JOIN peaks b ON ST_DWithin(a.geom, b.geom, 208724)
        FROM search_distances sd CROSS JOIN peaks a LEFT JOIN peaks b ON ST_DWithin(a.geom, b.geom, sd.dist)
        ORDER BY ele DESC, id ASC, dist ASC

    )
SELECT 
    id, name, ele, geom, long, lat, all_distances.zoom,
    min(all_distances.dist) as mindist 
FROM all_distances
WHERE all_distances.ele <= all_distances.ele_dist
GROUP BY id, name, ele, geom, long, lat, all_distances.zoom
ORDER BY mindist DESC
;

-- create index for faster geom lookups
CREATE INDEX distance_peaks_geom_idx
  ON distance_peaks
  USING GIST (geom);


CREATE INDEX distance_peaks_zoom_idx
  ON distance_peaks
  USING HASH (zoom);






















DROP FUNCTION IF EXISTS peak_tile;

CREATE OR REPLACE
    FUNCTION peak_tile(z integer, x integer, y integer)
    RETURNS bytea AS $$
DECLARE
    mvt bytea;
BEGIN
    IF (z < 10) THEN
        -- do nothing
    ELSIF (z < 22) THEN
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

