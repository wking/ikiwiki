#!/usr/bin/perl
# File: org.pm
# Time-stamp: <2008-06-08 23:12:20 srivasta>
#
# Copyright (C) 2008 by Manoj Srivastava
#
# Author: Manoj Srivastava
#
# Description:
# This allows people to write Ikiwiki content using Emacs and org-mode
# (requires Emacs 23), and uses the html export facility of org-mode to
# create the output. Some bits based on otl.pm.
# Here is the code: org.pm

package IkiWiki::Plugin::org;
use warnings;
use strict;
use Carp;
use IkiWiki 2.00;

use File::Temp qw/ tempfile tempdir /;

# ------------------------------------------------------------

sub import {
  hook(type => "htmlize", id => "org", call => \&htmlize);
} #

sub htmlize (@) {
  my %params  = @_;
  my $dir     = File::Temp->newdir();



  my $ret = open(INPUT, ">$dir/contents.org");
  unless (defined $ret) {
    debug("failed to open $dir/contents.org: $@");
    return $params{content};
  }
  
  print INPUT $params{content};
  close INPUT;
  my $args = '/usr/local/bin/emacs --batch -l org ' .
              "--eval '(setq org-export-headline-levels 3 org-export-with-toc nil org-export-author-info nil )' " .
              "--visit=$dir/contents.org " .
              '--funcall org-export-as-html-batch >/dev/null 2>&1';
  if (system($args)) {
    debug("failed to convert $params{page}: $@");
    return $params{content};
  }
  $ret = open(OUTPUT, "$dir/contents.html");
  unless (defined $ret) {
    debug("failed find html output for $params{page}: $@");
    return $params{content};
  }
  local $/ = undef;
  $ret = <OUTPUT>;
  close OUTPUT;
  $ret=~s/(.*<h1 class="title">){1}?//s;
  $ret=~s/^(.*<\/h1>){1}?//s;
  $ret=~s/<div id="postamble">.*//s;
  $ret=~s/(<\/div>\s*$)//s;
  
  return $ret;
}

# ------------------------------------------------------------
1; # modules have to return a true value
