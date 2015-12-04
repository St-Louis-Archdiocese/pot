our $status = 0;

package Client;
use Mojo::IOLoop::Client;

sub run {
  my ($class, $message) = @_;
  return unless $message;
  my $client = Mojo::IOLoop::Client->new;
  $client->on(connect => sub {
    my ($client, $handle) = @_;
    $handle->write($message);
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

package Tx;
use Mojo::Base -base;

has 'object' => sub { Object->new };
has 'person' => sub { Person->new };

sub reset {
  my $self = shift;
  say "Resetting\n";
  $self->object->barcode('');
  $self->person->rfid('');
}

package Object;
use Mojo::Base -base;

has 'barcode';
has 'name';
has 'id';
has 'status';
has 'person';
has 'checkedout';
has 'returned';
has 'timestamp';

sub lookup {
  my $self = shift;
  return undef unless $self->barcode;
  printf "Looking up %s\n", $self->barcode;
  # Parse barcode
  # select *,(if returned is null, 0, 1) status from objects left join tx where id = barcode
  $self->name("Object");
  $self->id("Object ID");
  $self->status(++$status%2==0);
  $self->person("Person");
  $self->checkedout("CheckedOut");
  $self->returned("Returned");
  $self->timestamp(time);
  $self;
}

sub checkout {
  my ($self, $tx) = @_;
  return undef unless $self->barcode;
  printf "Checking out: %s by %s\n", $self->name, $tx->person->name;
  # insert into tx (object, person, checkout) values (name, name, now())
  $tx->reset;
}

sub Return {
  my ($self, $tx) = @_;
  return undef unless $self->barcode;
  printf "Returning: %s\n", $self->name;
  # update tx set returned=now() where object=object and returned is null
  $tx->reset;
}

sub timeout {
  my $self = shift;
  return undef unless $self->barcode;
  time - $self->timestamp > 15;
}

package Person;
use Mojo::Base -base;

has 'rfid';
has 'name';
has 'id';
has 'timestamp';

sub parse {
  my $self = shift;
  return undef unless $self->rfid;
  printf "Looking up %s\n", $self->rfid;
  # Parse rfid
  $self->name("Person");
  $self->id("Person ID");
  $self->timestamp(time);
  $self;
}

sub timeout {
  my $self = shift;
  return undef unless $self->rfid;
  time - $self->timestamp > 15;
}

package main;
use feature 'say';
use Mojo::Pg;
use Mojo::IOLoop;
use Mojo::IOLoop::Stream;

Client->run($ARGV[0]);

my $tx = Tx->new;
my $readable = Mojo::IOLoop::Stream->new(\*STDIN)->timeout(0);

Mojo::IOLoop->recurring($ENV{TICK} => sub {
  printf "Status\n  Barcode: %s\n  RFID: %s\n", $tx->object->barcode, $tx->person->rfid;
}) if $ENV{TICK};
Mojo::IOLoop->recurring(1 => sub {
  $tx->reset if $tx->object->timeout || $tx->person->timeout;
});

$readable->on(close => sub { Mojo::IOLoop->stop });
   
$readable->on(read => sub {
  my ($stream, $bytes) = @_;
  Mojo::IOLoop->next_tick(sub{
    my $loop = shift;
    chomp $bytes;
    my $object = $tx->object->barcode($bytes)->lookup;
    if ( $object->status ) {
      printf "Got Barcode: %s -- currently %s, last checked out by %s on %s until %s\n", $object->name, ($object->status?'IN':'OUT'), $object->person, $object->checkedout, $object->returned;
      $object->checkout($tx) if $tx->person->rfid;
    } else {
      printf "Got Barcode: %s -- currently %s, checked out by %s on %s\n", $object->name, ($object->status?'IN':'OUT'), $object->person, $object->checkedout;
      $object->Return($tx);
    }
  });
});
   
Mojo::IOLoop->server({port => 10001} => sub {
  my ($loop, $stream) = @_;
  $stream->on(read => sub {
    my ($stream, $bytes) = @_;
    chomp $bytes;
    my $person = $tx->person->rfid($bytes)->parse;
    printf "RFID: %s -- %s\n", $person->name, $person->id;
    $tx->object->checkout($tx) if $tx->object->barcode;
  });
});

# Start event loop if necessary
$readable->start;
Mojo::IOLoop->start unless Mojo::IOLoop->is_running;
