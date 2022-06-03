#!/bin/sh

die () {
    echo >&2 "$@"
    exit 1
}

[ "$#" -eq 3 ] || die "3 argument required: [input.csv] [output.csv] [cell_size], $# provided"

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

sed haeufindex.sql -e "s/OUTPUT_FILE/$2/" -e "s/CELL_SIZE/$3/" | spatialite -batch $DB
