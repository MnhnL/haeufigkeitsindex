-- NOTE: Run these two commands in sqlite3 since spatialite does not properly
-- import the csv. Open the prepared database with spatialite aftwerwards for
-- the .elemgeo macro to work.
-----------------------------------------------------------------------------
-- .header on
-- .mode csv
-- .import observations.csv obs
-----------------------------------------------------------------------------

.timer on

--.load mod_spatialite
select InitSpatialMetaData(1); -- param 1 makes it fast

select '-- Prepare obs table';

-- Add columns for lux gauss position
select AddGeometryColumn('obs', 'geom', 2169, 'POINT', 'XY'); -- Lux Gauss

-- Update table with observation positions as geometry in posn_gps and posn columns
select '-- Read and reproject positions';
update obs set geom = Transform(MakePoint(cast(Long as real), cast(Lat as real), 4326), 2169);
--update obs set geom = Transform(PointFromText(location, 4326), 2169);

--select '-- Create spatial index for observations';
--select CreateSpatialIndex('obs', 'geom');

-- Create a table to store the grid as multipolygon (the only way)
select '-- Create grid';
create table cells_multi (id integer primary key autoincrement);
select AddGeometryColumn('cells_multi', 'geom', 2169, 'MULTIPOLYGON', 'XY');

-- Generate grid
insert into cells_multi (geom)
select
  squaregrid(
    transform(
      envelope(
        makeline(
          makepoint(5.67405195478, 49.4426671413, 4326), -- Luxembourg bounding box
          makepoint(6.24275109216, 50.128051662, 4326)
        )
      ),
      2169
    ),
    CELL_SIZE
  );

-- extract multipolygon into singe polygons
.elemgeo cells_multi geom cells pk old_id

select CreateMbrCache('cells', 'geom'); 

-- Create normalized observation table (obs has cellid if it's contained in said cell)
select '-- Creat obs_norm';
create table obs_norm (obs_key text, taxon text, determiner text, cellid integer);

-- Naively localize observation in cell
-- insert into obs_norm
-- select o.Observation_Key as obs_key, o.preferred as taxon, Determiner as determiner, c.pk as cellid
-- from obs as o
-- inner join cells as c
--     on within(o.geom, c.geom);

-- Localize observation in cell using in-memory MBR/BoundingBox cache
insert into obs_norm
select o.Observation_Key as obs_key, o.preferred as taxon, Determiner as determiner, c.pk as cellid
  from obs as o
       inner join cells as c
           on within(o.geom, c.geom)
           and c.rowid in (
             select rowid from cache_cells_geom
              where mbr = FilterMbrContains(x(o.geom), y(o.geom), x(o.geom), y(o.geom))
           );

-- Calculate AAI = Art/Artklassenintensität
select '-- Calculate AAI';
create table aai (intensity real, taxon text);

insert into aai
select cast(count(obs_key) as real) / sum(count(obs_key)) over () as aai,
       taxon
  from obs_norm
 group by taxon
 order by aai;

-- Calculate AGI = Art/Gebiet-Intensität
select '-- Calculate AGI';
create table agi (intensity real, taxon text);

insert into agi
select cast(count(cellid) as real) / sum(cellid) over () as agi,
       taxon
from (
   select count(cellid), taxon, cellid
   from obs_norm
   group by taxon, cellid
)
group by taxon
order by agi;

-- Calculate AMI = Art/Melder-Intensität
select '-- Calculate AMI';
create table ami (intensity real, taxon text);

insert into ami
select cast(count(determiner) as real) / sum(count(determiner)) over () as ami,
       taxon
  from (
    select count(determiner), determiner, taxon
      from obs_norm
     group by taxon, determiner
  )
 group by taxon
 order by ami;

-- Create interpretation table
select '-- Create interpretation table';
create table mai_interpretation (mai_low real, mai_high real, interpretation text);
insert into mai_interpretation (mai_low, mai_high, interpretation)
values (0.0, 0.5, 'extremely rare'),
       (0.5, 1.0, 'rare'),
       (1.0, 5.0, 'relatively rare'),
       (5.0, 10.0, 'few'),
       (10.0, 20.0, 'moderately frequent'),
       (20.0, 50.0, 'relatively frequent'),
       (50.0, 300.0, 'very frequent');

-- Calculate mAI
select '-- Calculate mai';
create table mai (taxon text, mai real);

insert into mai
select aai.taxon as taxon,
       (aai.intensity + agi.intensity + ami.intensity)*100 as mai
  from aai
       inner join agi on aai.taxon = agi.taxon
       inner join ami on aai.taxon = ami.taxon
 order by mai;

select '-- Output';
.header on
.mode csv
.output OUTPUT_FILE
  -- select * from mai;
  select mai.taxon, mai.mai, mi.interpretation from mai inner join mai_interpretation as mi on mai.mai >= mi.mai_low and mai.mai < mi.mai_high;
.quit
