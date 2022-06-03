# Haeufigkeitsindex
Calculates the rarity index as defined in https://mdata.mnhn.lu/include/mai/NuL10-17-325-333-Ott.pdf on the Luxembourgish territory. If you want to use it in other regions, you need to adapt the grid cell generation in haeufindex.sql.

## Dependencies
`apt install sqlite3 spatialite-bin`

## Running
1. Export a csv file from https://mdata.mnhn.lu/ that includes all obeservations of a reference taxon in a reference time.
2. Install dependencies
3. Check out this repository using git
4. Change into git repository
5. Run `sh haeufindex.sh observations.csv output.csv 1000` for an analysis on 1km squares
6. Read the output in the file `output.csv`

Note: If you want to do additional analysis, you can run `spatialite /tmp/loaded.sqlite` after running the analysis. This database contains the following interesting tables:
* obs_norm: observations with reference to cell they are contained in
* aai, agi, ami: The components of mAI
* mai: The results
