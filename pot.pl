package Tx;
use Mojo::Base -base;
use Mojo::Loader qw(find_modules load_class);

use DBM::Deep;

has db => sub { DBM::Deep->new("foo.db") };
has object => sub { Tx::Model::Object->new(tx => shift) };
has person => sub { Tx::Model::Person->new(tx => shift) };
has plugins => sub { [qw/Person::Isonas Person::Barcode Object::Barcode/] };

sub parse {
  my ($self, $bytes) = @_;
  chomp $bytes;
  return undef unless $bytes;
  #printf "Parsing %s\n", $bytes;
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
        if ( $self->object->checkedout ) {
          printf "%s: %s (%s) -- currently OUT, checked out by %s on %s\n", $module, $self->object->name, $self->object->id, $self->object->person, scalar localtime($self->object->checkedout);
          $self->object->Return;
        } else {
          printf "%s: %s (%s) -- currently IN\n", $module, $self->object->name, $self->object->id;
          $self->object->checkout if $self->person->id;
        }
      } elsif ( $regex->isa('Tx::Model::Person') ) {
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
  say join '', 'Resetting ', ref $model, "\n" if $ENV{DEBUG} || ! ref $model;
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
    $tx->person->name("Name $1");
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
has 'id' => '';
has 'timestamp' => sub { time };

sub timeout {
  my $self = shift;
  return undef unless $self->id;
  time - $self->timestamp > 15;
}

sub set {
  my ($self, $id, %data) = @_;
  $self->tx->db->{$self->_table}->{$id} = {%data};
}

sub del {
  my ($self, $id) = @_;
  delete $self->tx->db->{$self->_table}->{$id};
}

sub get {
  my ($self, $id) = @_;
  if ( $id ) {
    $self->tx->db->{$self->_table}->{$id};
  } else {
    $self->tx->db->{$self->_table};
  }
}

sub fetch {
  my $self = shift;
  return {} unless $self->id;
  $self->get($self->id);
}

sub _table {
  my $self = shift;
  my $table = lc(ref $self);
  $table =~ /::(\w+)$/;
  $1;
}

package Tx::Model::Object;
use Mojo::Base 'Tx::Model';

sub name { shift->fetch->{name} || 'Unknown' }
sub person { shift->fetch->{person}->{name} || 'Unknown' }
sub checkedout { shift->fetch->{checkedout} || 0 }

sub checkout {
  my $self = shift;
  return undef unless $self->id;
  printf "Checking out: %s by %s\n", $self->name, $self->tx->person->name;
  $self->fetch->{person} = {id => $self->tx->person->id, name => $self->tx->person->name};
  $self->fetch->{checkedout} = time;
  $self->log;
  $self->tx->reset;
}

sub Return {
  my $self = shift;
  return undef unless $self->id;
  printf "Returning: %s\n", $self->name;
  $self->fetch->{checkedout} = undef;
  $self->log;
  $self->tx->reset;
}

sub log {
  my $self = shift;
  if ( $self->checkedout ) {
    push @{$self->tx->db->{log}}, sprintf "< %s -- %s (%s) -- %s (%s)", scalar localtime($self->checkedout), $self->name, $self->id, $self->person, $self->fetch->{person}->{id};
  } else {
    push @{$self->tx->db->{log}}, sprintf "> %s -- %s (%s) -- %s (%s)", scalar localtime, $self->name, $self->id, $self->person, $self->fetch->{person}->{id};
  }
}

package Tx::Model::Person;
use Mojo::Base 'Tx::Model';

has 'name' => sub { shift->fetch->{name} };

package Tx::Command::log;
use Mojo::Base 'Mojolicious::Command';

use Data::Dumper;

has description => 'Show transaction log';

sub run {
  my $log = shift->app->tx->db->{log};
  say for @$log;
}

package Tx::Command::clearlog;
use Mojo::Base 'Mojolicious::Command';

use Data::Dumper;

has description => 'Show transaction log';

sub run { delete shift->app->tx->db->{log} }

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
  my ($self, $id, @args) = @_;

  my %data;
  my @args1;
  while ( $_ = shift @args ) {
    push @args1, $_ and next unless s/^--//;
    $data{$_} = shift @args;
  }
  $self->app->tx->object->set($id, %data);
}

package Tx::Command::object::delete;
use Mojo::Base 'Mojolicious::Command';

use Getopt::Long qw(GetOptionsFromArray :config no_auto_abbrev no_ignore_case);

has description => 'Delete Object from database';

sub run {
  my ($self, $id, @args) = @_;

  $self->app->tx->object->del($id);
}

package Tx::Command::object::list;
use Mojo::Base 'Mojolicious::Command';

use Data::Dumper;

has description => 'List Objects in database';

sub run { say Dumper(shift->app->tx->object->get) }

package Tx::Command::object::status;
use Mojo::Base 'Mojolicious::Command';

has description => 'Show Object status';

sub run {
  my ($self, $id) = @_;
  $self->app->tx->object->id($id);
  my $object = $self->app->tx->object;
  if ( my $status = $object->checkedout ) {
    printf "%s is currently unavailable. It was checked out %s by %s\n", $object->name, scalar localtime($object->checkedout), $object->person;
  } else {
    printf "%s is currently available. It was last checked out by %s\n", $object->name, $object->person;
  }
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
    exit;
  });
  $client->on(error => sub {
    my ($client, $err) = @_;
    die "Error sending message: $err\n";
  });
  $client->connect(address => '127.0.0.1', port => 10001);

  # Start reactor if necessary
  $client->reactor->start unless $client->reactor->is_running;

  exit;
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
      $self->app->tx->parse($bytes);
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

use Term::ReadKey;
ReadMode('noecho');

my $tx = Tx->new;

my $readable = Mojo::IOLoop::Stream->new(\*STDIN)->timeout(0);
$readable->on(close => sub { ReadMode('normal'); Mojo::IOLoop->stop });
$readable->on(read => sub {
  my ($stream, $bytes) = @_;
  Mojo::IOLoop->next_tick(sub{
    my $loop = shift;
    $tx->parse($bytes);
  });
});
$readable->start;

helper tx => sub { $tx };

Mojo::IOLoop->recurring($ENV{TICK} => sub {
  printf "Status\n  Object: %s\n  Person: %s\n", app->tx->object->id, app->tx->person->id;
}) if $ENV{TICK};

Mojo::IOLoop->recurring(1 => sub {
  app->tx->reset if app->tx->object->timeout || app->tx->person->timeout;
});

app->start;
