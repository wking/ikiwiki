#!/usr/bin/perl
#
# itex to MathML plugin for IkiWiki.  Based on the itex MovableType
# plugin by Jacques Distler.

package IkiWiki::Plugin::mdwn_itex;

use warnings;
use strict;
use IkiWiki 3.00;

use File::Temp qw(tempfile);

sub import {
    # register the plugin
    hook(type => "getsetup", id => "mdwn_itex", call => \&getsetup);
    hook(type => "checkconfig", id => "mdwn_itex", call => \&checkconfig);
    hook(type => "preprocess", id => "itex", call => \&preprocess);
    hook(type => "htmlize", id => "mdwn_itex", call => \&htmlize,
	 longname => "Markdown + itex");
}

sub getsetup () {
    # declare plugin options etc. for the setup file
    return
	plugin => {
	    description => "itex to MathML conversion followed by Markdown formatting",
	    safe => 1,
	    rebuild => 1,
	    section => "format",
        },
        itex2mml => {
	    type => "string",
	    example => '/usr/local/bin/itex2MML',
	    description => "path to the itex2MML binary",
	    safe => 0, # path
	    rebuild => 0,
	},
        itex_num_equations => {
	    type => "boolean",
	    example => 1,
	    description => 'autonumber \[..\] equations?',
	    safe => 1,
	    rebuild => 1,
	},
}

sub checkconfig () {
    # setup default settings
    if (! exists $config{itex2mml}) {
	$config{itex2mml} = '/usr/local/bin/itex2MML';
    }
    if (! exists $config{itex_num_equations}) {
	$config{itex_num_equations} = 1;
    }
    if (! exists $config{itex_default}) {
	$config{itex_default} = 0;
    }
}

sub htmlize (@) {
    # convert the page contents to XHTML.
    my %params=@_;

    my $content = $params{content};
    my $page = $params{page};

    $params{content} = itex_filter($content);

    return IkiWiki::Plugin::mdwn::htmlize(%params);
}

sub itex_filter {
    my $content = shift;

    # Remove carriage returns. itex2MML expects Unix-style lines.
    $content =~ s/\r//g;

    # Process equation references
    $content = number_equations($content) if $config{itex_num_equations};

    my ($Reader, $outfile) = tempfile( UNLINK => 1 );
    my ($Writer, $infile) = tempfile( UNLINK => 1 );
    binmode $Writer, ":utf8";
    print $Writer "$content";
    system("$config{itex2mml} < $infile > $outfile");
    my @out = <$Reader>;
    close $Reader;
    close $Writer;
    eval { unlink ($infile, $outfile); };
    return join('', @out);
}

sub number_equations {
    my $body = shift;

    my $prefix = "eq";
    my $cls = "numberedEq";

    my %eqnumber;
    my $eqno=1;

    # add equation numbers to \[...\]
    #  - introduce a wrapper-<div> and a <span> with the equation number
    while ($body =~ s/\\\[(.*?)\\\]/\n\n<div class=\"$cls\"><span>\($eqno\)<\/span>\$\$$1\$\$<\/div>\n\n/s)
      {
          $eqno++;
      }

    # assemble equation labels into a hash
    # - remove the \label{} command, collapse surrounding whitespace
    # - add an ID to the wrapper-<div>. prefix it to give a fighting chance
    #   for the ID to be unique
    # - hash key is the equation label, value is the equation number
    while ($body =~ s/<div class=\"$cls\"><span>\((\d+)\)<\/span>\$\$((?:[^\$]|\\\$)*)\s*\\label{(\w*)}\s*((?:[^\$]|\\\$)*)\$\$<\/div>/<div class=\"$cls\" id=\"$prefix:$3\"><span>\($1\)<\/span>\$\$$2$4\$\$<\/div>/s)
      {
          $eqnumber{"$3"} = $1;
      }

    # add cross-references
    # - they can be either (eq:foo) or \eqref{foo}
    $body =~ s/\(eq:(\w+)\)/\(<a href=\"#$prefix:$1\">$eqnumber{"$1"}<\/a>\)/g;
    $body =~ s/\\eqref\{(\w+)\}/\(<a href=\'#$prefix:$1\'>$eqnumber{"$1"}<\/a>\)/g;

    return $body;
}

1

  __END__

=head1 NAME

ikiwiki Plug-in: mdwn_itex

=head1 SYNOPSIS

Processes embedded itex (LaTeX-based) expressions in pages and converts
them to MathML.  Also provides equation-numbering as described on
Jacques Distler's itex2MML commands page.

=head1 AUTHORS

W. Trevor King <wking@drexel.edu>,
updates to IkiWiki v3.00

Jason Blevins <jrblevin@sdf.lonestar.org>,
itex Blosxom plugin

Jacques Distler <distler@golem.ph.utexas.edu>,
itex2MML and itex2MML Movable Type Plugin

=head1 SEE ALSO

W. Trevor King's blog entry for this plugin:
http://www.physics.drexel.edu/~wking/unfolding-disasters/posts/mdwn_itex/

Jason Blevins' ikiwiki plugin:
http://jblevins.org/git/ikiwiki/plugins.git/plain/mdwn_itex.pm

ikiwiki Homepage:
http://ikiwiki.info/

ikiwiki Plugin Documentation:
http://ikiwiki.info/plugins/write/

itex2MML commands:
http://golem.ph.utexas.edu/~distler/blog/itex2MML.html

=head1 LICENSE

Copyright (C) 2010 W. Trevor King

Copyright (C) 2008 Jason Blevins

Copyright (C) 2003-2007 Jacques Distler

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License along
with this program; if not, write to the Free Software Foundation, Inc.,
51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
