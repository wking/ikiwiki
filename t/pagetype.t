#!/usr/bin/perl
use warnings;
use strict;
use Test::More tests => 3;
use Test::Exception;

BEGIN { use_ok("IkiWiki"); }

%config=IkiWiki::defaultconfig();
$config{srcdir}=$config{destdir}="/dev/null";
IkiWiki::loadplugins();
IkiWiki::checkconfig();

dies_ok(sub { pagetype("") }, "missing file") or diag(pagetype(""));
is(pagetype("t/test1.mdwn"), "mdwn", "markdown file");

