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
          makepoint(5.674, 49.442, 4326), -- Luxembourg bounding box
          makepoint(6.56, 50.225, 4326)
        )
      ),
      2169
    ),
    {{CELL_SIZE}}
  );

-- extract multipolygon into singe polygons
.elemgeo cells_multi geom cells pk old_id

-- this also creates table roi
.loadshp {{ROI}} roi utf-8

-- only keep cells intersecting with ROI
create table cells_in_roi (pk integer primary key);
select AddGeometryColumn('cells_in_roi', 'geom', 2169, 'POLYGON', 'XY');

insert into cells_in_roi
select c.pk, c.geom as geom from cells as c, roi
 where intersects(c.geom, roi.geometry);

select CreateMbrCache('cells_in_roi', 'geom');

-- Create normalized observation table (obs has cellid if it's contained in said cell)
select '-- Creat obs_norm';
create table obs_norm (obs_key text,
                       taxon_kingdom text, taxon_phylum text, taxon_class text,
                       taxon_order text, taxon_family text, taxon_genus text,
                       taxon text,
                       determiner text, cellid integer);

-- Naively localize observation in cell
-- insert into obs_norm
-- select o.Observation_Key as obs_key, o.preferred as taxon, Determiner as determiner, c.pk as cellid
-- from obs as o
-- inner join cells_in_roi as c
--     on within(o.geom, c.geom);

-- Localize observation in cell using in-memory MBR/BoundingBox cache
insert into obs_norm
select o.Observation_Key as obs_key,
       o.Taxon_Kingdom as taxon_kingdom,o.Taxon_Phylum as taxon_phylum,
       o.Taxon_Class as taxon_class, o.Taxon_Order as taxon_order,
       o.Taxon_Family as taxon_family, o.Taxon_Genus as taxon_genus,
       o.preferred as taxon, Determiner as determiner, c.pk as cellid
  from obs as o
       inner join cells_in_roi as c
           on within(o.geom, c.geom)
           and c.rowid in (
             select rowid from cache_cells_in_roi_geom
              where mbr = FilterMbrContains(x(o.geom), y(o.geom), x(o.geom), y(o.geom))
           )
 where taxon <> ''; -- don't take into account observations w/o taxon


-- Species-Group count table: Allows different reference counts for different taxa
create table species_group_count (name text, count integer);

insert into species_group_count
select taxon_{{SPECIES_GROUP}}, count(*)
  from obs_norm
 group by taxon_{{SPECIES_GROUP}};

-- Calculate AAI = Art/Artklassenintensität
select '-- Calculate AAI';
create table aai (intensity real, taxon text, sample_count integer);

insert into aai
select (cast(count(cellid) as real) / sgc.count)*100 as aai,
       taxon,
       count(*) as sample_count
  from obs_norm
       inner join species_group_count as sgc
                    on obs_norm.taxon_{{SPECIES_GROUP}} = sgc.name
 group by taxon
 order by aai;

-- Calculate AGI = Art/Gebiet-Intensität
select '-- Calculate AGI';
create table agi (intensity real, taxon text);

insert into agi
select (cast(count(cellid) as real) / sgc.count)*100 as agi,
       taxon
  from (
    select count(cellid), cellid, taxon_kingdom, taxon_phylum, taxon_class, taxon_order, taxon_family, taxon
      from obs_norm
     group by taxon, cellid
  ) as obs
       inner join species_group_count as sgc
           on obs.taxon_{{SPECIES_GROUP}} = sgc.name
 group by taxon
 order by agi;

-- Calculate AMI = Art/Melder-Intensität
select '-- Calculate AMI';
create table ami (intensity real, taxon text);

insert into ami
select (cast(count(determiner) as real) / sgc.count)*100 as ami,
       taxon
  from (
    select count(determiner), determiner, taxon_kingdom, taxon_phylum, taxon_class, taxon_order, taxon_family, taxon
      from obs_norm
     group by taxon, determiner
  ) as obs
       inner join species_group_count as sgc
           on obs.taxon_{{SPECIES_GROUP}} = sgc.name
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
create table mai (taxon text, aai real, agi real, ami real, mai real, sample_count integer);

insert into mai
select aai.taxon as taxon,
       aai.intensity as aai, agi.intensity as agi, ami.intensity as ami,
       aai.intensity + agi.intensity + ami.intensity as mai,
       aai.sample_count
  from aai
       inner join agi on aai.taxon = agi.taxon
       inner join ami on aai.taxon = ami.taxon
 where aai.sample_count >= 1000
 order by mai;

select '-- Output';
.header on
.mode csv
.output {{OUTPUT_FILE}}
  -- select * from mai;
  select mai.taxon, mai.aai, mai.agi, mai.ami, mai.mai, mi.interpretation, mai.sample_count
  from mai
  inner join mai_interpretation as mi
  on mai.mai >= mi.mai_low
  and mai.mai < mi.mai_high;
.quit
