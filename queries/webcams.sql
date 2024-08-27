-- TU WIEN
-- planet_osm_point.ele
-- planet_osm_point.tags->'ele'

-- drop everything we dont need
DROP FUNCTION IF EXISTS metahelper_webcams;
DROP FUNCTION IF EXISTS webcams_tile;
DROP INDEX distance_webcams_geom_idx;
DROP INDEX webcams_geom_idx;
DROP INDEX webcams_importance_metric_idx;
DROP MATERIALIZED VIEW IF EXISTS distance_webcams;
DROP MATERIALIZED VIEW IF EXISTS webcams_temp;

-- temp view for webcams
CREATE MATERIALIZED VIEW webcams_temp AS
    -- combines osm data with external webcam data table
    -- note external table has same fields and ids are far bigger than current osm id max
    SELECT * FROM (
    (
        -- general attributes (all features should have them)
        SELECT osm_id as id,
            COALESCE(planet_osm_point.tags->'name:de', planet_osm_point.name, '') as name,
            ST_X(ST_TRANSFORM(planet_osm_point.way,4674)) AS long,
            ST_Y(ST_TRANSFORM(planet_osm_point.way,4674)) AS lat,
            planet_osm_point.way as geom,

            COALESCE(FLOOR(nullif(substring(planet_osm_point.ele FROM '[0-9]+'), '')::decimal)::int,0) as importance_metric,
            
            slice( -- only extracts attributes defined by array
                planet_osm_point.tags 
                  || hstore('contact:webcam',  COALESCE(planet_osm_point.tags->'contact:webcam', planet_osm_point.tags->'image', planet_osm_point.tags->'contact:website')::text)
                  || hstore('ele', COALESCE(FLOOR(nullif(substring(planet_osm_point.ele FROM '[0-9]+'), '')::decimal)::int,0)::text),
                ARRAY[
                   'camera:type',
                   'camera:direction',
                   'surveillance:type',
                   'surveillance:zone',
                   'contact:webcam', -- the actual image
                   'description',
                   'ele'
                ]
            ) as data

        FROM planet_osm_point
        WHERE planet_osm_point."man_made" = 'surveillance'::text
        -- NOTE: we are currently only using webcams from the following websites
        -- other webcams were either not available, traffic cameras, duplicates from the external source, or not fitting for the application
        -- if you ever want to add other webcams you can use the following sql command to see what other webcam services are available
        -- split_part(data->'contact:webcam', '/', 3)
        AND planet_osm_point.tags->'contact:webcam' LIKE ANY (ARRAY[
            '%foto-webcam.eu%',
            '%terra-hd.de%',
            '%livecam-hd.eu%',
            '%landgasthof-adler.at%',
            '%entners.at%',
            '%bergoase.at%',
            '%arlberghaus.com%',
            '%webcam.nl%',
            '%linz.it-wms.com%',
            '%irrseewebcam.sein.at%',
            '%wurzacher.eu%',
            '%vorarlberg-cam.at%',
            '%webcams-thalgau.at%',
            '%unternehmen.ortswaerme.info%',
            '%poestlingberg.it-wms.com%'
        ])

        -- useful queries if you ever decide to expand the webcam sites
        -- AND planet_osm_point.tags->'surveillance' in ('public', 'webcam', 'outdoor')
        -- AND (
        --   planet_osm_point.tags->'surveillance:zone' IN ('area', 'public')
        --   or not planet_osm_point.tags ? 'surveillance:zone' -- case that zone is not defined
        -- )
        
    )
    UNION
    (
        SELECT id, name,long,lat,
        ST_Transform(ST_SetSRID(ST_MakePoint(long, lat),4326), 3857) as geom,

        1500 as importance_metric, -- we have no valid way to calculate the metric here

        hstore('contact:webcam', url) as data
        
        FROM external_webcams
    )) a
    ORDER BY importance_metric desc
;


CREATE INDEX webcams_geom_idx
  ON webcams_temp
  USING GIST (geom);

CREATE INDEX webcams_importance_metric_idx
  ON webcams_temp(importance_metric);  -- automatcially uses b-tree


