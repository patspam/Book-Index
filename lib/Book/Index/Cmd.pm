package Book::Index::Cmd;
use base qw(App::Cmd::Simple);
use Book::Index;

sub opt_spec {
    return (
        [ "verbose|v",   "be more verbose" ],
        [ "help|h",      "helpful information" ],
        [ "doc=s",       "(re)build doc" ],
        [ "phrases=s",   "parse phrases doc" ],
        [ "max-pages=i", "max pages to process" ],
        [ "pre-pages=i", "pre (title) pages to number with roman numerals" ],
        [ "report|r",    "generate report" ],
        [ "suggest|s",   "suggest words" ],
        [ "truncate|t",   "truncate all tables" ],
    );
}

sub validate_args {
    my ( $self, $opt, $args ) = @_;

    if ( $opt->help ) {
        print $self->usage;
        exit 0;
    }

    die $self->usage unless $opt->doc || $opt->phrases || $opt->report || $opt->suggest || $opt->truncate;
}

sub execute {
    my ( $self, $opt, $args ) = @_;

    my $b = Book::Index->new(
        doc        => $opt->doc,
        phrase_doc => $opt->phrases,
        verbose    => $opt->verbose,
        max_pages  => $opt->max_pages || 0,
        pre_pages  => $opt->pre_pages || 0,
    );

    $b->truncate if $opt->truncate;
    $b->build_doc_information if $opt->doc;
    $b->build_phrase_information if $opt->phrases;
    $b->report  if $opt->report;
    $b->suggest if $opt->suggest;
}

1;
