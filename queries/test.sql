
-- SELECT osm_id as id,
--     planet_osm_point.name,
--     ST_X(ST_TRANSFORM(planet_osm_point.way,4674)) AS long,
--     ST_Y(ST_TRANSFORM(planet_osm_point.way,4674)) AS lat,
--     planet_osm_point.way as geom,

--     -- importance metric is elevation
--     -- note for elevation: there are some data errors in osm -> we need to clean them up a bit
--         -- ->substring resolves issues where meter is specified (e.g. "602 m")
--         -- ->decimal cast and flooring resolves issues where number was in decimal (e.g. "1060.0")
--         -- TODO what if instead of metres it is declared in feet -> would result in complete different values...

--     FLOOR(nullif(substring(ele FROM '[0-9]+'), '')::decimal)::int as importance_metric,

-- 	hstore_to_matrix ( -- output {{key1,value1},{key2,value2},...}
-- 		slice( -- only extracts attributes defined by array
-- 			-- add ele to data field
-- 			planet_osm_point.tags || hstore('ele', FLOOR(nullif(substring(ele FROM '[0-9]+'), '')::decimal)::int::text)
-- 			|| hstore('ele2', 'asdf{}eee[]33dd,ees"'::text)
--       || hstore('ele3', 'eerr'::text),
-- 			ARRAY[
-- 				'name:de',
-- 				'wikipedia',
-- 				'wikidata',
-- 				'importance',
-- 				'prominence',
-- 				'summit:cross',
-- 				'summit:register',
-- 				'ele',
--         'ele3',
-- 				'ele2'
-- 			]
-- 		)
-- 	)::TEXT  as data

--    FROM planet_osm_point
--   WHERE planet_osm_point."natural" = 'peak'::text AND name IS NOT NULL AND ele IS NOT NULL
--   ORDER BY importance_metric desc
--   LIMIT 25;

select * from distance_peaks WHERE name = 'Kleinglockner';
-- select * from peaks WHERE name = 'Großglockner';
  
  -- SELECT osm_id as id,
  --       planet_osm_point.name,
  --       ST_X(ST_TRANSFORM(planet_osm_point.way,4674)) AS long,
  --       ST_Y(ST_TRANSFORM(planet_osm_point.way,4674)) AS lat,
  --       planet_osm_point.way as geom,

  --       -- set population as importance_metric
  --       COALESCE(substring(planet_osm_point.population FROM '[0-9]+')::int, 0) as importance_metric,

  --       hstore_to_matrix ( -- output {{key1,value1},{key2,value2},...}
  --           slice( -- only extracts attributes defined by array
  --               -- planet_osm_point.tags,
  --               planet_osm_point.tags 
  --                   || hstore('population', COALESCE(substring(planet_osm_point.population FROM '[0-9]+')::int, 0)::text)
  --                   || hstore('place',  planet_osm_point.place),
  --               ARRAY[
  --                   'name:de',
  --                   'wikipedia',
  --                   'wikidata',
  --                   'population',
  --                   'place'
  --               ]
  --           )
  --       )::TEXT  as data

  --   FROM planet_osm_point
  --   WHERE (
  --       planet_osm_point."place" = 'city'::text 
  --       or planet_osm_point."place" = 'town'::text
  --       or planet_osm_point."place" = 'village'::text
  --       or planet_osm_point."place" = 'hamlet'::text
  --   ) AND name IS NOT NULL
  --   ORDER BY importance_metric desc;




--   SELECT * from distance_peaks ORDER BY importance_metric ASC LIMIT 5;
-- ;
