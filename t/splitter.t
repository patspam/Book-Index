use strict;
use Test::Most 'defer_plan', 'die';
use Book::Index::Splitter;
my $s = Book::Index::Splitter->new;

my @words = $s->words(<<END_TEXT);
being-in time 
is someone's time book.
!
END_TEXT
cmp_deeply(\@words, [qw(being time someone book)], 'splits properly') or show @words;

# Stop Words

my @filtered = qw(a b this 1 20);
for my $word (@filtered) {
    is($s->stop($word), 1, "Filtered: $word");
}

my @not_filtered = qw(cat);
for my $word (@not_filtered) {
    is($s->stop($word), undef, "Not filtered: $word");
}

all_done;