#!/usr/bin/perl
# Markdown markup language
package IkiWiki::Plugin::mdwn;

use warnings;
use strict;
use IkiWiki 3.00;

sub import {
	hook(type => "getsetup", id => "mdwn", call => \&getsetup);
	hook(type => "htmlize", id => "mdwn", call => \&htmlize, longname => "Markdown");
}

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => 1, # format plugin
			section => "format",
		},
		multimarkdown => {
			type => "boolean",
			example => 0,
			description => "enable multimarkdown features?",
			safe => 1,
			rebuild => 1,
		},
		markdown_path => {
			type => "string",
			example => 0, # /usr/bin/markdown
			description => "path to an external markdown binary",
			safe => 0,
			rebuild => undef,
		},
}

my $markdown_sub;
my $tempdir;
sub htmlize (@) {
	my %params=@_;
	my $content = $params{content};

	if (! defined $markdown_sub) {
		# Markdown is forked and splintered upstream and can be
		# available in a variety of forms. Support them all.
		no warnings 'once';
		$blosxom::version="is a proper perl module too much to ask?";
		use warnings 'all';
	
		if ($config{markdown_path}) {
                        eval q{use File::Temp};
                        if ($@) {
                                debug(gettext("markdown_path is set, but File::Temp is not installed"));
                        }
			else {
				debug("Markdown: $config{markdown_path}");
				$tempdir=File::Temp::tempdir( CLEANUP => 1 );
				$markdown_sub=sub {
					my $content=shift;
					my $fh;
					my $filename;
					($fh, $filename) = File::Temp::tempfile( DIR => $tempdir );
					print $fh "$content\n";
					close($fh);
					$content = `$config{markdown_path} $filename`;
					return $content;
				}
			}
		} elsif (exists $config{multimarkdown} && $config{multimarkdown}) {
			eval q{use Text::MultiMarkdown};
			if ($@) {
				debug(gettext("multimarkdown is enabled, but Text::MultiMarkdown is not installed"));
			}
			else {
				debug("Markdown: Text::MultiMarkdown::markdown()");
				$markdown_sub=sub {
					Text::MultiMarkdown::markdown(shift, {use_metadata => 0});
				}
			}
		}
		if (! defined $markdown_sub) {
			eval q{use Text::Markdown};
			if (! $@) {
				if (Text::Markdown->can('markdown')) {
					debug("Markdown: Text::Markdown::markdown()");
					$markdown_sub=\&Text::Markdown::markdown;
				}
				else {
					debug("Markdown: Text::Markdown::Markdown()");
					$markdown_sub=\&Text::Markdown::Markdown;
				}
			}
			else {
				eval q{use Markdown};
				if (! $@) {
					debug("Markdown: Markdown::Markdown()");
					$markdown_sub=\&Markdown::Markdown;
				}
				else {
					error("failed to load Markdown.pm perl module or $config{markdown_path}");
				}
			}
		}
		
		require Encode;
	}
	
	# Workaround for perl bug (#376329)
	$content=Encode::encode_utf8($content);
	eval {$content=&$markdown_sub($content)};
	if ($@) {
		eval {$content=&$markdown_sub($content)};
		print STDERR $@ if $@;
	}
	$content=Encode::decode_utf8($content);

	return $content;
}

1
