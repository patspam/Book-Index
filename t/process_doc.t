use strict;
use warnings;
use Book::Index;
use Test::Most 'defer_plan', 'die';
use File::Temp;

my @original_pages = ( 'this is page 1', 'page 2 is about horses' );
my $original_contents = join "\f", @original_pages;

my $doc     = File::Temp->new;
my $docname = "$doc";
$doc->print($original_contents);
$doc->close;

my $phrase_doc     = File::Temp->new;
my $phrase_docname = "$phrase_doc";
$phrase_doc->print($original_contents);
$phrase_doc->close;

my $b = Book::Index->new( doc => $docname, phrase_doc => $phrase_docname);
$b->process_doc;

is( $b->doc_contents, $original_contents, 'Correct contents' );

my @pages = Book::Index::Page->select('order by page');
for my $p (0..$#pages) {
    is($pages[$p]->contents, $original_pages[$p], "Page " . ($p + 1) . " has correct contents");
}

my @words = map { $_->word } Book::Index::Word->select('order by word');
cmp_set([@words], [qw(this is page 1 2 about horses)], 'Correct words');

my @stems = map { $_->stem } Book::Index::Stem->select('order by stem');
cmp_set([@stems], [qw(this is page 1 2 about hors)], 'Correct stems');

all_done;

END { 
    Book::Index::Page->truncate;
    Book::Index::Word->truncate;
    Book::Index::Stem->truncate;
}