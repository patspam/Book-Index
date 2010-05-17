use strict;
use warnings;
use Book::Index;
use Test::Most 'defer_plan', 'die';

# Sanity check on DSN
like(Book::Index->dsn, qr/^dbi:SQLite:/, 'dsn looks ok');

# Try using one of the generated classes
Book::Index::Page->truncate;
my $book = Book::Index::Page->new( page => 1, contents => 'page 1 contents' )->insert;
my @pages = Book::Index::Page->select( 'where page = ?', 1 );
is(scalar @pages, 1, 'Only 1 page found');
isa_ok($pages[0], 'Book::Index::Page');
is($pages[0]->contents, 'page 1 contents', 'Correct contents');

all_done;