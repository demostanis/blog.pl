# blog.pl
## A small script to generate a blog

### Overview

blog.pl is a small script (~300 lines) written in Perl
to generate HTML files in order to create your own blog.

It has its own syntax, called BLog Language (BLL), consisting
of text and *shorthands*, providing ways to add easily content,
such as pieces of code (with syntax highlighting) or links to
Wikipedia articles.

It has a few optional dependencies over some CPAN modules:
- Syntax::SourceHighlight - for code syntax highlighting
- HTML::Packer - for minifying the resulting HTML files
which can easily be installed with
`$ cpanm install Syntax::SourceHighlight HTML::Packer`.

### BLL Syntax

A BLL file contains *metadata*, key value pairs separated by
a colon, which gives information such as the post's title or
the image previewed in the index of your blog, as well as the
*content*, which is composed of text and *shorthands*, taking
the following form:
`(key=value,...)<name>![ {[( ]+ <content> [ }]) ]+` 
For example:
`Check this (text=great Wikipedia article)wikipedia!(Perl)!`
will output in the resulting HTML file:
`Check this <a href="https://wikipedia.org/wiki/Perl">great Wikipedia article</a>!`

### Using
You can use blog.pl right now! First, clone this git repository:
`$ git clone https://github.com/demostanis/blog.pl.git`
Once the command has finished, edit files in the `posts/` directory.
Finally, run `./blog.pl`. It will generate your blog in `./output/`.
If you have Python installed, you can start a HTTP server:
`$ python -m http.server 8000 --directory ./output/`

### License
Copyright 2021 demostanis worlds. Licensed under GPLv3.

