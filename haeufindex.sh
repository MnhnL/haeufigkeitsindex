#!/bin/sh

die () {
    echo >&2 "$@"
    exit 1
}

[ "$#" -eq 5 ] || die "5 argument required: [input.csv] [output.csv] [cell_size] [roi_shape_file_without_ending] [species_group=family|order|class|phylum|kingdom], $# provided"

# Load csv file into loaded.sqlite
DB=/tmp/loaded.sqlite
[ -e $DB ] && rm $DB
sqlite3 -batch $DB <<EOF
.header on
.mode csv
select '-- Import csv';
.import $1 obs
.quit
EOF

sed haeufindex.sql -e "s|{{OUTPUT_FILE}}|$2|" -e "s|{{CELL_SIZE}}|$3|" -e "s|{{ROI}}|$4|" -e "s|{{SPECIES_GROUP}}|$5|" | spatialite -batch $DB
