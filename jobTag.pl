#!/usr/bin/env perl
# =======================================================================================
#
#      Author:   Jan Eitzinger (je), jan.eitzinger@fau.de
#      Copyright (c) 2019 RRZE, University Erlangen-Nuremberg
#
#      Permission is hereby granted, free of charge, to any person obtaining a copy
#      of this software and associated documentation files (the "Software"), to deal
#      in the Software without restriction, including without limitation the rights
#      to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
#      copies of the Software, and to permit persons to whom the Software is
#      furnished to do so, subject to the following conditions:
#
#      The above copyright notice and this permission notice shall be included in all
#      copies or substantial portions of the Software.
#
#      THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
#      IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
#      FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
#      AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
#      LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
#      OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
#      SOFTWARE.
#
# =======================================================================================

use strict;
use warnings;
use utf8;

use DBI;

my $database = 'jobDB';

my %attr = (
    PrintError => 1,
    RaiseError => 1
);

my $dbh = DBI->connect(
    "DBI:SQLite:dbname=$database", "", "", \%attr)
    or die "Could not connect to database: $DBI::errstr";

my $sth_query_job = $dbh->prepare(qq{
    SELECT j.*
    FROM jobtag jt, job j, tag t
    WHERE jt.tag_id=t.tag_id
        AND t.name=?
        AND j.id=jt.job_id
    GROUP BY j.id
    });

my $sth_select_job = $dbh->prepare(qq{
    SELECT id
    FROM job
    WHERE job_id=?
    });

my $sth_select_tag = $dbh->prepare(qq{
    SELECT id
    FROM tag
    WHERE name=?
    });

my $sth_insert_tag = $dbh->prepare(qq{
    INSERT INTO tag(type,name)
    VALUES(?,?)
    });

my $sth_job_add_tag = $dbh->prepare(qq{
    INSERT INTO jobtag(job_id,tag_id)
    VALUES(?,?)
    });

my $CMD = $ARGV[0];

if ( $CMD eq 'ADD' ) {
    # body...
}
elsif ( $CMD eq 'RM' ) {
    # elsif...
}
elsif ( $CMD eq 'LS' ) {
    # elsif...
}
else {
    # else...
}
