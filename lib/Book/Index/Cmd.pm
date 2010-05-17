package Book::Index::Cmd;
use base qw(App::Cmd::Simple);
use Book::Index;

sub opt_spec {
    return ( 
        [ "verbose|v", "be more verbose" ], 
        [ "help|h", "helpful information" ], 
    );
}

sub validate_args {
    my ( $self, $opt, $args ) = @_;

    if ( $opt->help ) {
        print $self->usage;
        exit 0;
    }

    $self->usage_error('Document not specified') unless @$args eq 1;
}

sub execute {
    my ( $self, $opt, $args ) = @_;
    
    my $b = Book::Index->new( doc => $args->[0], verbose => $opt->verbose );

    $b->process_doc;
}

1;
