package Text::Amuse::Output;
use strict;
use warnings;
use utf8;
use Text::Amuse::Output::Image;

=head1 NAME

Text::Amuse::Output

=head1 SYNOPSIS

The module is used internally by L<Text::Amuse>, so everything here is
pretty much internal only (and underdocumented).

=head1 Basic LaTeX preamble

  \documentclass[DIV=9,fontsize=10pt,oneside,paper=a5]{scrbook}
  \usepackage{graphicx}
  \usepackage{alltt}
  \usepackage{verbatim}
  \usepackage[hyperfootnotes=false,hidelinks,breaklinks=true]{hyperref}
  \usepackage{bookmark}
  \usepackage[stable]{footmisc}
  \usepackage{enumerate}
  \usepackage{longtable}
  \usepackage[normalem]{ulem}
  \usepackage{wrapfig}
  
  % avoid breakage on multiple <br><br> and avoid the next [] to be eaten
  \newcommand*{\forcelinebreak}{~\\\relax}
  % this also works
  % \newcommand*{\forcelinebreak}{\strut\\{}}

  \newcommand*{\hairline}{%
    \bigskip%
    \noindent \hrulefill%
    \bigskip%
  }
  
  % reverse indentation for biblio and play
  
  \newenvironment{amusebiblio}{
    \leftskip=\parindent
    \parindent=-\parindent
    \bigskip
    \indent
  }{\bigskip}
  
  \newenvironment{amuseplay}{
    \leftskip=\parindent
    \parindent=-\parindent
    \bigskip
    \indent
  }{\bigskip}
  
  \newcommand{\Slash}{\slash\hspace{0pt}}
  
=head2 METHODS

=head3 Text::Amuse::Output->new(document => $obj, format => "ltx")

Constructor. Format can be C<ltx> or C<html>, while document must be a
L<Text::Amuse::Document> object.

=cut

sub new {
    my $class = shift;
    my %opts = @_;
    die "Missing document object!\n" unless $opts{document};
    die "Missing or wrong format!\n" unless ($opts{format} and ($opts{format} eq 'ltx' or
                                                                $opts{format} eq 'html'));
    my $self = { document => $opts{document},
                 fmt => $opts{format} };
    bless $self, $class;
}

=head3 document

