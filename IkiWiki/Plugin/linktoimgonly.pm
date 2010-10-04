#!/usr/bin/perl

package IkiWiki::Plugin::linktoimgonly;

use warnings;
use strict;
use IkiWiki 3.00;

sub import {
    hook(type => "preprocess", id => "ltio", call => \&preprocess);
}

sub preprocess {
    my %params = @_;
    return "<a href='" . bestlink($params{"page"}, $params{"img"}) . "'>" . $params{"text"} . "</a>";
}

1
