use strict;
use warnings;
use Book::Index;
use Test::Most 'defer_plan', 'die';
use File::Temp;

my $file     = File::Temp->new;
my $filename = "$file";
$file->print('blah');
$file->close;

my $b = Book::Index->new( doc => $filename );
$b->process_doc;

is( $b->doc_contents, 'blah', 'Correct contents' );

all_done;
