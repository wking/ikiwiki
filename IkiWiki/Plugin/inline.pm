#!/usr/bin/perl
# Page inlining and blogging.
package IkiWiki::Plugin::inline;

use warnings;
use strict;
use Encode;
use IkiWiki 3.00;
use URI;

my %knownfeeds;
my %page_numfeeds;
my @inline;
my $nested=0;

sub import {
	hook(type => "getopt", id => "inline", call => \&getopt);
	hook(type => "getsetup", id => "inline", call => \&getsetup);
	hook(type => "checkconfig", id => "inline", call => \&checkconfig);
	hook(type => "sessioncgi", id => "inline", call => \&sessioncgi);
	hook(type => "preprocess", id => "inline",
		call => \&IkiWiki::preprocess_inline);
	hook(type => "pagetemplate", id => "inline",
		call => \&IkiWiki::pagetemplate_inline);
	hook(type => "format", id => "inline", call => \&format, first => 1);
	# Hook to change to do pinging since it's called late.
	# This ensures each page only pings once and prevents slow
	# pings interrupting page builds.
	hook(type => "change", id => "inline", call => \&IkiWiki::pingurl);
}

sub getopt () {
	eval q{use Getopt::Long};
	error($@) if $@;
	Getopt::Long::Configure('pass_through');
	GetOptions(
		"rss!" => \$config{rss},
		"atom!" => \$config{atom},
		"allowrss!" => \$config{allowrss},
		"allowatom!" => \$config{allowatom},
		"pingurl=s" => sub {
			push @{$config{pingurl}}, $_[1];
		},
	);
}

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => undef,
			section => "core",
		},
		rss => {
			type => "boolean",
			example => 0,
			description => "enable rss feeds by default?",
			safe => 1,
			rebuild => 1,
		},
		atom => {
			type => "boolean",
			example => 0,
			description => "enable atom feeds by default?",
			safe => 1,
			rebuild => 1,
		},
		allowrss => {
			type => "boolean",
			example => 0,
			description => "allow rss feeds to be used?",
			safe => 1,
			rebuild => 1,
		},
		allowatom => {
			type => "boolean",
			example => 0,
			description => "allow atom feeds to be used?",
			safe => 1,
			rebuild => 1,
		},
		pingurl => {
			type => "string",
			example => "http://rpc.technorati.com/rpc/ping",
			description => "urls to ping (using XML-RPC) on feed update",
			safe => 1,
			rebuild => 0,
		},
		raw_templates => {
			type => "string",
			example => [qw{raw}],
			description => "templates for which you want raw content",
			safe => 0,
			rebuild => 1,
		},
}

sub checkconfig () {
	if (($config{rss} || $config{atom}) && ! length $config{url}) {
		error(gettext("Must specify url to wiki with --url when using --rss or --atom"));
	}
	if ($config{rss}) {
		push @{$config{wiki_file_prune_regexps}}, qr/\.rss$/;
	}
	if ($config{atom}) {
		push @{$config{wiki_file_prune_regexps}}, qr/\.atom$/;
	}
	if (! exists $config{pingurl}) {
		$config{pingurl}=[];
	}
}

sub format (@) {
	my %params=@_;

	# Fill in the inline content generated earlier. This is actually an
	# optimisation.
	$params{content}=~s{<div class="inline" id="([^"]+)"></div>}{
		delete @inline[$1,]
	}eg;
	return $params{content};
}

sub sessioncgi ($$) {
	my $q=shift;
	my $session=shift;

	if ($q->param('do') eq 'blog') {
		my $page=titlepage(decode_utf8($q->param('title')));
		$page=~s/(\/)/"__".ord($1)."__"/eg; # don't create subdirs
		# if the page already exists, munge it to be unique
		my $from=$q->param('from');
		my $add="";
		while (exists $IkiWiki::pagecase{lc($from."/".$page.$add)}) {
			$add=1 unless length $add;
			$add++;
		}
		$q->param('page', $page.$add);
		# now go create the page
		$q->param('do', 'create');
		# make sure the editpage plugin in loaded
		if (IkiWiki->can("cgi_editpage")) {
			IkiWiki::cgi_editpage($q, $session);
		}
		else {
			error(gettext("page editing not allowed"));
		}
		exit;
	}
}

