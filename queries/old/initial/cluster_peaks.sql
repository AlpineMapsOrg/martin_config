



----------------------------------------------------------------------------------
----------------------------------------------------------------------------------
------------------------ !!! CLUSTERING DOES NOT WORK !!! ------------------------
--- the distance (eps) of a cluster is the distance to
--- at least one other geometry within the cluster
--- -> it is possible that there is only one cluster for whole austria
--- if eps is large enough
----------------------------------------------------------------------------------
----------------------------------------------------------------------------------

-- -- creates a materialized view that precomputes cluster ids per zoom level
-- -- drop view before recreating
-- DROP MATERIALIZED VIEW clustered_peaks;

-- CREATE MATERIALIZED VIEW clustered_peaks AS
-- WITH cluster_distances as (SELECT * from (VALUES
-- -- values from above helper query
--     -- (5, 17448.0904747757),
--     -- (6, 208724.04523738846),

--     -- (7, 104362.0226186936),
--     -- (8, 52181.0113093468),
--     -- (9, 26090.505654674023),
--     (10, 13045.252827337632)
--     -- (11, 6522.626413668196),
--     -- (12, 3261.313206834098)

--     -- (13, 1630.656603417049),
--     -- (14, 815.3283017079035),
--     -- (15, 407.66415085395175),
--     -- (16, 203.83207542697588),
--     -- (17, 101.91603771348794),
--     -- (18, 50.95801885674397)
--     )as x(zoom, cluster_dist)
-- )--, clusters as (
--     SELECT osm_id as id,
--     name,
--     cluster_distances.zoom,
--     way,
--     ST_X(ST_TRANSFORM(planet_osm_point.way,4674)) AS long,
--     ST_Y(ST_TRANSFORM(planet_osm_point.way,4674)) AS lat,
--     ST_X(planet_osm_point.way) AS long1,
--     ST_Y(planet_osm_point.way) AS lat1,
--     -- ST_ClusterDBSCAN(planet_osm_point.way, cluster_distances.cluster_dist, 1) OVER() AS clst_id,
--     ST_ClusterDBSCAN(planet_osm_point.way, cluster_distances.cluster_dist, 1) OVER() AS clst_id,
--     FLOOR(nullif(trim(trailing 'm' from ele), '')::decimal)::int as ele
--     -- ST_ClusterDBSCAN(planet_osm_point.way, 50, 1) OVER() AS clst_id

--     FROM planet_osm_point, cluster_distances
--     WHERE planet_osm_point."natural" = 'peak'::text AND name IS NOT NULL AND ele IS NOT NULL
--     ORDER BY ele
-- -- )
-- -- SELECT * FROM clusters 

-- ;

-- -- if new data is available -> execute this to refresh the view
-- REFRESH MATERIALIZED VIEW clustered_peaks;

