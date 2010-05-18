package Book::Index;

# ABSTRACT: Create an index for a book manuscript

=head1 DESCRIPTION

=cut

use 5.010;
use strict;
use warnings;

use Book::Index::Tables;
use Any::Moose;
use File::Slurp qw(read_file);
use Lingua::EN::Splitter;    # TODO: replace with something better
use Lingua::Stem::Snowball;
use Lingua::EN::StopWords qw(%StopWords);
use List::MoreUtils qw(uniq);

has 'doc' => ( is => 'rw', required => 1 );
has 'doc_contents' => ( is => 'rw' );
has 'verbose'      => ( is => 'rw', isa => 'Bool' );
has 'splitter'     => ( is => 'ro', builder => sub { Lingua::EN::Splitter->new } );
has 'stemmer'      => ( is => 'ro', builder => sub { Lingua::Stem::Snowball->new( lang => 'en' ) } );
has 'seen_words'   => ( is => 'rw', isa => 'HashRef', default => sub { +{} } );
has 'seen_stems'   => ( is => 'rw', isa => 'HashRef', default => sub { +{} } );
has 'log_indent' => ( is => 'rw', isa => 'Int', default => 0 );
has 'max_pages' => ( is => 'rw', 'isa' => 'Int', default => 5 );

sub BUILD {
    my $self = shift;
    my $doc  = $self->doc;
    die "File not found: $doc" unless -e $doc;
}

sub process_doc {
    my $self = shift;
    $self->slurp_doc;
    $self->populate_pages;
}

sub populate_pages {
    my $self     = shift;
    my $contents = $self->doc_contents;

    $self->log('Populating pages->');
    my $page_counter = 0;
    for my $page_contents ( split "\f", $contents ) {
        $page_counter++;
        $self->log("Page $page_counter->");
        my $page = Book::Index::Page->new(
            page     => $page_counter,
            contents => $page_contents,
        )->insert;
        
        $self->process_page($page);
        
        $self->log("<-");
        last if $self->max_pages && $page_counter >= $self->max_pages;
    }
    $self->log("<-Inserted $page_counter pages");
}

sub process_page {
    my ( $self, $page ) = @_;
    
    # Get words on page
    my @words = uniq @{ $self->splitter->words( $page->contents ) };
    $self->log( scalar @words . ' words' );
    
    my $seen_words = $self->seen_words;
    my $seen_stems = $self->seen_stems;

    my (%word_freq, %stem_freq);
    for my $word (@words) {
        
        # Get canonical word and stem
        $word = lc $word;    # TODO: do we really want lowercase?
        my $stem = $self->stemmer->stem($word) || '';
        
        # Bump word and stem appearances for this page
        $word_freq{$word}++;
        $stem_freq{$stem}++;
        
        # Insert word and stem into db
        my $stem_id = $self->insert_stem( stem => $stem )->id;
        $self->insert_word( word => $word, stem => $stem_id );
    }
    
    # Create word_page and stem_page entries
    for my $word ( keys %word_freq ) {
        Book::Index::WordPage->new( word => $word, page => $page->page, n => $word_freq{$word} );
    }
    for my $stem ( keys %stem_freq ) {
        Book::Index::StemPage->new( stem => $stem, page => $page->page, n => $stem_freq{$stem} );
    }
}

sub insert_word {
    my ( $self, %args ) = @_;
    my $word       = $args{word};
    my $seen_words = $self->seen_words;
    return $seen_words->{$word} = $seen_words->{$word} || Book::Index::Word->new(%args)->insert;
}

sub insert_stem {
    my ( $self, %args ) = @_;
    my $stem       = $args{stem};
    my $seen_stems = $self->seen_stems;
    return $seen_stems->{$stem} = $seen_stems->{$stem} || Book::Index::Stem->new(%args)->insert;
}

sub slurp_doc {
    my $self = shift;
    $self->log( "Reading doc: " . $self->doc );
    my $contents = read_file( $self->doc );
    $self->doc_contents($contents);
}

sub log {
    my ( $self, $message ) = @_;
    $self->{log_indent}-- if $message =~ s/^<-//;
    $self->{log_indent}++ if $message =~ s/->$//;
    return unless $message;
    say( ( " " x $self->log_indent ) . $message ) if $self->verbose;
}

#
#
# sub process {
# my ( $class, $filename ) = @_;
#
# my @words =
# grep { !$StopWords{$_} }
# map  { lc } @{ $splitter->words( $pages[$page] ) };
#
# $stemmer->stem_in_place( \@words );
#
# my %freq;
# map { $freq{$_}++ } grep { !$StopWords{$_} } @words;
#
# for my $word ( keys %freq ) {
# Indexer::Word->new(
# word  => $word,
# count => $freq{$word},
# page  => $page
# )->insert;
# }
# }
#
# say "Finished procesing all pages.";
# }
#
# sub word {
# my ( $class, $word ) = @_;
# my $rows = Indexer->selectall_arrayref(
# 'select page, count from word where word = ?',
# undef, $word );
# print "$word: ";
# if ( !@$rows ) {
# say "not found.";
# return;
# }
# my @hits;
# for my $row (@$rows) {
# my $word = $row->[1];
# my $times = $row->[0];
# push @hits, $word . ( $times > 1 ? " (x$times)" : '' );
# }
# say join ', ', @hits;
# }
#
# sub top {
# my ( $class, $n ) = @_;
# $n ||= 10;
# my $rows = Indexer->selectall_arrayref(
# 'select sum(count) as count, word from word group by word order by count desc limit ?',
# undef, $n
# );
# say "Top $n Words:\n";
# for my $row (@$rows) {
# printf( "%5d %s\n", @$row );
# }
# }

1;