# Back to ikiwiki namespace for the rest, this code is very much
# internal to ikiwiki even though it's separated into a plugin.
package IkiWiki;

my %toping;
my %feedlinks;

sub preprocess_inline (@) {
	my %params=@_;

	if (! exists $params{pages} && ! exists $params{pagenames}) {
		error gettext("missing pages parameter");
	}
	my $raw=yesno($params{raw});
	my $archive=yesno($params{archive});
	my $rss=(($config{rss} || $config{allowrss}) && exists $params{rss}) ? yesno($params{rss}) : $config{rss};
	my $atom=(($config{atom} || $config{allowatom}) && exists $params{atom}) ? yesno($params{atom}) : $config{atom};
	my $quick=exists $params{quick} ? yesno($params{quick}) : 0;
	my $feeds=! $nested && (exists $params{feeds} ? yesno($params{feeds}) : !$quick && ! $raw);
	my $emptyfeeds=exists $params{emptyfeeds} ? yesno($params{emptyfeeds}) : 1;
	my $feedonly=yesno($params{feedonly});
	if (! exists $params{show} && ! $archive) {
		$params{show}=10;
	}
	if (! exists $params{feedshow} && exists $params{show}) {
		$params{feedshow}=$params{show};
	}
	my $desc;
	if (exists $params{description}) {
		$desc = $params{description}
	}
	else {
		$desc = $config{wikiname};
	}
	my $actions=yesno($params{actions});
	if (exists $params{template}) {
		$params{template}=~s/[^-_a-zA-Z0-9]+//g;
	}
	else {
		$params{template} = $archive ? "archivepage" : "inlinepage";
	}

	my @list;

	if (exists $params{pagenames}) {
		foreach my $p (qw(sort pages)) {
			if (exists $params{$p}) {
				error sprintf(gettext("the %s and %s parameters cannot be used together"),
					"pagenames", $p);
			}
		}

		@list = map { bestlink($params{page}, $_) }
			split ' ', $params{pagenames};

		if (yesno($params{reverse})) {
			@list=reverse(@list);
		}

		foreach my $p (@list) {
			add_depends($params{page}, $p, deptype($quick ? "presence" : "content"));
		}
	}
	else {
		my $num=0;
		if ($params{show}) {
			$num=$params{show};
		}
		if ($params{feedshow} && $num < $params{feedshow} && $num > 0) {
			$num=$params{feedshow};
		}
		if ($params{skip} && $num) {
			$num+=$params{skip};
		}

		@list = pagespec_match_list($params{page}, $params{pages},
			deptype => deptype($quick ? "presence" : "content"),
			filter => sub { $_[0] eq $params{page} },
			sort => exists $params{sort} ? $params{sort} : "age",
			reverse => yesno($params{reverse}),
			($num ? (num => $num) : ()),
		);
	}

	if (exists $params{skip}) {
		@list=@list[$params{skip} .. $#list];
	}

	my @feedlist;
	if ($feeds) {
		if (exists $params{feedshow} &&
		    $params{feedshow} && @list > $params{feedshow}) {
			@feedlist=@list[0..$params{feedshow} - 1];
		}
		else {
			@feedlist=@list;
		}
	}

	if ($params{show} && @list > $params{show}) {
		@list=@list[0..$params{show} - 1];
	}

	if ($feeds && exists $params{feedpages}) {
		@feedlist = pagespec_match_list(
			$params{page}, "($params{pages}) and ($params{feedpages})",
			deptype => deptype($quick ? "presence" : "content"),
			list => \@feedlist,
		);
	}

	my ($feedbase, $feednum);
	if ($feeds) {
		# Ensure that multiple feeds on a page go to unique files.

		# Feedfile can lead to conflicts if usedirs is not enabled,
		# so avoid supporting it in that case.
		delete $params{feedfile} if ! $config{usedirs};
		# Tight limits on legal feedfiles, to avoid security issues
		# and conflicts.
		if (defined $params{feedfile}) {
			if ($params{feedfile} =~ /\// ||
			    $params{feedfile} !~ /$config{wiki_file_regexp}/) {
				error("illegal feedfile");
			}
			$params{feedfile}=possibly_foolish_untaint($params{feedfile});
		}
		$feedbase=targetpage($params{destpage}, "", $params{feedfile});

		my $feedid=join("\0", $feedbase, map { $_."\0".$params{$_} } sort keys %params);
		if (exists $knownfeeds{$feedid}) {
			$feednum=$knownfeeds{$feedid};
		}
		else {
			if (exists $page_numfeeds{$params{destpage}}{$feedbase}) {
				if ($feeds) {
					$feednum=$knownfeeds{$feedid}=++$page_numfeeds{$params{destpage}}{$feedbase};
				}
			}
			else {
				$feednum=$knownfeeds{$feedid}="";
				if ($feeds) {
					$page_numfeeds{$params{destpage}}{$feedbase}=1;
				}
			}
		}
	}

	my $rssurl=abs2rel($feedbase."rss".$feednum, dirname(htmlpage($params{destpage}))) if $feeds && $rss;
	my $atomurl=abs2rel($feedbase."atom".$feednum, dirname(htmlpage($params{destpage}))) if $feeds && $atom;

	my $ret="";

	if (length $config{cgiurl} && ! $params{preview} && (exists $params{rootpage} ||
	    (exists $params{postform} && yesno($params{postform}))) &&
	    IkiWiki->can("cgi_editpage")) {
		# Add a blog post form, with feed buttons.
		my $formtemplate=template_depends("blogpost.tmpl", $params{page}, blind_cache => 1);
		$formtemplate->param(cgiurl => $config{cgiurl});
		$formtemplate->param(rootpage => rootpage(%params));
		$formtemplate->param(rssurl => $rssurl) if $feeds && $rss;
		$formtemplate->param(atomurl => $atomurl) if $feeds && $atom;
		if (exists $params{postformtext}) {
			$formtemplate->param(postformtext =>
				$params{postformtext});
		}
		else {
			$formtemplate->param(postformtext =>
				gettext("Add a new post titled:"));
		}
		$ret.=$formtemplate->output;

		# The post form includes the feed buttons, so
		# emptyfeeds cannot be hidden.
		$emptyfeeds=1;
	}
	elsif ($feeds && !$params{preview} && ($emptyfeeds || @feedlist)) {
		# Add feed buttons.
		my $linktemplate=template_depends("feedlink.tmpl", $params{page}, blind_cache => 1);
		$linktemplate->param(rssurl => $rssurl) if $rss;
		$linktemplate->param(atomurl => $atomurl) if $atom;
		$ret.=$linktemplate->output;
	}

	if (! $feedonly) {
		my $template;
		if (! $raw) {
			# cannot use wiki pages as templates; template not sanitized due to
			# format hook hack
			eval {
				$template=template_depends($params{template}.".tmpl", $params{page},
					blind_cache => 1);
			};
			if ($@) {
				error sprintf(gettext("failed to process template %s"), $params{template}.".tmpl").": $@";
			}
		}
		my $needcontent=$raw || (!($archive && $quick) && $template->query(name => 'content'));

		foreach my $page (@list) {
			my $file = $pagesources{$page};
			my $type = pagetype($file);
			if (! $raw) {
				# is $params{template} in $config{raw_templates}?
				my $read_raw = grep {$_ eq $params{template}} @{$config{raw_templates}};
				if ($needcontent) {
					# Get the content before populating the
					# template, since getting the content uses
					# the same template if inlines are nested.
					my $content=get_inline_content($page, $params{destpage}, $read_raw);
					$template->param(content => $content);
				}
				$template->param(pageurl => urlto($page, $params{destpage}));
				$template->param(inlinepage => $page);
				$template->param(title => pagetitle(basename($page)));
				$template->param(ctime => displaytime($pagectime{$page}, $params{timeformat}, 1));
				$template->param(mtime => displaytime($pagemtime{$page}, $params{timeformat}));
				$template->param(first => 1) if $page eq $list[0];
				$template->param(last => 1) if $page eq $list[$#list];
				$template->param(html5 => $config{html5});

				if ($actions) {
					my $file = $pagesources{$page};
					my $type = pagetype($file);
					if ($config{discussion}) {
						if ($page !~ /.*\/\Q$config{discussionpage}\E$/i &&
						    (length $config{cgiurl} ||
						     exists $pagesources{$page."/".lc($config{discussionpage})})) {
							$template->param(have_actions => 1);
							$template->param(discussionlink =>
								htmllink($page,
									$params{destpage},
									$config{discussionpage},
									noimageinline => 1,
									forcesubpage => 1));
						}
					}
					if (length $config{cgiurl} &&
					    defined $type &&
					    IkiWiki->can("cgi_editpage")) {
						$template->param(have_actions => 1);
						$template->param(editurl => cgiurl(do => "edit", page => $page));

					}
				}

				run_hooks(pagetemplate => sub {
					shift->(page => $page, destpage => $params{destpage},
						template => $template,);
				});

				$ret.=$template->output;
				$template->clear_params;
			}
			else {
				if (defined $type) {
					$ret.="\n".
					      linkify($page, $params{destpage},
					      preprocess($page, $params{destpage},
					      filter($page, $params{destpage},
					      readfile(srcfile($file)))));
				}
				else {
					$ret.="\n".
					      readfile(srcfile($file));
				}
			}
		}
	}

	if ($feeds && ($emptyfeeds || @feedlist)) {
		if ($rss) {
			my $rssp=$feedbase."rss".$feednum;
			will_render($params{destpage}, $rssp);
			if (! $params{preview}) {
				writefile($rssp, $config{destdir},
					genfeed("rss",
						$config{url}."/".$rssp, $desc, $params{guid}, $params{destpage}, @feedlist));
				$toping{$params{destpage}}=1 unless $config{rebuild};
				$feedlinks{$params{destpage}}.=qq{<link rel="alternate" type="application/rss+xml" title="$desc (RSS)" href="$rssurl" />};
			}
		}
		if ($atom) {
			my $atomp=$feedbase."atom".$feednum;
			will_render($params{destpage}, $atomp);
			if (! $params{preview}) {
				writefile($atomp, $config{destdir},
					genfeed("atom", $config{url}."/".$atomp, $desc, $params{guid}, $params{destpage}, @feedlist));
				$toping{$params{destpage}}=1 unless $config{rebuild};
				$feedlinks{$params{destpage}}.=qq{<link rel="alternate" type="application/atom+xml" title="$desc (Atom)" href="$atomurl" />};
			}
		}
	}

	clear_inline_content_cache();

	return $ret if $raw || $nested;
	push @inline, $ret;
	return "<div class=\"inline\" id=\"$#inline\"></div>\n\n";
}

sub pagetemplate_inline (@) {
	my %params=@_;
	my $page=$params{page};
	my $template=$params{template};

	$template->param(feedlinks => $feedlinks{$page})
		if exists $feedlinks{$page} && $template->query(name => "feedlinks");
}

{
my %inline_content;
my $cached_destpage="";

sub get_inline_content ($$$) {
	my $page=shift;
	my $destpage=shift;
	my $read_raw=shift;

	if (exists $inline_content{$page} && $cached_destpage eq $destpage) {
		return $inline_content{$page};
	}

	my $file=$pagesources{$page};
	my $type=pagetype($file);
	my $ret="";
	$nested++;
	if (defined $type) {
		$ret=htmlize($page, $destpage, $type,
		             linkify($page, $destpage,
		             preprocess($page, $destpage,
		             filter($page, $destpage,
		             readfile(srcfile($file))))));
	} elsif ($read_raw) {
		$ret=readfile(srcfile($file));
	}
	$nested--;
	if (isinternal($page)) {
		# make inlined text of internal pages searchable
		run_hooks(indexhtml => sub {
			shift->(page => $page, destpage => $page,
				content => $ret);
			});
	}

	if ($cached_destpage ne $destpage) {
		clear_inline_content_cache();
		$cached_destpage=$destpage;
	}
	return $inline_content{$page}=$ret;
}

sub clear_inline_content_cache () {
	%inline_content=();
}

}

sub date_822 ($) {
	my $time=shift;

	my $lc_time=POSIX::setlocale(&POSIX::LC_TIME);
	POSIX::setlocale(&POSIX::LC_TIME, "C");
	my $ret=POSIX::strftime("%a, %d %b %Y %H:%M:%S %z", localtime($time));
	POSIX::setlocale(&POSIX::LC_TIME, $lc_time);
	return $ret;
}

sub absolute_urls ($$) {
	# sucky sub because rss sucks
	my $content=shift;
	my $baseurl=shift;

	my $url=$baseurl;
	$url=~s/[^\/]+$//;

	# what is the non path part of the url?
	my $top_uri = URI->new($url);
	$top_uri->path_query(""); # reset the path
	my $urltop = $top_uri->as_string;

	$content=~s/(<a(?:\s+(?:class|id)\s*="?\w+"?)?)\s+href=\s*"(#[^"]+)"/$1 href="$baseurl$2"/mig;
	# relative to another wiki page
	$content=~s/(<a(?:\s+(?:class|id)\s*="?\w+"?)?)\s+href=\s*"(?!\w+:)([^\/][^"]*)"/$1 href="$url$2"/mig;
	$content=~s/(<img(?:\s+(?:class|id|width|height)\s*="?\w+"?)*)\s+src=\s*"(?!\w+:)([^\/][^"]*)"/$1 src="$url$2"/mig;
	# relative to the top of the site
	$content=~s/(<a(?:\s+(?:class|id)\s*="?\w+"?)?)\s+href=\s*"(?!\w+:)(\/[^"]*)"/$1 href="$urltop$2"/mig;
	$content=~s/(<img(?:\s+(?:class|id|width|height)\s*="?\w+"?)*)\s+src=\s*"(?!\w+:)(\/[^"]*)"/$1 src="$urltop$2"/mig;
	return $content;
}

