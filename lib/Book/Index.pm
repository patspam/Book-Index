package Book::Index;

# ABSTRACT: Create an index for a book manuscript

=head1 DESCRIPTION

=cut

use 5.010;
use strict;
use warnings;

use Book::Index::Tables;

# use File::Slurp qw(read_file);
# use Lingua::EN::Splitter;
# use Lingua::Stem::Snowball;
# use Lingua::EN::StopWords qw(%StopWords);
# 
# use ORLite {
    # file     => 'sqlite.db',
    # readonly => 0,
    # create   => sub {
        # my $dbh = shift;
        # $dbh->do(<<END_SQL);
# CREATE TABLE word ( 
    # id INTEGER PRIMARY KEY, 
    # word TEXT, count INTEGER, 
    # page INTEGER
# )
# END_SQL
      # }
# };
# 
# sub process {
    # my ( $class, $filename ) = @_;
# 
    # my $doc      = read_file($filename);
    # my $splitter = new Lingua::EN::Splitter;
    # my $stemmer  = Lingua::Stem::Snowball->new( lang => 'en' );
# 
    # my @pages = split "\f", $doc;
# 
    # say "Generating index for file: $filename";
# 
    # for my $page ( 0 .. $#pages ) {
        # say "Processing page $page..";
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
