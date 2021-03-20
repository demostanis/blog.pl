#!/usr/bin/env -S perl -l

use strict;
use warnings;
use experimental qw(switch);
use HTML::Entities;
use Getopt::Long;
use File::Basename;
use File::Copy;
use LWP::Simple;
use POSIX ();
use JSON;

my %options;
GetOptions (
	"silent" => \$options{silent},
	"outdir=s" => \$options{outdir},
	"config=s" => \$options{config},
);

my %config;
open(my $configfile, '<', $options{config} || './config');
while (<$configfile>) {
	chomp;
	if (/^(?<key>\w+)\s*\=\s*(?<value>\N+)$/g) {
		$config{$+{key}} = $+{value};
	}
}
my $outdir = (($options{outdir} || './output') . '/') =~ s/~/$ENV{HOME}/r;

sub optional_module {
	my ($name, $reason) = @_;
	my $module = eval {
		(my $file = $name) =~ s|::|/|g;
		require "$file.pm";
		$name->import();
		1;
	} or do {
		print "You should install $name $reason.";
	};
	return defined $module;
}

my $sourcehighlight = optional_module 'Syntax::SourceHighlight', 'to highlight code in your posts';
my $html_minifier = optional_module 'HTML::Packer', 'to reduce resulting file size';

my $code_theme = 'sh_night.css';

sub minify {
	my $code = shift;
	if ($html_minifier) {
		my $packer = HTML::Packer->init();
		return $packer->minify(\$code, { do_stylesheet => 'minify', remove_newlines => 1 });
	} else {
		return $code;
	}
}

sub handle_metadata {
	my $metadata = shift;
	$metadata->{date} =~ /(\d+)-(\d+)-(\d+)/;
	my $fulldate = POSIX::strftime("%B %d, %Y", 0, 0, 0,
		int $3, int $2 - 1, int $1 - 1900);
	if ($metadata->{code_theme}) {
		$code_theme = $metadata->{code_theme};
	}
	if ($metadata->{image} && -e 'posts/images/' . $metadata->{image}) {
		copy('posts/images/' . $metadata->{image}, $outdir . basename $metadata->{image});	
		print "Copying @{[ basename $metadata->{image} ]} to $outdir...";
	}
	return <<EOF;
<h1 id="t">$metadata->{title}</h1>
<small id="d">$fulldate</small>
EOF
}

sub handle_shorthand {
	my $shorthand = shift, my $html;
	$shorthand->{content} = $+{content};
	$shorthand->{content} =~ s/^\s+|\s+$//g if $shorthand->{args}{trim} || 'no' eq 'yes';
	print "Generating HTML for $shorthand->{name}...";
	given ($shorthand->{name}) {
		when ('escape') {
			return encode_entities $+{content}, '<>';
		}
		when ('code') {
			if ($sourcehighlight) {
				my $highlighter = Syntax::SourceHighlight->new('html.outlang');
				my $lm = Syntax::SourceHighlight::LangMap->new();
				$highlighter->setTabSpaces(int $shorthand->{args}{tabs} or 2);
				$highlighter->setGenerateLineNumbers();
				$highlighter->setLineNumberPad(' ');
				$highlighter->setStyleCssFile($code_theme);
				$html = $highlighter->highlightString($shorthand->{content},
					$lm->getMappedFileName($shorthand->{args}{lang} or 'perl'));
				$html =~ s/\n*$//s;
			} else {
				return "<pre>$shorthand->{content}</pre>"
			}
		}
		when ('wikipedia') {
			my $url = "https://wikipedia.org/wiki/$shorthand->{content}" =~ s/ /_/rg;
			my $text = $shorthand->{args}{text} || $shorthand->{content};
			return "<a href=\"$url\" target=\"_blank\">$text</a>";
		}
		when ('cpan') {
			my $name = $shorthand->{content};
			my $rightname = $name =~ s/::/-/gr;
			print "Requesting metacpan's API for module $name...";
			my $module = get "https://fastapi.metacpan.org/v1/release/$rightname?join=author";
			my $json = decode_json $module;
			my $version = $json->{version};
			my $author = $json->{author}{_source}{name};
			my $desc = $json->{abstract};
			my $website;
			if ($json->{author}{_source}{website}) {
				$website = $json->{author}{_source}{website}[0];
			}
			my $authorhtml = $website ? "<a href=\"$website\" target=\"_blank\">$author</a>" : $author;
			return "<p><a href=\"https://metacpan.org/pod/$name\" target=\"_blank\">$name</a> $version by $authorhtml</p>";
		}
		when ('comment') {
			return "<!-- $shorthand->{content} -->";
		}
		default {
			if ($shorthand->{args}) {
				my $argsstr = join ' ', join '=', each %{$shorthand->{args}};
				$html = "<$shorthand->{name} $argsstr>$shorthand->{content}</$shorthand->{name}>";
			} else {
				$html = "<$shorthand->{name}>$shorthand->{content}</$shorthand->{name}>";
			}
		}
	}
	return $html;
}

