
-- cluster_dists table is used to uniformly define the minimum dists between two POIs when looking at one zoom level
DROP TABLE IF EXISTS cluster_dists;

CREATE TABLE cluster_dists AS
WITH RECURSIVE cd (zoom,dist) as (
    SELECT -- start values
        25 as zoom, 
        0.3981095217168331 as dist -- dist was calculated as 1/3 of the tile width of a tile with zoom 25

    UNION ALL

    SELECT zoom-1, dist*2 -- what to do at each iteration
    FROM cd
    WHERE zoom > 5 -- end value
)
SELECT * FROM cd;

-- SELECT * FROM cluster_dists;
