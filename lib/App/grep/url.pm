package App::abgrep;

# AUTHORITY
# DATE
# DIST
# VERSION

use 5.010001;
use strict;
use warnings;
use Log::ger;

use AppBase::Grep;
use Perinci::Sub::Util qw(gen_modified_sub);

our %SPEC;

gen_modified_sub(
    output_name => 'abgrep',
    base_name   => 'AppBase::Grep::grep',
    summary     => 'Print lines having URL(s) (optionally of certain criteria) in them',
    description => <<'_',

This is a grep-like utility that greps for URLs of certain criteria.

_
    remove_args => [
        'ignore_case',
        'regexps',
        'pattern',
    ],
    add_args    => {
        min_urls => {
            schema => 'uint*',
            default => 1,
            tags => ['category:filtering'],
        },
        max_urls => {
            schema => 'int*',
            default => -1,
            tags => ['category:filtering'],
        },
        schemes => {
            'x.name.is_plural' => 1,
            'x.name.singular' => 'scheme',
            schema => ['array*', of=>['str*',in=>[qw/http ftp file ssh/]]],
            default => ['http', 'file'],
            tags => ['category:url-criteria'],
        },

        host_contains => {
            schema => 'str*',
            tags => ['category:url-criteria'],
        },
        host_not_contains => {
            schema => 'str*',
            tags => ['category:url-criteria'],
        },
        host_matches => {
            schema => 're*',
            tags => ['category:url-criteria'],
        },
        host_is => {
            schema => 'str*',
            tags => ['category:url-criteria'],
        },
        host_not => {
            schema => 'str*',
            tags => ['category:url-criteria'],
        },

        path_contains => {
            schema => 'str*',
            tags => ['category:url-criteria'],
        },
        path_not_contains => {
            schema => 'str*',
            tags => ['category:url-criteria'],
        },
        path_matches => {
            schema => 're*',
            tags => ['category:url-criteria'],
        },

        # XXX more criteria against query param

        files => {
            'x.name.is_plural' => 1,
            'x.name.singular' => 'file',
            schema => ['array*', of=>'filename*'],
            pos => 1,
            slurpy => 1,
        },

        # XXX recursive (-r)
    },
    modify_meta => sub {
        my $meta = shift;
        $meta->{examples} = [
            {
                summary => 'Show lines that contain at least 2 URLs',
                'src' => q([[prog]] --min-urls 2),
                'src_plang' => 'bash',
                'test' => 0,
                'x.doc.show_result' => 0,
            },
            {
                summary => 'Show lines that contain URLs from google',
                'src' => q([[prog]] --host-matches google),
                'src_plang' => 'bash',
                'test' => 0,
                'x.doc.show_result' => 0,
            },
        ];
    },
    output_code => sub {
        my %args = @_;
        my ($fh, $file);

        my @files = @{ $args{files} // [] };
        if ($args{regexps} && @{ $args{regexps} }) {
            unshift @files, delete $args{pattern};
        }

        my $show_label = 0;
        if (!@files) {
            $fh = \*STDIN;
        } elsif (@files > 1) {
            $show_label = 1;
        }

        $args{_source} = sub {
          READ_LINE:
            {
                if (!defined $fh) {
                    return unless @files;
                    $file = shift @files;
                    log_trace "Opening $file ...";
                    open $fh, "<", $file or do {
                        warn "abgrep: Can't open '$file': $!, skipped\n";
                        undef $fh;
                    };
                    redo READ_LINE;
                }

                my $line = <$fh>;
                if (defined $line) {
                    return ($line, $show_label ? $file : undef);
                } else {
                    undef $fh;
                    redo READ_LINE;
                }
            }
        };

        require Regexp::Pattern::URI;
        require URI;

        my @re;
        for my $scheme (@{ $args{schemes} // [] }) {
            if    ($scheme eq 'ftp')  { push @re, $Regexp::Pattern::URI::RE{ftp} }
            elsif ($scheme eq 'http') { push @re, $Regexp::Pattern::URI::RE{http} }
            elsif ($scheme eq 'ssh')  { push @re, $Regexp::Pattern::URI::RE{ssh} }
            elsif ($scheme eq 'file') { push @re, $Regexp::Pattern::URI::RE{file} }
            else { die "grep-url: Unknown URL scheme '$scheme'\n" }
        }
        die "grep-url: Please add one or more schemes\n" unless @re;
        my $re = join('|', @re);
        $re = qr/$re/;

        $args{_highlight_regexp} = $re;
        $args{_filter_code} = sub {
            my ($line, $fargs) = @_;

            my @urls;
            while ($line =~ /($re)/g) {
                push @urls, $1;
            }
            return 0 if $fargs->{min_urls} >= 0 && @urls < $fargs->{min_urls};
            return 0 if $fargs->{max_urls} >= 0 && @urls > $fargs->{max_urls};

            return 1 unless @urls;
            for (@urls) { $_ = URI->new($_) }

            1;
        };

        AppBase::Grep::grep(%args);
    },
);

1;
# ABSTRACT:
