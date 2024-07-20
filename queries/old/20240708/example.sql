-- SELECT id, name, ele, lat,long,
-- ST_AsMVTGeom(
--     ST_Transform(geom, 3857),
--     ST_TileEnvelope(15,17539,11515),
--     4096, 0, true
-- ) as geom
-- FROM peaks
-- WHERE ST_TRANSFORM(peaks.geom,4674) && ST_Transform(ST_TileEnvelope(15,17539,11515), 4674)
-- ;


-- SELECT peak_tile3(15,17539,11515);


SELECT planet_osm_line.osm_id, planet_osm_line.name, planet_osm_line.tags
FROM planet_osm_line
WHERE planet_osm_line.name='Hohe Tauern' and osm_id = -2129656;