-- we want to prioritize POIs with the higher distances to other POIs where the importance_metric is higher than itself.
-- e.g. Kleinglockner is near Großglockner (small distance -> will only be shown very late although it has a high altitude)
-- the following materialized view calculates those distances to each POI within a certain radius (search radius defined in cluster_dist as 1/3 of tile width and zoom level 8)
-- the select calculates the min_dist to better POI (saved as importance which is the normalized distance [0,1] interval)
CREATE MATERIALIZED VIEW distance_webcams AS
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
    -- this way it will always be here if no better webcams have been found in the radius
    min(
    (CASE 
        WHEN a.id = b.id
        THEN 1.0
        ELSE LEAST(ST_Distance(a.geom, b.geom)::real / cd.dist::real, 1.0)::real
    END)) as importance -- =normalized min_dist
FROM cd CROSS JOIN webcams_temp a LEFT JOIN webcams_temp b ON (ST_DWithin(a.geom, b.geom, cd.dist) and b.importance_metric >= a.importance_metric)
GROUP BY a.id, a.name, a.data, a.geom, a.long, a.lat, a.importance_metric
ORDER BY importance DESC, importance_metric DESC
;



-- create index for faster geom lookups
CREATE INDEX distance_webcams_geom_idx
  ON distance_webcams
  USING GIST (geom);





CREATE OR REPLACE
    FUNCTION webcams_tile(z integer, x integer, y integer)
    RETURNS bytea AS $$
DECLARE
    mvt bytea;
BEGIN
    IF (z < 22) THEN
        -- only POIs with highest importance metric in vicinity visible
        SELECT INTO mvt ST_AsMVT(tile, 'webcams', 4096, 'geom', 'id') FROM (

            SELECT id, name, lat,long,importance,importance_metric,
            ST_AsMVTGeom(
                ST_Transform(distance_webcams.geom, 3857),
                ST_TileEnvelope(z,x,y),
                4096, 0, true
            ) as geom,

            data->'camera:type' as camera_type,
            (data->'camera:direction')::int as direction,
            data->'surveillance:type' as surveillance_type,
            data->'surveillance:zone' as surveillance_zone,
            data->'contact:webcam' as image,
            data->'description' as description,
            (data->'ele')::int as ele

            FROM distance_webcams
            WHERE ST_TRANSFORM(distance_webcams.geom,4674) && ST_Transform(ST_TileEnvelope(z,x,y), 4674)
            LIMIT 4
        ) as tile;
    ELSE
    -- all POIs visible
        SELECT INTO mvt ST_AsMVT(tile, 'webcams', 4096, 'geom', 'id') FROM (

            SELECT id, name, lat,long,importance,importance_metric,
            ST_AsMVTGeom(
                ST_Transform(distance_webcams.geom, 3857),
                ST_TileEnvelope(z,x,y),
                4096, 0, true
            ) as geom,

            data->'camera:type' as camera_type,
            (data->'camera:direction')::int as direction,
            data->'surveillance:type' as surveillance_type,
            data->'surveillance:zone' as surveillance_zone,
            data->'contact:webcam' as image,
            data->'description' as description,
            (data->'ele')::int as ele

            FROM distance_webcams
            WHERE ST_TRANSFORM(distance_webcams.geom,4674) && ST_Transform(ST_TileEnvelope(z,x,y), 4674)
        ) as tile;
        
    END IF;

  RETURN mvt;
END
$$ LANGUAGE plpgsql IMMUTABLE STRICT PARALLEL SAFE;



------------------------
-- Helper function to understand the data encapsulated by the underlying table better
------------------------

CREATE OR REPLACE
    FUNCTION metahelper_webcams(min_amount_with_key integer, max_values_per_key integer) 
  returns table(keys text, entries_with_values integer, distinct_value_amount integer, value text[]) 
as $$

  WITH source as (
    SELECT planet_osm_point.tags as tags
    FROM planet_osm_point
    WHERE planet_osm_point."man_made" = 'surveillance'::text
        AND planet_osm_point.tags->'contact:webcam' LIKE ANY (ARRAY[
            '%foto-webcam.eu%',
            '%terra-hd.de%',
            '%livecam-hd.eu%',
            '%landgasthof-adler.at%',
            '%entners.at%',
            '%bergoase.at%',
            '%arlberghaus.com%',
            '%webcam.nl%',
            '%linz.it-wms.com%',
            '%irrseewebcam.sein.at%',
            '%wurzacher.eu%',
            '%vorarlberg-cam.at%',
            '%webcams-thalgau.at%',
            '%unternehmen.ortswaerme.info%',
            '%poestlingberg.it-wms.com%'
        ])
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
-- SELECT * from metahelper_webcams(10,10)
-- ORDER BY entries_with_values DESC;

