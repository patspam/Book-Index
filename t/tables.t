use strict;
use Test::More tests => 1;
use Book::Index;

like(Book::Index->dsn, qr/^dbi:SQLite:/);