Accessor to the L<Text::Amuse::Document> object (read-only, but you
may call its method on that.

=cut

sub document {
    return shift->{document};
}

=head3 fmt

Accessor to the current format (read-only);

=cut

sub fmt {
    return shift->{fmt};
}

=head3 process

This method returns a array ref with the processed chunks. To get
a sensible output you will have to join the pieces yourself.

We don't return a joined string to avoid copying large amounts of
data.

  my $splat_pages = $obj->process(split => 1);
  foreach my $html (@$splat_pages) {
      # ...templating here...
  }

If the format is C<html>, the option C<split> may be passed. Instead
of a arrayref of chuncks, an arrayref with html pages will be
returned. Each page usually starts with an heading, and it's without
<head> <body>. Footnotes are flushed and inserted at the end of each
pages.

E.g.

  print @{$obj->process};

=cut

sub process {
    my ($self, %opts) = @_;
    my (@pieces, @splat, $splithtml);
    if ($opts{split} and $self->fmt eq 'html') {
        $splithtml = 1;
    }
    my $imagere = $self->image_re;
    $self->reset_toc_stack;
    # loop over the parsed elements
    foreach my $el ($self->document->document) {
        if ($el->type eq 'startblock') {
            die "startblock with string passed!: " . $el->string if $el->string;
            push @pieces, $self->blkstring(start => $el->block);
        }
        elsif ($el->type eq 'stopblock') {
            die "stopblock with string passed!:" . $el->string if $el->string;
            push @pieces, $self->blkstring(stop => $el->block);
        }
        elsif ($el->type eq 'regular') {
            # manage the special markup
            if ($el->string =~ m/^\s*-----*\s*$/s) {
                push @pieces, $self->manage_hr($el);
            }
            # an image by itself, so avoid it wrapping with <p></p>,
            # but only if just 1 is found. With multiple one, we get
            # incorrect output anyway, so who cares?
            elsif ($el->string =~ m/^\s*\[\[\s*$imagere\s*\]
                                    (\[[^\]\[]+?\])?\]\s*$/sx and
                   $el->string !~ m/\[\[.*\[\[/s) {
                push @pieces, $self->manage_regular($el);
            }
            else {
                push @pieces, $self->manage_paragraph($el);
            }
        }
        elsif ($el->type eq 'standalone') {
            push @pieces, $self->manage_regular($el);
        }
        elsif ($el->type =~ m/h[1-6]/) {

            # if we want a split html, we cut here and flush the footnotes
            if ($el->type =~ m/h[1-4]/ and $splithtml and @pieces) {
                
                foreach my $fn ($self->flush_footnotes) {
                    push @pieces, $self->manage_html_footnote($fn);
                }

                push @splat, join("", @pieces);
                @pieces = ();
                # all done
            }

            # then continue as usual
            push @pieces, $self->manage_header($el);
        }
        elsif ($el->type eq 'verse') {
            push @pieces, $self->manage_verse($el);
        }
        elsif ($el->type eq 'comment') {
            push @pieces, $self->manage_comment($el);
        }
        elsif ($el->type eq 'table') {
            push @pieces, $self->manage_table($el);
        }
        elsif ($el->type eq 'example') {
            push @pieces, $self->manage_example($el);
        }
        elsif ($el->type eq 'newpage') {
            push @pieces, $self->manage_newpage($el);
        }
        else {
            die "Unrecognized element: " . $el->type;
        }
    }
    if ($self->fmt eq 'html') {
        foreach my $fn ($self->flush_footnotes) {
            push @pieces, $self->manage_html_footnote($fn);
        }
    }

    if ($splithtml) {
        # catch the last
        push @splat, join("", @pieces);
        # and return
        return \@splat;
    }
    return \@pieces;
}

=head3 header

Return the formatted header as an hashref with key/value
pairs.

=cut

sub header {
    my $self = shift;
    my %directives = $self->document->raw_header;
    my %out;
    while (my ($k, $v) = each %directives) {
        $out{$k} = $self->manage_regular($v);
    }
    return \%out;
}


=head2 INTERNAL METHODS

=head3 add_footnote($num)

Add the footnote to the internal list of found footnotes. Its
existence is checked against the document object.

=cut

sub add_footnote {
    my ($self, $num) = @_;
    return unless $num;
    unless ($self->document->get_footnote($num)) {
        warn "no footnote $num found!";
        return;
    }
    unless (defined $self->{_fn_list}) {
        $self->{_fn_list} = [];
    }
    push @{$self->{_fn_list}}, $num;
}

=head3 flush_footnotes

Return the list of footnotes found as a list of digits.

=cut

sub flush_footnotes {
    my $self = shift;
    return unless (defined $self->{_fn_list});
    # if we flush, we flush and forget, so we don't collect them again
    # on the next call
    return @{delete $self->{_fn_list}};
}

=head3 manage_html_footnote

=cut

sub manage_html_footnote {
    my ($self, $num) = @_;
    return unless $num;
    my $chunk = qq{\n<p class="fnline"><a class="footnotebody"} . " "
      . qq{href="#fn_back$num" id="fn$num">[$num]</a> } .
        $self->manage_regular($self->document->get_footnote($num)) .
          qq{</p>\n};
}

=head3 blkstring 

=cut

sub blkstring  {
    my ($self, $start_stop, $block) = @_;
    die "Wrong usage! Missing params $start_stop, $block"
      unless ($start_stop && $block);
    die "Wrong usage!\n" unless ($start_stop eq 'stop' or
                                 $start_stop eq 'start');
    my $table = $self->blk_table;
    die "Table is missing an element $start_stop  $block "
      unless exists $table->{$block}->{$start_stop}->{$self->fmt};
    return $table->{$block}->{$start_stop}->{$self->fmt};
}

=head3 manage_regular($element_or_string)

Main routine to transform a string to the given format

=cut

sub manage_regular {
    my ($self, $el) = @_;
    my $string;
    my $recurse = 1;
    # we can accept even plain string;
    if (ref($el) eq "") {
        $string = $el;
    } else {
        $string = $el->string;
        if ($el->type eq 'footnote') {
            $recurse = 0;
        }
    }
    return "" unless defined $string;
    my $linkre = $self->link_re;
    # split at [[ ]] to avoid the mess
    my @pieces = split /($linkre)/, $string;
    my @out;
    while (@pieces) {
        my $l = shift @pieces;
        if ($l =~ m/^$linkre$/s) {
            push @out, $self->linkify($l);
            next;
        } else {
            next if $l eq ""; # no text!

            # convert the muse markup to tags
            $l = $self->muse_inline_syntax_to_tags($l);

            # here we have different routines
            if ($self->fmt eq 'ltx') {
                $l = $self->escape_tex($l);
                $l = $self->_ltx_replace_ldots($l);
                $l = $self->muse_inline_syntax_to_ltx($l);
                $l = $self->_ltx_replace_slash($l);
            }
            elsif ($self->fmt eq 'html') {
                $l = $self->escape_html($l);
            }
        }
        if ($recurse) {
            $l = $self->inline_footnotes($l);
        }
        push @out, $l;
    }
    return join("", @out);
}

=head3 inline_footnotes($string)

Inline the footnotes in the given string, accordingly to the current
format.

=cut

sub inline_footnotes {
    my ($self, $string) = @_;
    my @output;
    my $footnotere = $self->footnote_re;
    return $string unless $string =~ m/($footnotere)/;
    my @pieces = split /( *$footnotere)/, $string;
    while (@pieces) {
        my $piece = shift @pieces;
        if ($piece =~ m/^( *)\[([0-9]+)\]$/s) {
            my $space = $1 || "";
            my $fn_num = $2;
            my $footnote = $self->document->get_footnote($fn_num);
            # here we have a bit of recursion, but it should be safe
            if (defined $footnote) {
                $footnote = $self->manage_regular($footnote);
                if ($self->fmt eq "ltx") {
                    $footnote =~ s/\n/ /gs;
                    $footnote =~ s/ +$//s;
                    push @output, '\footnote{' . $footnote . '}';
                }
                elsif ($self->fmt eq "html") {
                    # in html, just remember the number
                    $self->add_footnote($fn_num);
                    push @output,
                      qq{$space<a href="#fn${fn_num}" class="footnote" } .
                        qq{id="fn_back${fn_num}">[$fn_num]</a>};
                }
            }
            else {
                # warn "Missing footnote [$fn_num] in $string";
                push @output, $piece;
            }
        }
        else {
            push @output, $piece;
        }
    }
    return join("", @output);
}

=head3 safe($string)

Be sure that the strings passed are properly escaped for the current
format, to avoid command injection.

=cut

sub safe {
    my ($self, $string) = @_;
    if ($self->fmt eq 'ltx') {
        return $self->escape_tex($string);
    }
    elsif ($self->fmt eq 'html') {
        return $self->escape_all_html($string);
    }
}

=head3 escape_tex($string)

Escape the string for LaTeX output

=cut

sub escape_tex {
    my ($self, $string) = @_;
    $string =~ s/\\/\\textbackslash{}/g;
    $string =~ s/#/\\#/g ;
    $string =~ s/\$/\\\$/g;
    $string =~ s/%/\\%/g;
    $string =~ s/&/\\&/g;
    $string =~ s/_/\\_/g ;
    $string =~ s/{/\\{/g ;
    $string =~ s/}/\\}/g ;
    $string =~ s/\\textbackslash\\{\\}/\\textbackslash{}/g;
    $string =~ s/~/\\textasciitilde{}/g ;
    $string =~ s/\^/\\^{}/g ;
    $string =~ s/\|/\\textbar{}/g;
    return $string;
}

sub _ltx_replace_ldots {
    my ($self, $string) = @_;
    my $ldots = "\\dots{}";
    $string =~ s/\.{3,4}/$ldots/g ;
    $string =~ s/\x{2026}/$ldots/g;
    return $string;
}

sub _ltx_replace_slash {
    my ($self, $string) = @_;
    $string =~ s!/!\\Slash{}!g;
    return $string;
}

=head4 escape_all_html($string)

Escape the string for HTML output

=cut

sub escape_all_html {
    my ($self, $string) = @_;
    $string =~ s/&/&amp;/g;
    $string =~ s/</&lt;/g;
    $string =~ s/>/&gt;/g;
    $string =~ s/"/&quot;/g;
    $string =~ s/'/&#x27;/g;
    return $string;
}

=head3 muse_inline_syntax_to_ltx

=cut

sub muse_inline_syntax_to_ltx {
    my ($self, $string) = @_;
    $string =~ s!<strong>(.+?)</strong>!\\textbf{$1}!gs;
    $string =~ s!<em>(.+?)</em>!\\emph{$1}!gs;
    $string =~ s!<code>(.+?)</code>!\\texttt{$1}!gs;
    # the same
    $string =~ s!<strike>(.+?)</strike>!\\sout{$1}!gs;
    $string =~ s!<del>(.+?)</del>!\\sout{$1}!gs;
    $string =~ s!<sup>(.+?)</sup>!\\textsuperscript{$1}!gs;
    $string =~ s!<sub>(.+?)</sub>!\\textsubscript{$1}!gs;
    $string =~ s!^[\s]*<br ?/?>[\s]*$!\n\\bigskip\n!gs;
    $string =~ s!<br ?/?>!\\forcelinebreak !gs;
    return $string;
}

=head3 escape_html

=cut

sub escape_html {
    my ($self, $string) = @_;
    $string = $self->remove_permitted_html($string);
    $string = $self->escape_all_html($string);
    $string = $self->restore_permitted_html($string);
    return $string;
}

=head3 remove_permitted_html

=cut

sub remove_permitted_html {
    my ($self, $string) = @_;
    foreach my $tag (keys %{ $self->tag_hash }) {
        # only matched pairs, so we avoid a lot of problems
        # we also use private unicode codepoints to mark start and end
        my $marker = $self->tag_hash->{$tag};
        my $startm = "\x{f0001}${marker}\x{f0002}";
        my $stopm  = "\x{f0003}${marker}\x{f0004}";
        $string =~ s!<$tag>
                     (.*?)
                     </$tag>
                    !$startm$1$stopm!gsx;
    };
    my $brhash = $self->br_hash;
    $string =~ s!<br */*>!\x{f0001}$brhash\x{f0002}!gs;
    return $string;
}

=head3 restore_permitted_html

=cut

sub restore_permitted_html {
    my ($self, $string) = @_;
    foreach my $hash (keys %{ $self->reverse_tag_hash }) {
        my $orig = $self->reverse_tag_hash->{$hash};
        $string =~ s!\x{f0001}$hash\x{f0002}!<$orig>!gs;
        $string =~ s!\x{f0003}$hash\x{f0004}!</$orig>!gs;
    }
    my $brhash = $self->br_hash;
    $string =~ s!\x{f0001}$brhash\x{f0002}!<br />!gs;
    return $string;
}

=head3 muse_inline_syntax_to_tags

=cut

sub muse_inline_syntax_to_tags {
    my ($self, $string) = @_;
    # first, add a space around, so we don't need to check for ^ and $
    $string = " " . $string . " ";
    # the *, something not a space, the match (no * inside), something
    # not a space, the *
    my $something = qr{\*(?=\S)([^\*]+?)(?<=\S)\*};
    # the same, but for =
    my $somethingeq = qr{\=(?=\S)([^\=]+?)(?<=\S)\=};

    # before and after the *, something not a word and not an *
    $string =~ s{(?<=[^\*\w])\*\*
                 $something
                 \*\*(?=[^\*\w])}
                {<strong><em>$1</em></strong>}gsx;
    $string =~ s{(?<=[^\*\w])\*
                 $something
                 \*(?=[^\*\w])}
                {<strong>$1</strong>}gsx;
    $string =~ s{(?<=[^\*\w])
                 $something
                 (?=[^\*\w])}
                {<em>$1</em>}gsx;
    $string =~ s{(?<=[^\=\w])
                 $somethingeq
                 (?=[^\=\w])}
                {<code>$1</code>}gsx;
    # the full line without the 2 spaces added;
    my $l = (length $string) - 2;
    # return the string, starting from 1 and for the length of the string.
    return substr($string, 1, $l);
}

=head3 manage_paragraph

=cut

sub manage_paragraph {
    my ($self, $el) = @_;
    my $body = $self->manage_regular($el);
    chomp $body;
    return $self->blkstring(start  => "p") .
      $body . $self->blkstring(stop => "p");
}

=head3 manage_header

=cut

sub manage_header {
    my ($self, $el) = @_;
    my $body = $self->manage_regular($el);
    # remove trailing spaces and \n
    chomp $body;
    my $leading = $self->blkstring(start => $el->type);
    # add them to the ToC for html output;
    if ($el->type =~ m/h([1-4])/) {
        my $level = $1;
        my $tocline = $body;
        my $index = $self->add_to_table_of_contents($level => $body);
        $level++; # increment by one
        die "wtf, no index for toc?" unless $index;

        # inject the id into the html toc
        if ($self->fmt eq 'html') {
            $leading = "<h" . $level .
              qq{ id="toc$index">};
        }
    }
    return $leading .
      $body .
        $self->blkstring(stop => $el->type) . "\n";
}

=head3 add_to_table_of_contents

When we catch an header, we save it in the Output object, so we can
emit the ToC. Level 5 is excluded as per doc.

It returns the numerical index (so you can inject the id).

=cut

sub add_to_table_of_contents {
    my ($self, $level, $string) = @_;
    return unless ($level and defined($string) and $string ne '');
    unless (defined $self->{_toc_entries}) {
        $self->{_toc_entries} = [];
    }
    my $index = scalar(@{$self->{_toc_entries}});
    push @{$self->{_toc_entries}}, { level => $level,
                                     string => $string,
                                     index => ++$index,
                                   };
    return $index;
}

=head3 reset_toc_stack

Clear out the list. This is called at the beginning of the main loop,
so we don't collect duplicates over multiple runs.

=cut

sub reset_toc_stack {
    my $self = shift;
    delete $self->{_toc_entries} if defined $self->{_toc_entries};
}

=head3 table_of_contents

Emit the formatted toc (if any). Please note that this method works
even for the LaTeX format, even if does not produce usable output.

This because we can test if we need to emit a table of contents
looking at this without searching the whole output.

=cut

sub table_of_contents {
    my $self = shift;
    my $internal_toc = $self->{_toc_entries};
    my @toc;
    return @toc unless $internal_toc; # no toc gets undef
    # do a deep copy and return;
    foreach my $entry (@$internal_toc) {
        push @toc, { %$entry };
    }
    return @toc;
}

=head3 html_toc

The HTML formatted table of contents.

=cut

sub html_toc {
    my $self = shift;
    return "" unless $self->fmt eq 'html';
    my @toc = $self->table_of_contents;
    return "" unless @toc;
    # do the dirty job
    my @out;
    foreach my $item (@toc) {
        # given that we wrap this into <a>, we have to strip eventual ones

        my $string = $item->{string};
        $string =~ s!<a [^>]+?>!!g;
        $string =~ s!</a>!!g;

        my $line = qq{<p class="tableofcontentline toclevel} .
          $item->{level} . qq{"><span class="tocprefix">} .
          "&nbsp;&nbsp;" x  $item->{level} . "</span>" .
            qq{<a href="#toc} . $item->{index} . qq{">} .
              $string . "</a></p>";
        push @out, $line;
    }
    return join ("\n", @out) . "\n";
}



=head3 manage_verse

=cut

sub manage_verse {
    my ($self, $el) = @_;
    my ($lead, $eol, $stanzasep);
    if ($self->fmt eq 'html') {
        $lead = "&nbsp;";
        $eol = "<br />\n";
        $stanzasep = "\n<br /><br />\n";
    }
    elsif ($self->fmt eq 'ltx') {
        $lead = "~";
        $eol = "\\forcelinebreak\n";
        $stanzasep = "\n\n";
    }
    my @stanza;
    my @out;
    my (@chunks) = split(/\n/, $el->string);
    foreach my $l (@chunks) {
        if ($l =~ m/^( *)(.+?)$/s) {
            my $leading = $lead x length($1);
            my $text = $self->manage_regular($2);
            push @stanza, $leading . $text;
        }
        elsif ($l =~ m/^\s*$/s) {
            if (@stanza) {
                push @out, join($eol, @stanza);
                @stanza = ();
            }
        }
        else {
            die "wtf?";
        }
    }
    # flush the stanzas
    if (@stanza) {
        push @out, join($eol, @stanza);
    }
    # process
    return $self->blkstring(start => $el->type) .
      join($stanzasep, @out) . $self->blkstring(stop => $el->type);
}

=head3 manage_comment

=cut

sub manage_comment {
    my ($self, $el) = @_;
    my $body = $self->safe($el->removed);
    chomp $body;
    return $self->blkstring(start => $el->type) .
      $body . $self->blkstring(stop => $el->type);
}

=head3 manage_table

=cut

sub manage_table {
    my ($self, $el) = @_;
    my $thash = $self->_split_table_in_hash($el->string);
    if ($self->fmt eq 'html') {
        return $self->manage_table_html($thash);
    }
    elsif ($self->fmt eq 'ltx') {
        return $self->manage_table_ltx($thash);
    }
    else {
        die "wtf?"
    }
}

=head3 manage_table_html

=cut

sub manage_table_html {
    my ($self, $table) = @_;
    my @out;
    my $map = $self->html_table_mapping;
    # here it's full of hardcoded things, but it can't be done differently
    push @out, "\n<table>";

    # the hash is always defined
    if ($table->{caption} ne "") {
        push @out, "<caption>"
          . $self->manage_regular($table->{caption})
            . "</caption>";
    }

    foreach my $tablepart (qw/head foot body/) {
        next unless @{$table->{$tablepart}};
        push @out, $map->{$tablepart}->{b};
        while (@{$table->{$tablepart}}) {
            my $cells = shift @{$table->{$tablepart}};

            push @out, $map->{btr};
            while (@$cells) {
                my $cell = shift @$cells;
                push @out, $map->{$tablepart}->{bcell},
                  $self->manage_regular($cell),
                    $map->{$tablepart}->{ecell},
                }
            push @out, $map->{etr};
        }
        push @out, $map->{$tablepart}->{e};
    }
    push @out, "</table>\n";
    return join("\n", @out);
}

=head3 manage_table_ltx

=cut

sub manage_table_ltx {
    my ($self, $table) = @_;

    my $out = {
               body => [],
               head => [],
               foot => [],
              };
    foreach my $t (qw/body head foot/) {
        foreach my $rt (@{$table->{$t}}) {
            my @row;
            foreach my $cell (@$rt) {
                # escape all!
                push @row, $self->manage_regular($cell);
            }
            my $texrow = join(q{ & }, @row);
            push @{$out->{$t}}, "\\relax " . $texrow . "  \\\\\n"
        }
    }
    # then we loop over what we have. First head, then body, and
    # finally foot
    my $has_caption;
    if (defined $table->{caption} and $table->{caption} ne '') {
        $has_caption = 1;
    }
    my $textable = '';
    if ($has_caption) {
        $textable .= "\\begin{table}[htbp!]\n";
    }
    else {
        $textable .= "\\bigskip\n\\noindent\n";
    }
    $textable .= " \\begin{minipage}[t]{\\textwidth}\n";
    $textable .= "\\begin{tabularx}{\\textwidth}{" ;
    $textable .= "|X" x $table->{counter};
    $textable .= "|}\n";
    if (my @head = @{$out->{head}}) {
        $textable .= "\\hline\n" . join("", @head);
    }
    if (my @body = @{$out->{body}}) {
        $textable .= "\\hline\n" . join("", @body);
    }
    if (my @foot = @{$out->{foot}}) {
        $textable .= "\\hline\n" . join("", @foot);
    }
    $textable .= "\\hline\n\\end{tabularx}\n";
    if ($has_caption) {
        $textable .= "\n\\caption[]{" .
          $self->manage_regular($table->{caption}) . "}\n";
    }
    $textable .= "\\end{minipage}\n";
    if ($has_caption) {
        $textable .= "\\end{table}\n";
    }
    else {
        $textable .= "\\bigskip\n";
    }
    $textable .= "\n";
    # print $textable;
    return $textable;
}

=head3 _split_table_in_hash

=cut

sub _split_table_in_hash {
    my ($self, $table) = @_;
    return {} unless $table;
    my $output = {
                  caption => "",
                  body => [],
                  head => [],
                  foot => [],
                  counter => 0,
                 };
    foreach my $row (split "\n", $table) {
        if ($row =~ m/^\s*\|\+\s*(.+?)\s*\+\|\s*$/) {
            $output->{caption} = $1;
            next
        }
        my $dest;
        my @cells = split /\|+/, $row;
        if ($output->{counter} < scalar(@cells)) {
            $output->{counter} = scalar(@cells);
        }
        if ($row =~ m/\|\|\|/) {
            push @{$output->{foot}}, \@cells;
        } elsif ($row =~ m/\|\|/) {
            push @{$output->{head}}, \@cells;
        } else {
            push @{$output->{body}}, \@cells;
        }
    }
    # pad the cells with " " if their number doesn't match
    foreach my $part (qw/body head foot/) {
        foreach my $row (@{$output->{$part}}) {
            while (@$row < $output->{counter}) {
                # warn "Found uneven table: " . join (":", @$row), "\n";
                push @$row, " ";
            }
        }
    }
    return $output;
}

=head3 manage_example

=cut

sub manage_example {
    my ($self, $el) = @_;
    my $body = $self->safe($el->string);
    return $self->blkstring(start => $el->type) .
      $body . $self->blkstring(stop => $el->type);
}

=head3 manage_hr

Put an horizontal rule

=cut

sub manage_hr {
    my ($self, $el) = @_;
    die "Wtf?" if $el->string =~ m/\w/s; # don't eat chars by mistake
    if ($self->fmt eq 'html') {
        return "\n<hr />\n";
    }
    elsif ($self->fmt eq 'ltx') {
        return "\n\\hairline\n\n";
    }
}

=head3 manage_newpage

If it's LaTeX, insert a newpage

=cut

sub manage_newpage {
    my ($self, $el) = @_;
    die "Wtf? " . $el->string if $el->string =~ m/\w/s; # don't eat chars by mistake
    if ($self->fmt eq 'html') {
        my $out = $self->blkstring(start => 'center') .
          $self->manage_paragraph($el) .
            $self->blkstring(stop => 'center');
        return $out;
    }
    elsif ($self->fmt eq 'ltx') {
        return "\n\\cleardoublepage\n\n";
    }
}


=head2 Links management

=head3 linkify($link)

Here we see if it's a single one or a link/desc pair. Then dispatch

=cut

sub linkify {
    my ($self, $link) = @_;
    die "no link passed" unless defined $link;
    # warn "Linkifying $link";
    if ($link =~ m/^\[\[
                     \s*
                     (.+?) # link
                     \s*
                     \]\[
                     \s*
                     (.+?) # desc
                     \s*
                     \]\]$
                    /sx) {
        return $self->format_links($1, $2);
    }

    elsif ($link =~ m/\[\[
		   \s*
		   (.+?) # link
		   \s*
		   \]\]/sx) {
        return $self->format_single_link($1);
    }

    else {
        die "Wtf??? $link"
    }
}

=head3 format_links

=cut

sub format_links {
    my ($self, $link, $desc) = @_;
    $desc = $self->manage_regular($desc);
    # first the images
    if (my $image = $self->find_image($link)) {
        my $src = $image->filename;
        $self->document->attachments($src);
        $image->desc($desc);
        return $image->output;
    }
    # links
    if ($self->fmt eq 'html') {
        $link = $self->_url_safe_escape($link);
        return qq{<a href="$link">$desc</a>};
    }
    elsif ($self->fmt eq 'ltx') {
        return qq/\\href{/ .
          $self->_url_safe_escape($link) .
            qq/}{$desc}/;
    }
}

=head3 format_single_link

=cut

sub format_single_link {
    my ($self, $link) = @_;
    # the re matches only clean names, no need to escape anything
    if (my $image = $self->find_image($link)) {
        $self->document->attachments($image->filename);
        return $image->output;
    }
    if ($self->fmt eq 'html') {
        $link = $self->_url_safe_escape($link);
        return qq{<a href="$link">$link</a>};
    }
    elsif ($self->fmt eq 'ltx') {
        return "\\url{" . $self->_url_safe_escape($link) . "}";
    }
}

=head3 _url_safe_escape

=cut

sub _url_safe_escape {
  my ($self, $string) = @_;
  utf8::encode($string);
  $string =~ s/([^0-9a-zA-Z\.\/\:\;_\%\&\#\?\=\-])
	      /sprintf("%%%02X", ord ($1))/gesx;
  my $escaped = $self->safe($string);
  return $escaped;
}

=head1 HELPERS

Methods providing some fixed values

=cut

=head3 blk_table

=cut

sub blk_table {
    my $table = {
                                  p =>  { start => {
                                                    ltx => "\n",
                                                    html => "\n<p>\n",
                                                   },
                                          stop => {
                                                   ltx => "\n\n",
                                                   html => "\n</p>\n",
                                                  },
                                        },
                                  h1 => {
                                         start => {
                                                   ltx => "\\part{",
                                                   html => "<h2>",
                                                  },
                                         stop => {
                                                  ltx => "}\n",
                                                  html => "</h2>\n"
                                                 }
                                        },
                                  h2 => {
                                         start => {
                                                   ltx => "\\chapter{",
                                                   html => "<h3>",
                                                  },
                                         stop => {
                                                  ltx => "}\n",
                                                  html => "</h3>\n"
                                                 }
                                        },
                                  h3 => {
                                         start => {
                                                   ltx => "\\section{",
                                                   html => "<h4>",
                                                  },
                                         stop => {
                                                  ltx => "}\n",
                                                  html => "</h4>\n"
                                                 }
                                        },
                                  h4 => {
                                         start => {
                                                   ltx => "\\subsection{",
                                                   html => "<h5>",
                                                  },
                                         stop => {
                                                  ltx => "}\n",
                                                  html => "</h5>\n"
                                                 }
                                        },
                                  h5 => {
                                         start => {
                                                   ltx => "\\subsubsection{",
                                                   html => "<h6>",
                                                  },
                                         stop => {
                                                  ltx => "}\n",
                                                  html => "</h6>\n"
                                                 }
                                        },
                                  example => { 
                                              start => { 
                                                        tex => "{\n\\startlines[space=on,style=\\tt]\n",
                                                        html => "\n<pre class=\"example\">\n",
                                                        ltx => "\n\\begin{alltt}\n",
                                                       },
                                              stop => {
                                                       tex => "\n\\stoplines\n",
                                                       html => "\n</pre>\n",
                                                       ltx => "\n\\end{alltt}\n\n",
                                                      },
                                             },
                                  
                                  comment => {
                                              start => { # we could also use a more
                                                        # stable startstop hiding
                                                        tex => "\n\\startcomment[][]\n",
                                                        html => "\n<!-- start comment -->\n<div class=\"comment\"><span class=\"commentmarker\">{{COMMENT:</span> \n",
                                                        ltx => "\n\n\\begin{comment}\n",
                                                       },
                                              stop => {
                                                       tex => "\n\\stopcomment\n",
                                                       html => "\n<span class=\"commentmarker\">END_COMMENT}}:</span>\n</div>\n<!-- stop comment -->\n",  
                                                       ltx => "\n\\end{comment}\n\n",
                                                      },
                                             },
                                  verse => {
                                            start => {
                                                      tex => "\n\n\\startawikiverse\n",
                                                      html => "<div class=\"verse\">\n",
                                                      ltx => "\n\n\\begin{verse}\n",
                                                     },
                                            stop => {
                                                     tex => "\\stopawikiverse\n\n",
                                                     html => "\n</div>\n",
                                                     ltx => "\n\\end{verse}\n\n",
                                                    },
                                           },
                               quote => {
                                         start => {
                                                   tex => "\n\\startblockquote\n",
                                                   html => "\n<blockquote>\n",
                                                   ltx => "\n\n\\begin{quote}\n\n",
                                                  },
                                         stop => {
                                                  tex => "\n\\stopblockquote\n",
                                                  html => "\n</blockquote>\n",
                                                  ltx => "\n\n\\end{quote}\n\n",
                                                 },
                                        },
	      
                               biblio => {
                                          start => {
                                                    tex => "\\startawikibiblio\n",
                                                    html => "\n<div class=\"biblio\">\n",
                                                    ltx => "\n\n\\begin{amusebiblio}\n\n",
                                                   },
                                          stop => {
                                                   tex => "\\stopawikibiblio\n",
                                                   html => "\n</div>\n",
                                                   ltx => "\n\n\\end{amusebiblio}\n\n",
                                                  },
                                         },
                               play => {
                                        start => {
                                                  tex => "\\startawikiplay\n",
                                                  html => "\n<div class=\"play\">\n",
                                                  ltx => "\n\n\\begin{amuseplay}\n\n",
                                                 },
                                        stop => {
                                                 tex => "\\stopawikiplay\n",
                                                 html => "\n</div>\n",
                                                 ltx => "\n\n\\end{amuseplay}\n\n",
                                                },
                                       },

                               center => {
                                          start => {
                                                    tex => "\\startawikicenter\n",
                                                    html => "\n<div class=\"center\">\n",
                                                    ltx => "\n\n\\begin{center}\n",
                                                   },
                                          stop => {
                                                   tex => "\\stopawikicenter\n",
                                                   html => "\n</div>\n",
                                                   ltx => "\n\\end{center}\n\n",
                                                  },
                                         },
                               right => {
                                         start => {
                                                   tex => "\\startawikiright\n",
                                                   html => "\n<div class=\"right\">\n",
                                                   ltx => "\n\n\\begin{flushright}\n",
                                                  },
                                         stop => {
                                                  tex => "\\stopawikiright\n",
                                                  html => "\n</div>\n",
                                                  ltx => "\n\\end{flushright}\n\n",
                                                 },
                                        },

                               ul => {
                                      start => {
                                                tex => "\n\\startitemize[1]\\relax\n",
                                                html => "\n<ul>\n",
                                                ltx => "\n\\begin{itemize}\n",
                                               },
                                      stop => {
                                               tex => "\n\\stopitemize\n",
                                               html => "\n</ul>\n",
                                               ltx => "\n\\end{itemize}\n",
                                              },
                                     },

                               ol => {
                                      start => {
                                                tex => "\n\\startitemize[N]\\relax\n",
                                                html => "\n<ol>\n",
                                                ltx => "\n\\begin{enumerate}[1.]\n",
                                               },
                                      stop => {
                                               tex => "\n\\stopitemize\n",
                                               html => "\n</ol>\n",
                                               ltx => "\n\\end{enumerate}\n",
                                              },
                                     },

                               oln => {
                                       start => {
                                                 tex => "\n\\startitemize[N]\\relax\n",
                                                 html => "\n<ol>\n",
                                                 ltx => "\n\\begin{enumerate}[1.]\n",
                                                },
                                       stop => {
                                                tex => "\n\\stopitemize\n",
                                                html => "\n</ol>\n",
                                                ltx => "\n\\end{enumerate}\n",
                                               },
                                      },

                               oli => {
                                       start => {
                                                 tex => "\n\\startitemize[r]\\relax\n",
                                                 html => "\n<ol style=\"list-style-type:lower-roman\">\n",
                                                 ltx => "\n\\begin{enumerate}[i.]\n",
                                                },
                                       stop => {
                                                tex => "\n\\stopitemize\n",
                                                html => "\n</ol>\n",
                                                ltx => "\n\\end{enumerate}\n",
                                               },
                                      },

                               olI => {
                                       start => {
                                                 tex => "\n\\startitemize[R]\\relax\n",
                                                 html => "\n<ol style=\"list-style-type:upper-roman\">\n",
                                                 ltx => "\n\\begin{enumerate}[I.]\n",
                                                },
                                       stop => {
                                                tex => "\n\\stopitemize\n",
                                                html => "\n</ol>\n",
                                                ltx => "\n\\end{enumerate}\n",
                                               },
                                      },

                               olA => {
                                       start => {
                                                 tex => "\n\\startitemize[A]\\relax\n",
                                                 html => "\n<ol style=\"list-style-type:upper-alpha\">\n",
                                                 ltx => "\n\\begin{enumerate}[A.]\n",
                                                },
                                       stop => {
                                                tex => "\n\\stopitemize\n",
                                                html => "\n</ol>\n",
                                                ltx => "\n\\end{enumerate}\n",
                                               },
                                      },

                               ola => {
                                       start => {
                                                 tex => "\n\\startitemize[a]\\relax\n",
                                                 html => "\n<ol style=\"list-style-type:lower-alpha\">\n",
                                                 ltx => "\n\\begin{enumerate}[a.]\n",
                                                },
                                       stop => {
                                                tex => "\n\\stopitemize\n",
                                                html => "\n</ol>\n",
                                                ltx => "\n\\end{enumerate}\n",
                                               },
                                      },

                               li => {
                                      start => {
                                                tex => "\\item[] ",
                                                html => "<li>",
                                                ltx => "\\item\\relax ",
                                               },
                                      stop => {
                                               tex => "\n\n ",
                                               html => "\n</li>\n",
                                               ltx => "\n\n",
                                              },
                                     },
                };
    return $table;
}

=head3 link_re

=cut

sub link_re {
    return qr{\[\[[^\[].*?\]\]};
}

=head3 image_re

Regular expression to match image links.

=cut

sub image_re {
    return qr{([0-9A-Za-z][0-9A-Za-z/-]+ # basename
                                    \. # dot
                                    (png|jpe?g)) # extension $2
                                ([ ]+
                                    ([0-9]+)? # width in percent
                                    ([ ]*([rlf]))?
                                )?}x;
}

=head3 find_image($link)

Given the input string $link, return undef if it's not an image. If it
is, return a Text::Amuse::Output::Image object.

=cut

sub find_image {
    my ($self, $link) = @_;
    my $imagere = $self->image_re;
    if ($link =~ m/^$imagere$/s) {
        my $filename = $1;
        my $width = $4;
        my $float = $6;
        return Text::Amuse::Output::Image->new(filename => $filename,
                                               width => $width,
                                               wrap => $float,
                                               fmt => $self->fmt);
    }
    else {
        # warn "Not recognized\n";
        return;
    }
}


=head3 url_re

=cut

sub url_re {
    return qr!((www\.|https?:\/\/)
                              \w[\w\-\.]+\.\w+ # domain
                              (:\d+)? # the port
                              # everything else, but start with a
                              # slash and end with a a \w, and don't
                              # tolerate spaces
                              (/(\S*\w)?)?)
                             !x;
}

=head3 footnote_re

=cut

sub footnote_re {
    return qr{\[[0-9]+\]};
}

=head3 br_hash

=cut

sub br_hash {
    my $self = shift;
    unless (defined $self->{_br_hash}) {
        my $random = sprintf('%u', rand(10000));
        $self->{_br_hash} = '49777d285f86e8b252431fdc1a78b92459704911' . $random;
    }
    return $self->{_br_hash};
}

=head3 tag_hash

=cut

sub tag_hash {
    my $self = shift;
    unless (defined $self->{_tag_hash}) {
        my $random = sprintf('%u', rand(10000));
        $self->{_tag_hash} =
          {
           'em' => '93470662f625a56cd4ab62d9d820a77e6468638e' . $random,
           'sub' => '5d85613a56c124e3a3ff8ce6fc95d10cdcb5001e' . $random,
           'del' => 'fea453f853c8645b085126e6517eab38dfaa022f' . $random,
           'strike' => 'afe5fd4ff1a85caa390fd9f36005c6f785b58cb4' . $random,
           'strong' => '0117691d0201f04aa02f586b774c190802d47d8c' . $random,
           'sup' => '3844b17b367801f41a3ff27aab7d5ca297c2b984' . $random,
           'code' => 'e6fb06210fafc02fd7479ddbed2d042cc3a5155e' . $random,
          };
    }
    return { %{$self->{_tag_hash} } };
}

=head3 reverse_tag_hash

=cut

sub reverse_tag_hash {
    my $self = shift;
    unless (defined $self->{_reverse_tag_hash}) {
        my %hash = %{ $self->tag_hash };
        my %reverse = reverse %hash;
        $self->{_reverse_tag_hash} = \%reverse;
    }
    return { %{$self->{_reverse_tag_hash}} };
}

=head3 html_table_mapping

=cut

sub html_table_mapping {
    return {
            head => {
                     b => " <thead>",
                     e => " </thead>",
                     bcell => "   <th>",
                     ecell => "   </th>",
                    },
            foot => {
                     b => " <tfoot>",
                     e => " </tfoot>",
                     bcell => "   <td>",
                     ecell => "   </td>",
                    },
            body => {
                     b => " <tbody>",
                     e => " </tbody>",
                     bcell => "   <td>",
                     ecell => "   </td>",
                    },
            btr => "  <tr>",
            etr => "  </tr>",
           };
}

1;
