package Tx;
use Mojo::Base -base;
use Mojo::Loader qw(data_section find_modules load_class);

use DBM::Deep;

has db => sub { DBM::Deep->new("foo.db") };
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
    if ( my $regex = $module->regex($bytes => $self) ) {
      #printf "%s got %s\n", $module, ref $regex;
      if ( $regex->isa('Tx::Model::Object') ) {
        $self->object->lookup;
        if ( $self->object->checkedout ) {
          printf "%s: %s (%s) -- currently %s, checked out by %s on %s\n", $module, $self->object->name, $self->object->id, ($self->object->checkedout?'OUT':'IN'), $self->object->person, scalar localtime($self->object->checkedout);
          $self->object->Return;
        } else {
          printf "%s: %s (%s) -- currently %s, last checked out by %s on %s\n", $module, $self->object->name, $self->object->id, ($self->object->checkedout?'OUT':'IN'), $self->object->person, scalar localtime($self->object->checkedout);
          $self->object->checkout if $self->person->id;
        }
      } elsif ( $regex->isa('Tx::Model::Person') ) {
        $self->person->lookup;
        printf "%s: %s (%s)\n", $module, $self->person->name, $self->person->id;
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
  my ($self, $model) = @_;
  say join '', 'Resetting ', ref $model, "\n";
  $self->object(Tx::Model::Object->new(tx => $self)) if !$model || ref $model eq 'Tx::Model::Object';
  $self->person(Tx::Model::Person->new(tx => $self)) if !$model || ref $model eq 'Tx::Model::Person';
}

package Tx::Plugin::Person::Isonas;
use Mojo::Base -base;

sub regex {
  my ($self, $bytes, $tx) = @_;
  my @person = ();
  while ( $bytes =~ /<([^<>]+)>/g ) {
    local $_ = $1;
    s/\s+$//;
    push @person, $_;
  }
  return undef unless @person;
  if ( my ($date, $time, $action, $reader, $badge, $name, undef, undef, undef, undef, undef, undef, undef, undef, undef, undef, $guid) = @person ) {
    $tx->reset($tx->person);
    $tx->person->name($name);
    $tx->person->id($badge);
    return $tx->person;
  }
  return undef;
}

package Tx::Plugin::Person::Barcode;
use Mojo::Base -base;

sub regex {
  my ($self, $bytes, $tx) = @_;
  if ( $bytes =~ /^(\d+)$/ ) {
    $tx->reset($tx->person);
    $tx->person->id($1);
    return $tx->person;
  }
  return undef;
}

package Tx::Plugin::Object::Barcode;
use Mojo::Base -base;

sub regex {
  my ($self, $bytes, $tx) = @_;
  if ( $bytes =~ /^([a-z]+)$/ ) {
    $tx->reset($tx->object);
    $tx->object->id($1);
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

sub reset {
  my $self = shift;
  warn "Reset: ", $self->person->id;
  $self->person(Person->new);
}

sub lookup {}

package Tx::Model::Object;
use Mojo::Base 'Tx::Model';

use Data::Dumper;

has 'name' => '';
has 'person' => sub { {} };
has 'checkedout' => '';

sub lookup {
  my $self = shift;
  return undef unless $self->id;
  printf "Looking up %s\n", $self->id;
  $self->name($self->tx->db->{objects}->{$self->id}->{name}||'Unknown');
  $self->person($self->tx->db->{objects}->{$self->id}->{person}||'Unknown');
  $self->checkedout($self->tx->db->{objects}->{$self->id}->{checkedout}||0);
  $self;
}

sub checkout {
  my $self = shift;
  return undef unless $self->id;
  printf "Checking out: %s by %s\n", $self->name, $self->tx->person->name;
  $self->tx->db->{objects}->{$self->id}->{person} = {id => $self->tx->person->id, name => $self->tx->person->name};
  $self->tx->db->{objects}->{$self->id}->{checkedout} = time;
  $self->tx->reset;
}

sub Return {
  my $self = shift;
  return undef unless $self->id;
  printf "Returning: %s\n", $self->name;
  $self->tx->db->{objects}->{$self->id}->{checkedout} = undef;
  $self->tx->reset;
}

sub add {
  my ($self, $id, $name) = @_;
  $self->tx->db->{objects}->{$id} = {name => $name};
}

sub del {
  my ($self, $id) = @_;
  delete $self->tx->db->{objects}->{$id};
}

sub dump {
  my $self = shift;
  say Dumper($self->tx->db->{objects});
}

package Tx::Model::Person;
use Mojo::Base 'Tx::Model';

use Data::Dumper;

has 'name' => '';

package Tx::Command::object;
use Mojo::Base 'Mojolicious::Commands';

has description => 'Manipulate Object database';
has hint        => <<EOF;

See 'APPLICATION object help COMMANDS' for more information on a specific
command.
EOF
has message    => sub { "Commands:\n" };
has namespaces => sub { ['Tx::Command::object'] };

sub help { shift->run(@_) }

package Tx::Command::object::add;
use Mojo::Base 'Mojolicious::Command';

use Getopt::Long qw(GetOptionsFromArray :config no_auto_abbrev no_ignore_case);

has description => 'Add Object to database';

sub run {
  my ($self, @args) = @_;

  GetOptionsFromArray \@args,
    'n|name=s' => \(my $name = shift),
    'i|id=s' => \(my $id = shift);

  $self->app->tx->object->add($id, $name);
}

package Tx::Command::object::delete;
use Mojo::Base 'Mojolicious::Command';

use Getopt::Long qw(GetOptionsFromArray :config no_auto_abbrev no_ignore_case);

has description => 'Delete Object from database';

sub run {
  my ($self, @args) = @_;

  GetOptionsFromArray \@args,
    'i|id=s' => \(my $id = shift);

  $self->app->tx->object->del($id);
}

package Tx::Command::object::list;
use Mojo::Base 'Mojolicious::Command';

use Getopt::Long qw(GetOptionsFromArray :config no_auto_abbrev no_ignore_case);

has description => 'List Objects in database';

sub run {
  my ($self, @args) = @_;

  $self->app->tx->object->dump;
}

package Tx::Command::client;
use Mojo::Base 'Mojolicious::Commands';

has description => 'Act as a client and send commands to the server';
has hint        => <<EOF;

See 'APPLICATION client help CLIENTS' for more information on a specific
client.
EOF
has message    => sub { "Clients:\n" };
has namespaces => sub { ['Tx::Command::client'] };

sub help { shift->run(@_) }

package Tx::Command::client::isonas;
use Mojo::Base 'Mojolicious::Command';

use Mojo::IOLoop::Client;

has description => 'Send Isonas packet';

sub run {
  my ($self, $message, @args) = @_;
  die "No message provided\n" unless $message;
  my $client = Mojo::IOLoop::Client->new;
  $client->on(connect => sub {
    my ($client, $handle) = @_;
    $handle->write($message);
  });
  $client->on(error => sub {
    my ($client, $err) = @_;
    die "Error sending message: $err\n";
  });
  $client->connect(address => '127.0.0.1', port => 10001);

  # Start reactor if necessary
  $client->reactor->start unless $client->reactor->is_running;
}

package Tx::Command::server;
use Mojo::Base 'Mojolicious::Commands';

has description => 'Run a packet-receiving server';
has hint        => <<EOF;

See 'APPLICATION server help SERVERS' for more information on a specific
server.
EOF
has message    => sub { "Servers:\n" };
has namespaces => sub { ['Tx::Command::server'] };

sub help { shift->run(@_) }

package Tx::Command::server::isonas;
use Mojo::Base 'Mojolicious::Command';
use Mojo::IOLoop;

use Getopt::Long qw(GetOptionsFromArray :config no_auto_abbrev no_ignore_case);

has description => 'Start Isonas server';
has usage => sub { shift->extract_usage };

sub run {
  my ($self, @args) = @_;

  Mojo::IOLoop->server({port => 10001} => sub {
    my ($loop, $stream) = @_;
    $stream->on(read => sub {
      my ($stream, $bytes) = @_;
      app->tx->parse($bytes);
    });
  });
  Mojo::IOLoop->start unless Mojo::IOLoop->is_running;
}

package main;
use Mojolicious::Lite;
use Mojo::IOLoop;
use Mojo::IOLoop::Stream;
use Mojolicious::Commands;
@{app->commands->namespaces} = ('Tx::Command');

use Getopt::Long qw(GetOptionsFromArray :config no_auto_abbrev no_ignore_case);

helper tx => sub { Tx->new };

my $readable = Mojo::IOLoop::Stream->new(\*STDIN)->timeout(0);
$readable->on(close => sub { Mojo::IOLoop->stop });
$readable->on(read => sub {
  my ($stream, $bytes) = @_;
  Mojo::IOLoop->next_tick(sub{
    my $loop = shift;
    app->tx->parse($bytes);
  });
});
$readable->start;

Mojo::IOLoop->recurring($ENV{TICK} => sub {
  printf "Status\n  Object: %s\n  Person: %s\n", app->tx->object->id, app->tx->person->id;
}) if $ENV{TICK};

Mojo::IOLoop->recurring(1 => sub {
  app->tx->reset if app->tx->object->timeout || app->tx->person->timeout;
});

app->start;
