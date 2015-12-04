our $status = 0;

package Tx;
use Mojo::Base -base;

has 'book';
has 'person';

sub reset {
  my $self = shift;
  $self->book(undef);
  $self->person(undef);
}

package Book;
use Mojo::Base -base;

has 'barcode';
has 'title';
has 'status';
has 'person';
has 'checkedout';
has 'returned';

sub lookup {
  my $self = shift;
  printf "Looking up %s\n", $self->barcode;
  # Parse barcode
  # select *,(if returned is null, 0, 1) status from books left join tx where id = barcode
  $self->title("Title");
  $self->status(++$status%2==0);
  $self->person("Who");
  $self->checkedout("CheckedOut");
  $self->returned("Returned");
  $self;
}

sub checkout {
  my ($self, $tx) = @_;
  printf "Checkout: %s by %s\n", $self->title, $tx->person->name;
  # insert into tx (book, person, checkout) values (title, name, now())
  $tx->reset;
}

sub Return {
  my ($self, $tx) = @_;
  printf "Return: %s\n", $self->title;
  # update tx set returned=now() where book=book and returned is null
  $tx->reset;
}

package Person;
use Mojo::Base -base;

has 'rfid';
has 'name';
has 'id';
has 'timestamp';

sub parse {
  my $self = shift;
  printf "Looking up %s\n", $self->rfid;
  # Parse rfid
  $self->name("Name");
  $self->id("ID");
  $self->timestamp("Timestamp");
  $self;
}

package main;
use feature 'say';
use Mojo::IOLoop;
use Mojo::IOLoop::Stream;
use Mojo::IOLoop::Client;

if ( $ARGV[0] ) {
  # Create socket connection
  my $client = Mojo::IOLoop::Client->new;
  $client->on(connect => sub {
    my ($client, $handle) = @_;
    $handle->write($ARGV[0]);
    #...
  });
  $client->on(error => sub {
    my ($client, $err) = @_;
    #...
  });
  $client->connect(address => '127.0.0.1', port => 10001);

  # Start reactor if necessary
  $client->reactor->start unless $client->reactor->is_running;

  exit;
}

my $tx = Tx->new;
Mojo::IOLoop->recurring($ENV{TICK} => sub { warn "tick\n" }) if $ENV{TICK};
my $readable = Mojo::IOLoop::Stream->new(\*STDIN)->timeout(0);

$readable->on(close => sub {
  my ($stream) = @_;
  Mojo::IOLoop->stop;
});
   
$readable->on(read => sub {
  my ($stream, $bytes) = @_;
  Mojo::IOLoop->next_tick(sub{
    my $loop = shift;
    chomp $bytes;
    $tx->book(my $book = Book->new(barcode => $bytes)->lookup);
    if ( $book->status ) {
      printf "Barcode (%s): %s -- last checked out by %s on %s until %s\n", ($book->status?'IN':''), $book->title, $book->person, $book->checkedout, $book->returned;
      $book->checkout($tx) if $tx->person;
    } else {
      printf "Barcode (%s): %s -- currently checked out by %s on %s\n", ($book->status?'':'OUT'), $book->title, $book->person, $book->checkedout;
      $book->Return($tx);
    }
  });
});
   
Mojo::IOLoop->server({port => 10001} => sub {
  my ($loop, $stream) = @_;
  $stream->on(read => sub {
    my ($stream, $bytes) = @_;
    chomp $bytes;
    $tx->person(my $person = Person->new(rfid => $bytes)->parse);
    printf "RFID: %s -- %s\n", $person->name, $person->id;
    $tx->book->checkout($tx) if $tx->book;
  });
});

# Start event loop if necessary
$readable->start;
Mojo::IOLoop->start unless Mojo::IOLoop->is_running;
