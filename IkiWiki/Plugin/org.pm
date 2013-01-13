#!/usr/bin/perl
# Emacs org-mode markup language.
package IkiWiki::Plugin::org;

use warnings;
use strict;
use utf8;
use File::Temp;
use IkiWiki 3.00;

sub import {
	hook(type => "getsetup", id => "org", call => \&getsetup);
	hook(type => "checkconfig", id => "org", call => \&checkconfig);
	hook(type => "htmlize", id => "org", call => \&htmlize);
}

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => 1, # format plugin
			section => "format",
		},
		emacs_path => {
			type => "string",
			example => 0,
			description => "path to an external emacs binary",
			safe => 0,
			rebuild => undef,
		},
		emacs_org_options => {
			type => "string",
			example => 0,
			description => "emacs options to convert org-mode to html.  The string 'FILE' will be replaced with the input filename.",
			safe => 0,
			rebuild => undef,
		},
}

sub checkconfig () {
	if (! defined $config{emacs_path}) {
		$config{emacs_path}="/usr/bin/emacs";
	}
	debug("Emacs: $config{emacs_path}");
	if (! defined $config{emacs_org_options}) {
		# See http://orgmode.org/org.html#Publishing-options
		$config{emacs_org_options}='--batch '.
			#q{--eval '(setq load-path (cons "~/share/emacs/site-lisp" load-path))' }.
			'--load org '. # $HOME/share/emacs/site-lisp/org.el
			q{--eval "(setq org-export-author-info 'nil)" }.
			q{--eval "(setq org-export-headline-levels 3)" }.
			q{--eval "(setq org-export-html-preamble 'nil)" }.
			q{--eval "(setq org-export-html-postamble 'nil)" }.
			q{--eval "(setq org-export-with-toc 'nil)" }.
			q{--eval "(setq org-export-skip-text-before-1st-heading t)" }.
			"--visit FILE ".
			'--funcall org-mode '.
			#q{--eval "(org-export-as-html-to-buffer 'nil)" }. # does not expose body-only option
			'--funcall mark-whole-buffer '.
			'--funcall org-replace-region-by-html '.
			q{--eval '(set-visited-file-name "/dev/stdout")' }.
			'--funcall save-buffer ';
	}
}

my $tempdir;
sub htmlize (@) {
	my $args = "$config{emacs_path} $config{emacs_org_options}";
	my %params = @_;
	my $fh;
	my $filename;

	if (! defined $tempdir) {
	    $tempdir = File::Temp::tempdir( CLEANUP => 1 );
	}
	($fh, $filename) = File::Temp::tempfile( DIR => $tempdir, SUFFIX => '.org' );
	binmode ($fh, ':utf8');
	print $fh "$params{content}\n";
	close($fh);

	$args =~ s/FILE/$filename/g;
	#$args =~ s/FILE/posts\/Git\/notes.org/g;
	debug("Executing: $args");
	my $content = `$args`;
	utf8::decode($content);
	return $content;
}

1
