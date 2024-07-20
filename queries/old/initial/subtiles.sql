-------------------------------------------------
-------------------------------------------------
----------------     VIEWS    -------------------
-------------------------------------------------
-------------------------------------------------

-- view for peaks
DROP VIEW IF EXISTS peaks;
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
;

-------------------------------------------------
-------------------------------------------------
-------------     TILE HELPER    ----------------
-------------------------------------------------
-------------------------------------------------

DROP FUNCTION IF EXISTS peak_tile_helper;

-- NOTE xyz and xyzFilter are separate parameters for the case that you want to only show a certain area while maintaining the correct 2d geom
-- normally they would be the same, but they might differ for showing subtiles
CREATE OR REPLACE FUNCTION peak_tile_helper(z integer, x integer, y integer, zFilter integer, xFilter integer, yFilter integer, extent integer default 4096)
returns table (
    -- NOTE: it is important to use the same order here as in the actual select query...
    id bigint, 
    name text, 
    long double precision, 
    lat double precision, 
    geom geometry,

    ele integer

    ) 

language plpgsql
as 
$$
begin
    return query 
        SELECT 
            peaks.id, peaks.name, peaks.long, peaks.lat,
            -- transform the point into the current vector tile -> x/y points lie within (0,4096)
            -- this is necessary for vector tiles on a flat map like leaflet
            ST_AsMVTGeom(
                ST_Transform(peaks.way, 3857),
                ST_TileEnvelope(z,x,y),
                extent, 0, true
            ) as geom,

            peaks.ele

        FROM peaks
        -- only select points where the current position and current tile bbox overlap
        WHERE ST_TRANSFORM(peaks.way,4674) && ST_Transform(ST_TileEnvelope(zFilter,xFilter,yFilter), 4674)
    ;
end; 
$$;


           


-------------------------------------------------
-------------------------------------------------
----------------     TILES    -------------------
-------------------------------------------------
-------------------------------------------------
-- function for peak tiles
CREATE OR REPLACE
    FUNCTION peak_tile(z integer, x integer, y integer)
    RETURNS bytea AS $$
DECLARE
    mvt bytea;
BEGIN
    IF (z < 14) THEN
    -- highest peaks visible
        SELECT INTO mvt ST_AsMVT(tile, 'Peak', 4096, 'geom', 'id') FROM (

            (
            SELECT *
            FROM peak_tile_helper(z,x,y, z+1,x*2,y*2)
            -- ORDER BY ele DESC 
            LIMIT 1
            ) UNION (
                SELECT *
                FROM peak_tile_helper(z,x,y, z+1,x*2+1,y*2)
                -- ORDER BY ele DESC 
                LIMIT 1
            ) UNION (
                SELECT *
                FROM peak_tile_helper(z,x,y, z+1,x*2,y*2+1)
                -- ORDER BY ele DESC 
                LIMIT 1
            ) UNION (
                SELECT *
                FROM peak_tile_helper(z,x,y, z+1,x*2+1,y*2+1)
                -- ORDER BY ele DESC 
                LIMIT 1
            )

        ) as tile;
    ELSE
    -- all peaks visible
        SELECT INTO mvt ST_AsMVT(tile, 'Peak', 4096, 'geom', 'id') FROM (
            SELECT *
            FROM peak_tile_helper(z,x,y,z,x,y)
        ) as tile;

     END IF;


  RETURN mvt;
END
$$ LANGUAGE plpgsql IMMUTABLE STRICT PARALLEL SAFE;






CREATE OR REPLACE
    FUNCTION peak_tile2(z integer, x integer, y integer)
    RETURNS bytea AS $$
DECLARE
    mvt bytea;
BEGIN
    IF (z < 14) THEN
    -- highest peaks visible
        SELECT INTO mvt ST_AsMVT(tile, 'Peak', 4096, 'geom', 'id') FROM (

            SELECT *
            FROM peak_tile_helper(z,x,y, z,x,y)
            ORDER BY ele DESC 
            LIMIT 4
        ) as tile;
    ELSE
    -- all peaks visible
        SELECT INTO mvt ST_AsMVT(tile, 'Peak', 4096, 'geom', 'id') FROM (
            SELECT *
            FROM peak_tile_helper(z,x,y,z,x,y)
        ) as tile;

     END IF;


  RETURN mvt;
END
$$ LANGUAGE plpgsql IMMUTABLE STRICT PARALLEL SAFE;


-- SELECT planet_osm_point.name, ele, way FROM planet_osm_point WHERE planet_osm_point."natural" = 'peak'::text and planet_osm_point.name = 'Großglockner'::text LIMIT 10;


-- SELECT
--         ST_X(ST_TRANSFORM(way,4674)) AS LONG,
--         ST_Y(ST_TRANSFORM(way,4674)) AS LAT,
--         name,
--         FLOOR(nullif(ele, '')::decimal)::int as ele,

--         -- transform the point into the current vector tile -> x/y points lie within (0,4096)
--         -- this is necessary for vector tiles on a flat map like leaflet
--         ST_AsText(ST_AsMVTGeom(
--             ST_Transform(way, 3857),
--             ST_TileEnvelope(9,274,179),
--             4096, 64, true
--         )) as geom

--     FROM peaks
--     -- only select points where the current position and current bbox overlap
--     WHERE name IS NOT NULL AND ele IS NOT NULL AND ST_TRANSFORM(way,4674) && ST_Transform(ST_TileEnvelope(9,274,179), 4674)
--     ORDER BY ele DESC
--     LIMIT 1;


-- SELECT ST_AsText(test_tile(9,274,179));

-- 4384,2878
-- 4384,2878



-- 28/143654912/94306304
-- 21/1122304/736768
-- 19/280576/184192



SELECT * from peak_tile_helper(9,274,179,9,274,179) ORDER BY ele DESC LIMIT 1;
-- SELECT * from peak_tile(9,274,179) LIMIT 1;


-- SELECT pg_typeof(ST_AsMVTGeom(ST_Transform(peaks.way, 3857),ST_TileEnvelope(9,274,179),4096, 64, true)) as geom from peaks ORDER BY peaks.ele DESC LIMIT 1;





-- CREATE OR REPLACE
--     FUNCTION peak_tile(z integer, x integer, y integer)
--     RETURNS bytea AS $$
-- DECLARE
--     mvt bytea;
-- BEGIN
--     -- NOTE it is possible to add if branches here for better individual configurations
--     SELECT INTO mvt ST_AsMVT(tile, 'peak_tile', 4096, 'geom', 'id') FROM (
--         SELECT
--             id, name, long, lat,
--             ele,
           
--             -- transform the point into the current vector tile -> x/y points lie within (0,4096)
--             -- this is necessary for vector tiles on a flat map like leaflet
--             ST_AsMVTGeom(
--                 ST_Transform(way, 3857),
--                 ST_TileEnvelope(z,x,y),
--                 4096, 64, true
--             ) as geom

--         FROM peaks
--         -- only select points where the current position and current tile bbox overlap
--         WHERE ST_TRANSFORM(way,4674) && ST_Transform(ST_TileEnvelope(z,x,y), 4674)
--         ORDER BY ele DESC
--         -- possible to use z parameter here to to differentiate how much is returned per zoom level
--         LIMIT 1
--     ) as tile;

--   RETURN mvt;
-- END
-- $$ LANGUAGE plpgsql IMMUTABLE STRICT PARALLEL SAFE;