sub genfeed ($$$$$@) {
	my $feedtype=shift;
	my $feedurl=shift;
	my $feeddesc=shift;
	my $guid=shift;
	my $page=shift;
	my @pages=@_;

	my $url=URI->new(encode_utf8(urlto($page,"",1)));

	my $template=$feedtype."item";
	my $itemtemplate=template_depends($template.".tmpl", $page, blind_cache => 1);
	my $content="";
	my $lasttime = 0;
	foreach my $p (@pages) {
		my $u=URI->new(encode_utf8(urlto($p, "", 1)));
		# is $params{template} in $config{raw_templates}?
		my $read_raw = grep {$_ eq $template} @{$config{raw_templates}};
		my $pcontent = absolute_urls(get_inline_content($p, $page, $read_raw), $url);

		$itemtemplate->param(
			title => pagetitle(basename($p)),
			url => $u,
			permalink => $u,
			cdate_822 => date_822($pagectime{$p}),
			mdate_822 => date_822($pagemtime{$p}),
			cdate_3339 => date_3339($pagectime{$p}),
			mdate_3339 => date_3339($pagemtime{$p}),
		);

		if (exists $pagestate{$p}) {
			if (exists $pagestate{$p}{meta}{guid}) {
				eval q{use HTML::Entities};
				$itemtemplate->param(guid => HTML::Entities::encode_numeric($pagestate{$p}{meta}{guid}));
			}

			if (exists $pagestate{$p}{meta}{updated}) {
				$itemtemplate->param(mdate_822 => date_822($pagestate{$p}{meta}{updated}));
				$itemtemplate->param(mdate_3339 => date_3339($pagestate{$p}{meta}{updated}));
			}
		}

		if ($itemtemplate->query(name => "enclosure")) {
			my $file=$pagesources{$p};
			my $type=pagetype($file);
			if (defined $type) {
				$itemtemplate->param(content => $pcontent);
			}
			else {
				my $size=(srcfile_stat($file))[8];
				my $mime="unknown";
				eval q{use File::MimeInfo};
				if (! $@) {
					$mime = mimetype($file);
				}
				$itemtemplate->param(
					enclosure => $u,
					type => $mime,
					length => $size,
				);
			}
		}
		else {
			$itemtemplate->param(content => $pcontent);
		}

		run_hooks(pagetemplate => sub {
			shift->(page => $p, destpage => $page,
				template => $itemtemplate);
		});

		$content.=$itemtemplate->output;
		$itemtemplate->clear_params;

		$lasttime = $pagemtime{$p} if $pagemtime{$p} > $lasttime;
	}

	$template=template_depends($feedtype."page.tmpl", $page, blind_cache => 1);
	$template->param(
		title => $page ne "index" ? pagetitle($page) : $config{wikiname},
		wikiname => $config{wikiname},
		pageurl => $url,
		content => $content,
		feeddesc => $feeddesc,
		guid => $guid,
		feeddate => date_3339($lasttime),
		feedurl => $feedurl,
		version => $IkiWiki::version,
	);
	run_hooks(pagetemplate => sub {
		shift->(page => $page, destpage => $page,
			template => $template);
	});

	return $template->output;
}

