package Text::Amuse::Output::Image;
use strict;
use warnings;
use utf8;
use Scalar::Util qw/looks_like_number/;

=head1 NAME

Text::Amuse::Output::Image -- class to manage images

=head1 SYNOPSIS

The module is used internally by L<Text::Amuse>, so everything here is
pretty much internal only (and underdocumented).

=head1 METHODS/ACCESSORS

=head2 new(filename => "hello.png", width => 0.5, wrap => 1)

Constructor. Accepts three options: filename, width, as a float, and
wrap, as a boolean. C<filename> is mandatory.

These arguments are saved in the objects and can be accessed with:

=over 4

=item filename

=item width

=item wrap

=item fmt

=item desc

Please note that we concatenate the caption as is. It's up to the
caller to pass an escaped string.

=back

=cut

sub new {
    my $class = shift;
    my $self = {
                width => 1,
                wrap => 0,
               };
    my %opts = @_;

    if (my $f = $opts{filename}) {
        $self->{filename} = $f;
        # just to be sure
        unless ($f =~ m{^[0-9A-Za-z][0-9A-Za-z/-]+\.(png|jpe?g)}s) {
            die "Illegal filename $f!";
        }
    }
    else {
        die "Missing filename argument!";
    }

    if (my $wrap = $opts{wrap}) {
        if ($wrap eq 'l' or $wrap eq 'r') {
            $self->{wrap} = $wrap;
        }
        else {
            die "Wrong wrapping option";
        }
    }

    if (my $w = $opts{width}) {
        if (looks_like_number($w)) {
            $self->{width} = sprintf('%.2f', $w);
        }
        else {
            die "Wrong width $w passed!";
        }
    }

    foreach my $k (qw/desc fmt/) {
        if (exists $opts{$k} and defined $opts{$k}) {
            $self->{$k} = $opts{$k};
        }
    }

    bless $self, $class;
}

sub width {
    return shift->{width};
}

sub wrap {
    return shift->{wrap};
}

sub filename {
    return shift->{filename};
}

sub fmt {
    return shift->{fmt};
}

sub desc {
    my ($self, @args) = @_;
    if (@args) {
        $self->{desc} = shift(@args);
    }
    return shift->{desc};
}

=head2 Formatters

=over 4

=item width_html

Width in percent

=item width_latex

Width as  '0.25\textwidth'

=back

=cut

sub width_html {
    my $self = shift;
    my $width = $self->width;
    my $width_in_pc = sprintf('%d', $width * 100);
    return $width_in_pc . '%';
}

sub width_latex {
    my $self = shift;
    my $width = $self->width;
    if ($width == 1) {
        return "\\textwidth";
    }
    else {
        return $self->width . "\\textwidth"; # a float
    }
}

=head1 METHODS

=over 4

=item as_latex

The LaTeX code for the image.

=item as_html

The HTML code for the image

=item output

Given that we know the format, just return the right one, using
C<as_html> or C<as_latex>.

=back


=cut



sub as_latex {
    my $self = shift;
    my $wrap = $self->wrap;
    my $width = $self->width_latex;
    my $desc = "";
    if (my $realdesc = $self->desc) {
        $desc = "\n\\bigskip\n $realdesc\n";
    }
    my $src = $self->filename;
    my $out;
    if ($wrap) {
        $out =<<"EOF";

\\begin{wrapfigure}{$wrap}{$width}
\\centering
\\includegraphics[width=$width]{$src}$desc
\\end{wrapfigure}
EOF
    }
    else {
        $out =<<"EOF";

\\begin{figure}[htp!]
\\centering
\\includegraphics[width=$width]{$src}$desc
\\end{figure}
EOF


    }
    return $out;
}

sub as_html {
    my $self = shift;
    my $wrap = $self->wrap;
    my $width = "";
    my $desc;
    my $class = "image";
    my $out;
    if ($wrap) {
        $class = "float_image_$wrap";
    }

    my $src = $self->filename;

    if (my $realdesc = $self->desc) {
        $desc = <<"EOF";
<div class="caption">$realdesc</div>
EOF
    }
    if ($self->width != 1) {
        $width = q{ style="width:} .  $self->width_html . q{;"};
    }

    $out = qq{\n<div class="$class"$width>\n} .
      qq{<img src="$src" alt="$src" class="embedimg" />\n};
    if (defined $desc) {
        $out .= $desc;
    }
    $out .= qq{</div>};
    return $out;
}

sub output {
    my $self = shift;
    if ($self->fmt eq 'ltx') {
        return $self->as_latex;
    }
    elsif ($self->fmt eq 'html') {
        return $self->as_html;
    }
    else {
        die "Bad format ". $self->fmt;
    }
}

1;
