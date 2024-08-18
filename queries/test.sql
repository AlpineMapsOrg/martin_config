


-- SELECT count(*)

--         FROM external_webcams
-- ;
-- SELECT 
--                 count(*)

--         FROM planet_osm_point
--         WHERE planet_osm_point."man_made" = 'surveillance'::text
--         -- NOTE: we are currently only using foto-webcam.eu 
--         -- if you ever want to add other webcams you can use the following sql command to see what other webcam services are available
--         -- split_part(data->'contact:webcam', '/', 3)
--         AND planet_osm_point.tags->'contact:webcam' LIKE '%foto-webcam.eu%'

--         -- useful queries if you ever decide to expand the webcam sites
--         -- AND planet_osm_point.tags->'surveillance' in ('public', 'webcam', 'outdoor')
--         -- AND (
--         --   planet_osm_point.tags->'surveillance:zone' IN ('area', 'public')
--         --   or not planet_osm_point.tags ? 'surveillance:zone' -- case that zone is not defined
--         -- )
-- ;

-- SELECT
--      id, name
--              -- COALESCE(array_length(avals(planet_osm_point.tags), 1),0) AS importance_metric
--     FROM external_webcams

--     ;

    -- DROP FUNCTION IF EXISTS poi_v1;