my @posts;
foreach my $file (<posts/*.bll>) {
	my %post;
	push @posts, \%post;
	print "Processing $file...";
	open(my $fd, '<', $file)
		or die "Couldn't open $file for read: $!";
	while (<$fd> =~ /^(?<key>\w+)\:\s*(?<value>\N+)$/g) {
		$post{metadata}{$+{key}} = $+{value};
	}
	my $metadata = handle_metadata $post{metadata};
	local $/;
	my $input = <$fd>;
	my @chars = split //, $input;
	for my $i (0 .. $#chars) {
		if ($chars[$i] eq '!' && $chars[$i + 1] =~ /[(\[{]/) {
			my $j = $i, my %shorthand;
			push @{$post{shorthands}}, %shorthand;
			while ($chars[--$i] =~ /\w/) {
				$shorthand{name} = $chars[$i] . ($shorthand{name} or '');
			}	
			if ($chars[$i] eq ')') {
				my $argsstr;
				while ($chars[--$i]) {
					if ($chars[$i] ne '(') {
						$argsstr = $chars[$i] . ($argsstr or '');
					} else {
						last;
					}
				}	
				while ($argsstr =~ /(?<key>\w+)\=(?<value>[^,]+),?/g) {
					$shorthand{args}{$+{key}} = $+{value};
					$input =~ s/\($argsstr\)//g;
				}
			}
			my $count, my $delimiter = ')';
			while ($_ = $chars[++$j]) {
				if (/[(\[{]/) {
					$count++;
				} else {
					last if $count > 0;
				}
			}
			$delimiter = chr(ord($chars[$j - 1]) + 2) if ($chars[$j - 1] =~ /[\[{]/);
			$input =~ s/$shorthand{name}\!\Q$chars[$j-1]\E{$count}(?<content>.*?)\Q$delimiter\E{$count}/handle_shorthand(\%shorthand)/esg;
		}
	}
	$input =~ s,\n\n,<br/><br/>,sg;
	print 'Generating HTML...';
	my $outdir = (($options{outdir} || './output') . '/') =~ s/~/$ENV{HOME}/r;
	$post{url} = $file =~ s/\.bll$/.html/r;
	my $outfile = $outdir . $post{url};
	mkdir $outdir if ! -e $outdir;
	mkdir $outdir . 'posts';
	open(my $out, '>', $outfile);
	print "Writting to $outfile...";
	print $out minify(<<EOF
<!DOCTYPE html>
<html>
<head>
	<meta charset="utf-8" />
	<style type="text/css">
body {
	background-color: black;
	color: lightgreen;
}
a {
	color: lightblue;
}
div#c {
	margin-top: 30px;
}
#c {
	text-align: center;
}
#c > pre {
	display: flex;
	justify-content: center;
	text-align: left;
}
#c > p {
	margin: 0;
}	
h1#t {
	text-align: center;
	text-transform: uppercase;
	margin-bottom: 10px;
}	
small#d {
	display: block;
	text-align: center;
}
a#h {
	position: absolute;
	text-decoration: none;
	margin: 0;
}
	</style>
</head>
<body>
	<a id="h" href="/">←</a>
	$metadata
	<div id="c">
		$input
	</div>
</body>	
</html>
EOF
	);
}

my $postshtml = '';
foreach (@posts) {
	my $imagehtml = '', my $descriptionhtml = '';
	$imagehtml = "<img src=\"$_->{metadata}{image}\"><br/>"
		if ($_->{metadata}{image});
	$descriptionhtml = "<p>$_->{metadata}{description}<br/>"
		if ($_->{metadata}{description});
	$postshtml .= <<EOF
<div class="c">
	$imagehtml
	<a class="a" href="$_->{url}">$_->{metadata}{title}</a>
	$descriptionhtml
</div>
EOF
}
my $outfile = $outdir . 'index.html';
open(my $out, '>', $outfile);
print "Writting to $outfile...";
print $out minify(<<EOF
<!DOCTYPE html>
<html>
<head>
	<meta charset="utf-8" />
	<style type="text/css">
body {
	background-color: black;
	color: lightgreen;
}
a {
	color: lightblue;
}
h1#t {
	text-align: center;
	text-transform: uppercase;
	margin-bottom: 10px;
}	
small#d {
	display: block;
	text-align: center;
	margin-bottom: 20px;
}
a.a {
	font-size: 200%;
}
.c > img {
	margin-left: auto;
	margin-right: auto;
	max-width: 100%;
	margin-bottom: 10px;
	object-fit: cover;
	height: 180px;
	width: 100%;
}
.c > p {
	margin: 15px 0 0 0;
}
.c {
	text-align: center;
	border-radius: 5px;
	background-color: #202020;
	margin-left: auto;
	margin-right: auto;
	display: inline-block;
	margin-right: 10px;
	padding: 10px;
	width: 20%;
}
	</style>
</head>
<body>
	<h1 id="t">$config{name}</h1>
	<small id="d">$config{description}</small>
	$postshtml
</body>
</html>
EOF
);

# vim:set sw=2 ts=2:
