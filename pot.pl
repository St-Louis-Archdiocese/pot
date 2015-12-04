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
use Mojo::Loader qw(data_section find_modules load_class);

use Data::Dumper;

has pg => sub { Mojo::Pg->new };
has object => sub { Tx::Model::Object->new(tx => shift) };
has person => sub { Tx::Model::Person->new(tx => shift) };
has plugins => sub { [qw/Person::Isonas Person::Barcode Object::Barcode/] };

sub parse {
  my ($self, $bytes) = @_;
  chomp $bytes;
  return undef unless $bytes;
  printf "Parsing %s\n", $bytes;
  for my $module ( @{$self->plugins}, find_modules 'Tx::Plugin' ) {
    if ( $module =~ /^Tx::Plugin/ ) {
      my $e = load_class $module;
      warn qq{Loading "$module" failed: $e} and next if ref $e;
    } else {
      $module = "Tx::Plugin::$module";
    }
#warn "!!! $module\n";
    if ( my $regex = $module->regex($bytes => $self) ) {
      printf "%s got %s\n", $module, ref $regex;
      if ( $regex->isa('Tx::Model::Object') ) {
        $self->object->lookup;
        if ( $self->object->status ) {
          printf "Got %s: %s -- currently %s, last checked out by %s on %s until %s\n", $module, $self->object->name, ($self->object->status?'IN':'OUT'), $self->object->person, $self->object->checkedout, $self->object->returned;
          $self->object->checkout if $self->person->id;
        } else {
          printf "Got %s: %s -- currently %s, checked out by %s on %s\n", $module, $self->object->name, ($self->object->status?'IN':'OUT'), $self->object->person, $self->object->checkedout;
          $self->object->Return;
        }
      } elsif ( $regex->isa('Tx::Model::Person') ) {
        $self->person->lookup;
        printf "%s: %s -- %s\n", $module, $self->person->name, $self->person->id;
        $self->object->checkout if $self->object->id;
      } else {
        say "Unknown input";
      }
      return $regex;
    }
  }
  say "Invalid input";
  $self;
}

sub reset {
  my $self = shift;
  say "Resetting\n";
  $self->object(Tx::Model::Object->new(tx => $self));
  $self->person(Tx::Model::Person->new(tx => $self));
}

package Tx::Plugin::Person::Isonas;
use Mojo::Base -base;

sub regex {
  my ($self, $bytes, $tx) = @_;
  if ( $bytes =~ /^<\d+>$/ ) {
    $tx->person->name("Person");
    $tx->person->id("Person ID");
    return $tx->person;
  }
  return undef;
}

package Tx::Plugin::Person::Barcode;
use Mojo::Base -base;

sub regex {
  my ($self, $bytes, $tx) = @_;
  if ( $bytes =~ /^\d+$/ ) {
    $tx->person->id("Person ID");
    return $tx->person;
  }
  return undef;
}

package Tx::Plugin::Object::Barcode;
use Mojo::Base -base;

sub regex {
  my ($self, $bytes, $tx) = @_;
  if ( $bytes =~ /^[a-z]+$/ ) {
    $tx->object->id("Person ID");
    return $tx->object;
  }
  return undef;
}

package Tx::Model;
use Mojo::Base -base;

has 'tx';
has 'id';
has 'timestamp' => sub { time };

sub timeout {
  my $self = shift;
  return undef unless $self->id;
  time - $self->timestamp > 15;
}

sub lookup {}

package Tx::Model::Object;
use Mojo::Base 'Tx::Model';

has 'name' => '';
has 'status' => '';
has 'person' => sub { Tx::Model::Person->new(tx => shift->tx) };
has 'checkedout' => '';
has 'returned' => '';

sub lookup {
  my $self = shift;
  return undef unless $self->id;
  printf "Looking up %s\n", $self->id;
  # select *,(if returned is null, 0, 1) status from objects left join tx where id = barcode
  $self->name("Object");
  $self->status(++$status%2==0);
  $self->person("Person");
  $self->checkedout("CheckedOut");
  $self->returned("Returned");
  $self;
}

sub checkout {
  my $self = shift;
  return undef unless $self->id;
  printf "Checking out: %s by %s\n", $self->name, $self->tx->person->name;
  # insert into tx (object, person, checkout) values (name, name, now())
  $self->tx->reset;
}

sub Return {
  my $self = shift;
  return undef unless $self->id;
  printf "Returning: %s\n", $self->name;
  # update tx set returned=now() where object=object and returned is null
  $self->tx->reset;
}

package Tx::Model::Person;
use Mojo::Base 'Tx::Model';

has 'name' => '';

package main;
use feature 'say';
use Mojo::Pg;
use Mojo::IOLoop;
use Mojo::IOLoop::Stream;

Client->run($ARGV[0]);

my $tx = Tx->new;
my $readable = Mojo::IOLoop::Stream->new(\*STDIN)->timeout(0);

$readable->on(close => sub { Mojo::IOLoop->stop });
   
$readable->on(read => sub {
  my ($stream, $bytes) = @_;
  Mojo::IOLoop->next_tick(sub{
    my $loop = shift;
    $tx->parse($bytes);
  });
});
   
Mojo::IOLoop->server({port => 10001} => sub {
  my ($loop, $stream) = @_;
  $stream->on(read => sub {
    my ($stream, $bytes) = @_;
    $tx->parse($bytes);
  });
});

Mojo::IOLoop->recurring($ENV{TICK} => sub {
  printf "Status\n  Object: %s\n  Person: %s\n", $tx->object->id, $tx->person->id;
}) if $ENV{TICK};

Mojo::IOLoop->recurring(1 => sub {
  $tx->reset if $tx->object->timeout || $tx->person->timeout;
});

# Start event loop if necessary
$readable->start;
Mojo::IOLoop->start unless Mojo::IOLoop->is_running;
