package Indexer;

# ABSTRACT: Helps create a book index

use strict;
use warnings;
use File::Slurp qw(read_file);
use Lingua::EN::Splitter;
use Lingua::Stem::Snowball;
use Lingua::EN::StopWords qw(%StopWords);

use ORLite {
    file   => 'sqlite.db',
    readonly => 0,
    create => sub {
        my $dbh = shift;
        $dbh->do('CREATE TABLE word ( id INTEGER PRIMARY KEY, word TEXT, count INTEGER, page INTEGER)');
    }
};

sub process {
    my ( $class, $filename ) = @_;
    
    my $doc      = read_file($filename);
    my $splitter = new Lingua::EN::Splitter;
    my $stemmer  = Lingua::Stem::Snowball->new( lang => 'en' );

    my @pages = split "\f", $doc;
    
    print "Generating index for file: $filename\n";

    for my $page (0 .. $#pages) {
        print "Processing page $page..\n";

        my @words = grep { !$StopWords{$_} } map {lc} @{ $splitter->words( $pages[$page] ) };

        $stemmer->stem_in_place( \@words );
        
        my %freq;
        map { $freq{$_}++ } grep { !$StopWords{$_} } @words;

        for my $word (keys %freq) {
            Indexer::Word->new( word => $word, count => $freq{$word}, page => $page )->insert;
        }
    }

    print "Finished procesing all pages.\n";
}

sub word {
    my ($class, $word) = @_;
    my $rows = Indexer->selectall_arrayref( 'select page, count from word where word = ?', undef, $word );
    print "Word stem '$word' ";
    if (!@$rows) {
        print "not found.\n";
        return;
    }
    print "appears:\n";
    for my $row (@$rows) {
        print " $row->[1] time(s) on page $row->[0]\n";
    }
}

sub top {
    my ($class, $n) = @_;
    $n ||= 10;
    my $rows = Indexer->selectall_arrayref( 'select sum(count) as count, word from word group by word order by count desc limit ?', undef, $n );
    print "Top $n Words:\n";
    for my $row (@$rows) {
        printf("%5d %s\n", @$row);
    }
}

1;

__END__

=pod

=head1 SYNOPSIS

 pdftotext doc.pdf
 indexer -f doc.text
 indexer --top 10
 indexer --word nations

=cut