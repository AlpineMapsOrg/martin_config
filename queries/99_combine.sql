-- combines multiple tiles into one

DROP FUNCTION IF EXISTS poi_v1;

CREATE OR REPLACE
    FUNCTION poi_v1(z integer, x integer, y integer)
    RETURNS bytea AS $$
BEGIN
-- here all the individual tiles are concetanated for the final output
-- although you can define indidivual properties in the config.yaml file
-- this is not necessary and all available properties are send in the tile
  RETURN peak_tile(z,x,y) || cities_tile(z,x,y) || cottages_tile(z,x,y) || webcams_tile(z,x,y);

END
$$ LANGUAGE plpgsql IMMUTABLE STRICT PARALLEL SAFE;


