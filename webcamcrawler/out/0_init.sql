CREATE TABLE IF NOT EXISTS "external_webcams" (

  "id"  bigserial PRIMARY KEY,
  "name" text,
  "lat" real,
  "long" real,
  "url" text
);

ALTER SEQUENCE external_webcams_id_seq RESTART WITH 1000000000000; -- big value that is much bigger than any currently existing osm id



