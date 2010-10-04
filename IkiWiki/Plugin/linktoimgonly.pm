#!/usr/bin/perl

package IkiWiki::Plugin::linktoimgonly;

use warnings;
use strict;
use IkiWiki 3.00;

sub import {
    hook(type => "preprocess", id => "ltio", call => \&preprocess);
}

sub preprocess {
    my ($image) = $_[0] =~ /$config{wiki_file_regexp}/; # untaint
    my %params=@_;

    if (! defined $image) {
	error("bad image filename");
    }

    return htmllink($params{page}, $params{destpage}, $image,
		    linktext => $params{text},
		    noimageinline => 1);
}

1
