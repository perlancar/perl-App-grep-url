package App::grep::url;

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
    output_name => 'grep_url',
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

        scheme_contains => {
            schema => 'str*',
            tags => ['category:url-criteria'],
        },
        scheme_not_contains => {
            schema => 'str*',
            tags => ['category:url-criteria'],
        },
        scheme_matches => {
            schema => 're*',
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

        query_param_contains => {
            schema => ['hash*', of=>'str*'],
            tags => ['category:url-criteria'],
        },
        query_param_not_contains => {
            schema => ['hash*', of=>'str*'],
            tags => ['category:url-criteria'],
        },
        query_param_matches => {
            schema => ['hash*', of=>'str*'], # XXX of re
            tags => ['category:url-criteria'],
        },

        files => {
            'x.name.is_plural' => 1,
            'x.name.singular' => 'file',
            schema => ['array*', of=>'filename*'],
            pos => 0,
            slurpy => 1,
        },

        # XXX recursive (-r)
    },
    modify_meta => sub {
        my $meta = shift;
        $meta->{examples} = [
            {
                summary => 'Show lines that contain at least 2 URLs',
                'src' => q([[prog]] --min-urls 2 file.txt),
                'src_plang' => 'bash',
                'test' => 0,
                'x.doc.show_result' => 0,
            },
            {
                summary => 'Show lines that contain URLs from google',
                'src' => q([[prog]] --host-contains google file.txt),
                'src_plang' => 'bash',
                'test' => 0,
                'x.doc.show_result' => 0,
            },
            {
                summary => 'Show lines that contain search URLs from google where query contains the keyword "mortal"',
                'src' => q([[prog]] --host-contains google --query-param-contains q=mortal file.txt),
                'src_plang' => 'bash',
                'test' => 0,
                'x.doc.show_result' => 0,
            },
        ];
    },
    output_code => sub {
        my %args = @_;
        my ($fh, $file);

        my @files = @{ delete($args{files}) // [] };

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
        require URI::QueryParam;

        my @re;
        for my $scheme (@{ $args{schemes} // [] }) {
            if    ($scheme eq 'ftp')  { push @re, $Regexp::Pattern::URI::RE{ftp}{pat} }
            elsif ($scheme eq 'http') { push @re, $Regexp::Pattern::URI::RE{http}{pat} }
            elsif ($scheme eq 'ssh')  { push @re, $Regexp::Pattern::URI::RE{ssh}{pat} }
            elsif ($scheme eq 'file') { push @re, $Regexp::Pattern::URI::RE{file}{pat} }
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

            my $match = 0;
          URL:
            for my $url (@urls) {

                # scheme criteria
                if (defined $fargs->{scheme_contains}) {
                    if ($fargs->{ignore_case} ?
                         index(lc($url->scheme), lc($fargs->{scheme_contains})) >= 0 :
                         index($url->scheme    , $fargs->{scheme_contains})     >= 0) {
                    } else {
                        next;
                    }
                }
                if (defined $fargs->{scheme_not_contains}) {
                    if ($fargs->{ignore_case} ?
                         index(lc($url->scheme), lc($fargs->{scheme_not_contains})) < 0 :
                         index($url->scheme    , $fargs->{scheme_not_contains})     < 0) {
                    } else {
                        next;
                    }
                }
                if (defined $fargs->{scheme_matches}) {
                    if ($fargs->{ignore_case} ?
                            $url->scheme =~ qr/$fargs->{scheme_matches}/i :
                            $url->scheme =~ qr/$fargs->{scheme_matches}/) {
                    } else {
                        next;
                    }
                }

                # host criteria
                if (defined $fargs->{host_contains}) {
                    if ($fargs->{ignore_case} ?
                         index(lc($url->host), lc($fargs->{host_contains})) >= 0 :
                         index($url->host    , $fargs->{host_contains})     >= 0) {
                    } else {
                        next;
                    }
                }
                if (defined $fargs->{host_not_contains}) {
                    if ($fargs->{ignore_case} ?
                         index(lc($url->host), lc($fargs->{host_not_contains})) < 0 :
                         index($url->host    , $fargs->{host_not_contains})     < 0) {
                    } else {
                        next;
                    }
                }
                if (defined $fargs->{host_matches}) {
                    if ($fargs->{ignore_case} ?
                            $url->host =~ qr/$fargs->{host_matches}/i :
                            $url->host =~ qr/$fargs->{host_matches}/) {
                    } else {
                        next;
                    }
                }

                # path criteria
                if (defined $fargs->{path_contains}) {
                    if ($fargs->{ignore_case} ?
                         index(lc($url->path), lc($fargs->{path_contains})) >= 0 :
                         index($url->path    , $fargs->{path_contains})     >= 0) {
                    } else {
                        next;
                    }
                }
                if (defined $fargs->{path_not_contains}) {
                    if ($fargs->{ignore_case} ?
                         index(lc($url->path), lc($fargs->{path_not_contains})) < 0 :
                         index($url->path    , $fargs->{path_not_contains})     < 0) {
                    } else {
                        next;
                    }
                }
                if (defined $fargs->{path_matches}) {
                    if ($fargs->{ignore_case} ?
                            $url->path =~ qr/$fargs->{path_matches}/i :
                            $url->path =~ qr/$fargs->{path_matches}/) {
                    } else {
                        next;
                    }
                }

                # query param criteria
                if (defined $fargs->{query_param_contains}) {
                    for my $param (keys %{ $fargs->{query_param_contains} }) {
                        if ($fargs->{ignore_case} ?
                                index((lc($url->query_param($param)) // ''), lc($fargs->{query_param_contains}{$param})) >= 0 :
                                index(($url->query_param($param)  // '')   , $fargs->{query_param_contains}{$param})     >= 0) {
                        } else {
                            next URL;
                        }
                    }
                }
                if (defined $fargs->{query_param_not_contains}) {
                    for my $param (keys %{ $fargs->{query_param_not_contains} }) {
                        if ($fargs->{ignore_case} ?
                                index((lc($url->query_param($param)) // ''), lc($fargs->{query_param_not_contains}{$param})) < 0 :
                                index(($url->query_param($param) // '')    , $fargs->{query_param_not_contains}{$param})     < 0) {
                        } else {
                            next URL;
                        }
                    }
                }
                if (defined $fargs->{query_param_matches}) {
                    for my $param (keys %{ $fargs->{query_param_matches} }) {
                        if ($fargs->{ignore_case} ?
                                ($url->query_param($param) // '') =~ qr/$fargs->{query_param_matches}{$param}/i :
                                ($url->query_param($param) // '') =~ qr/$fargs->{query_param_matches}{$param}/) {
                        } else {
                            next URL;
                        }
                    }
                }

                $match++; last;
            }
            $match;
        };

        AppBase::Grep::grep(%args);
    },
);

1;
# ABSTRACT:
