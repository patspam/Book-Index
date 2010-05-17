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
use Lingua::EN::Splitter; # TODO: replace with something better
use Lingua::Stem::Snowball;
use Lingua::EN::StopWords qw(%StopWords);
use List::MoreUtils qw(uniq);

has 'doc' => ( is => 'rw', required => 1 );
has 'doc_contents' => ( is => 'rw' );
has 'verbose'      => ( is => 'rw', isa => 'Bool' );
has 'splitter'     => ( is => 'ro', builder => sub { Lingua::EN::Splitter->new } );
has 'stemmer'      => ( is => 'ro', builder => sub { Lingua::Stem::Snowball->new( lang => 'en' ) } );
has 'processed_words' => ( is => 'rw', isa => 'HashRef' );
has 'processed_stems' => ( is => 'rw', isa => 'HashRef' );
has '_log_indent' => ( is => 'rw', isa => 'Int', default => 0 );

sub BUILD {
    my $self = shift;

    my $doc = $self->doc;
    die "File not found: $doc" unless -e $doc;
}

sub process_doc {
    my $self = shift;

    $self->slurp;
    $self->process_pages;
}

sub process_pages {
    my $self     = shift;
    my $contents = $self->doc_contents;

    $self->log("Processing pages", 1);
    my $page_counter = 0;
    for my $page_contents ( split "\f", $contents ) {
        $page_counter++;

        $self->log("Processing page $page_counter");
        my $page = Book::Index::Page->new(
            page     => $page_counter,
            contents => $page_contents,
        )->insert;
        $self->process_page($page);
    }
    $self->log("Inserted $page_counter pages", -1);
}

sub process_page {
    my $self = shift;
    my $page = shift;
    
    my @words = uniq @{ $self->splitter->words( $page->contents ) };
    $self->process_words(@words);
}

sub process_words {
    my ($self, @words) = @_;
    
    my $processed_words = $self->processed_words;
    my $processed_stems = $self->processed_stems;
    
    $self->log("Processing " . scalar @words . " words", 1);
    for my $word (@words) {
        $word = lc $word; # TODO: do we really want lowercase?
        next if $processed_words->{$word};
        
        my $s = $self->stemmer->stem($word);
        my $stem = $self->insert_stem( stem => $s );
        $self->insert_word( word => $word, stem => $stem->id );
    }
}

sub insert_word {
    my ($self, %args) = @_;
    my $word = $args{word};
    
    # return cached version, if it exists
    my $processed_words = $self->processed_words;
    return $processed_words->{$word} if $processed_words->{$word};
    
    # create and insert
    my $new = Book::Index::Word->new( %args )->insert;
    $processed_words->{$word} = $new;
    return $new;
}

sub insert_stem {
    my ($self, %args) = @_;
    my $stem = $args{stem};
    
    # return cached version, if it exists
    my $processed_stems = $self->processed_stems;
    return $processed_stems->{$stem} if $processed_stems->{$stem};
    
    # create and insert
    my $new = Book::Index::Stem->new( %args )->insert;
    $processed_stems->{$stem} = $new;
    return $new;
}

sub slurp {
    my $self = shift;
    $self->log( "Reading doc: " . $self->doc );
    my $contents = read_file( $self->doc );
    $self->doc_contents($contents);
}

sub log {
    my ($self, $message, $indent) = @_;
    $self->_log_indent( $self->_log_indent + $indent ) if $indent;
    say( (" " x $indent) . $message ) if defined $message && $self->verbose;
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
