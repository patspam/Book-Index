package Book::Index::Cmd;
use base qw(App::Cmd::Simple);
use Book::Index;

sub opt_spec {
    return (
        [ "verbose|v", "be more verbose" ],
        [ "help|h",    "helpful information" ],
        [ "rebuild|r", "rebuild database" ],
        [ "output|o",  "output report" ],
        [ "suggest|s", "suggest words" ],
    );
}

sub validate_args {
    my ( $self, $opt, $args ) = @_;

    if ( $opt->help ) {
        print $self->usage;
        exit 0;
    }

    die $self->usage unless $opt->rebuild || $opt->output || $opt->suggest;
}

sub execute {
    my ( $self, $opt, $args ) = @_;

    my $b = Book::Index->new( verbose => $opt->verbose );
    if ( $opt->rebuild ) {
        $self->usage_error('Document and/or Phrases not specified') unless @$args eq 2;
        $b->truncate;
        $b->process( $args->[0], $args->[1] );
    }
    $b->output if $opt->output;
    $b->suggest if $opt->suggest;
}

1;
