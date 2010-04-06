package Indexer::Cmd;
use base qw(App::Cmd::Simple);
use Indexer;

sub opt_spec {
    return ( 
        [ "file|f=s", "index the given file" ], 
        [ "top|t=s", "show top words" ], 
        [ "word|w=s", "lookup word" ], 
    );
}

sub execute {
    my ( $self, $opt, $args ) = @_;

    if (my $file = $opt->file) {
        $self->usage_error("File does not exist: $file") unless -e $file;
        Indexer->process( $file );
    }
    
    Indexer->top($opt->top) if $opt->top;
    Indexer->word($opt->word) if $opt->word;
}

1;