sub pingurl (@) {
	return unless @{$config{pingurl}} && %toping;

	eval q{require RPC::XML::Client};
	if ($@) {
		debug(gettext("RPC::XML::Client not found, not pinging"));
		return;
	}

	# daemonize here so slow pings don't slow down wiki updates
	defined(my $pid = fork) or error("Can't fork: $!");
	return if $pid;
	chdir '/';
	POSIX::setsid() or error("Can't start a new session: $!");
	open STDIN, '/dev/null';
	open STDOUT, '>/dev/null';
	open STDERR, '>&STDOUT' or error("Can't dup stdout: $!");

	# Don't need to keep a lock on the wiki as a daemon.
	IkiWiki::unlockwiki();

	foreach my $page (keys %toping) {
		my $title=pagetitle(basename($page), 0);
		my $url=urlto($page, "", 1);
		foreach my $pingurl (@{$config{pingurl}}) {
			debug("Pinging $pingurl for $page");
			eval {
				my $client = RPC::XML::Client->new($pingurl);
				my $req = RPC::XML::request->new('weblogUpdates.ping',
					$title, $url);
				my $res = $client->send_request($req);
				if (! ref $res) {
					error("Did not receive response to ping");
				}
				my $r=$res->value;
				if (! exists $r->{flerror} || $r->{flerror}) {
					error("Ping rejected: ".(exists $r->{message} ? $r->{message} : "[unknown reason]"));
				}
			};
			if ($@) {
				error "Ping failed: $@";
			}
		}
	}

	exit 0; # daemon done
}


sub rootpage (@) {
	my %params=@_;

	my $rootpage;
	if (exists $params{rootpage}) {
		$rootpage=bestlink($params{page}, $params{rootpage});
		if (!length $rootpage) {
			$rootpage=$params{rootpage};
		}
	}
	else {
		$rootpage=$params{page};
	}
	return $rootpage;
}

1
