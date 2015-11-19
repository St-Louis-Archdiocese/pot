#!/usr/bin/perl -w

use strict;
use Getopt::Long;
Getopt::Long::Configure ("bundling");
use Sys::Syslog qw(:DEFAULT setlogsock);
use Date::Manip;
use MIME::Base64;
use Net::MAC;
use Net::LDAP;
use Net::LDAP::Entry;
use File::Basename;
use MIME::Base64;
use Lingua::EN::NameCase;
use Lingua::EN::NameParse;
#use Lingua::EN::MatchNames;
use Tkx qw(MainLoop destroy);
use Win32::Sound;
use Win32::API;

my $server = 'ldap.borgia.com'; # netserv. -or- ldap.borgia.com;
my $syslogsrv = '172.16.254.5';

my ($console, $window, $content, $lab, $output, $scroll, $input, $override);
my ($login, $l_content, $l_server, $l_user, $l_pass);
my ($popup, $p_content, $p_message, $p_entry, $phase);
my ($syslog, $glb_echo, $behalf, $multiple);
my ($argv, $progpath, $config, $echo, $pictures, $picturedir, $pictureurl, $passwordfile, $password, $auth, $autocheckin, $showauth, $help, $bind, $binddn);
my (@authorized);
my ($authorizer, $localDevice, $bio);
my (%authorizer, %localDevice, %bio);
my ($name, $ldap, $bin);
my $lastinput;

$|=1;
Date_Init('TZ=EST5EDT'); # Needed for Windows
$syslog = 'info|local5';
# Configure syslog and logrotate:
#   /etc/syslog.conf:
#     local6.*                                                -/var/log/fss.log
#   /etc/logrotate.d/syslog:
#     /var/log/fss.log {\nsharedscripts\nrotate 5\nweekly\npostrotate\n/usr/bin/killall -HUP syslogd #\nendscript\n}

setlogsock('udp', $syslogsrv);
openlog(basename($0), 'ndelay', 'local5');

$argv = join ' ', @ARGV; $argv =~ s/(\s*-w\s+)\S+(.*?)/$1$2/;
message(0, "Start options: $argv");

$SIG{'INT'} = sub {
	message(2, 'Control-C interrupt exit.', 'Reload');
	exit 0;
};

# draw over everything else (including the taskbar) by default (toggle with F11)?
$override = 1;

$progpath = dirname $0;
$config = "$progpath/fss.conf";
$config = '/etc/fss.conf' unless -f $config && -r _;
$config = '' unless -f $config && -r _;
$echo = 0;
$pictures = 0;
$picturedir = '/data/vhosts/webspeedpics.borgia.com/htdocs/skywardpictures';
$pictureurl = 'http://webspeedpics.borgia.com/skywardpictures';
$passwordfile = $ENV{PASSFILE} if defined $ENV{PASSFILE} && -r $ENV{PASSFILE};
$password = '';
$auth = 0;
$autocheckin = 1;
$showauth = 0;
$behalf = 1;
$help = 0;
$binddn = "$ENV{LDAPUSER},$ENV{BASEDN}";
$multiple = 0;

$passwordfile = '' if (!defined($passwordfile));

GetOptions(
	'help|h' => sub { $help = 1 },
	'config|c' => sub { $config = 1 },
	'echo|e' => sub { $echo = 1 },
	'multiple|m' => sub { $multiple = 1 },
	'auth|a' => sub { $auth = 1 },
	'autocheckin|C' => sub { $autocheckin = 0 },
	'showauth|A' => sub { $showauth = 1 },
	'behalf|b' => sub { $behalf = 0 },
	'pictures|p' => sub { $pictures = 1 },
	'picturedir|P=s' => \$picturedir,
	'pictureurl|U=s' => \$pictureurl,
	'binddn|D=s' => \$binddn,
	'password|w=s' => \$password,
	'passwordfile|W=s' => \$passwordfile,
);
die <<DIE if $help;
Usage: $0 [OPTIONS]
	-h:	Display this help message and exit
	-c:	FSS Config file (Default: $config)
	-e:	Display keyboard input (Default: hide)
	-m:	Allow multiple rentals (Default: disallow)
	-a:	Require transaction authorization (Default: skip)
	-C:	Allow auto-checkin (Default: disallow)
	-A:	Show authorized transactors and exit
	-b:	Do not allow returns on behalf of another (Default: allow)
	-p:	Display URL to user's picture (Default: skip)
	-P:	Linux path to pictures (Default: $picturedir)
	-U:	Base URL to pictures (Default: $pictureurl)
	-D:	Bind DN (Default: $binddn)
	-w:	LDAP Manager password
	-W:	File containing LDAP Manager password (Default: $passwordfile)
DIE
$glb_echo = $echo == 1 ? 'normal' : 'noecho';	# If barcode/bio problems, run in echo mode and the admin can key the data in using the keyboard

@authorized = authorized($config);
message(1, @authorized) if $showauth;

%authorizer = ();
%localDevice = ();
%bio = ();

# Create the project window
$window = Tkx::widget->new('.');
$window->g_wm_title('FSS - Fingerprint/Serial Number entry');
$window->g_wm_minsize(300, 200);

# Let's make it full-screen...
$window->g_wm_overrideredirect($override);
$window->g_wm_state('zoomed');

$content = $window->new_ttk__frame(-borderwidth => 5, -relief => 'sunken');

# Output controls
$content->g_grid(-column => 0, -row => 0, -sticky => 'nsew');
$output = $content->new_text(-wrap => 'word', -padx => 5, -pady => 5, -background => 'white');
$output->g_grid(-column => 0, -row => 0, -columnspan => 9, -ipadx => 5, -ipady => 5, -sticky => 'nsew');

$scroll = $content->new_ttk__scrollbar(-orient => 'vertical', -command => [$output, 'yview']);
$scroll->g_grid(-column => 9, -row => 0, -sticky => "ns");
$output->configure(-yscrollcommand => [$scroll, 'set']);

# Input controls
$input = $content->new_entry();
$input->g_grid(-column => 0, -row => 1, -columnspan => 8, -sticky => 'nsew');
$content->new_button(-text => "OK", -default => 'active', -command => \&click)->g_grid(-column => 8, -row => 1, -columnspan => 2, -sticky => 'nsew');

# First row of command buttons...
$content->new_ttk__label(-text => "Reports:")->g_grid(-column => 0, -row => 2, -columnspan => 1);
$content->new_button(-text => "Registered", -command => sub { report(special=>'QUERY003'); })->g_grid(-column => 1, -row => 2, -columnspan => 2, -sticky => 'nsew');
$content->new_button(-text => "Checked Out", -command => sub { report(special=>'QUERY002'); })->g_grid(-column => 3, -row => 2, -columnspan => 2, -sticky => 'nsew');
$content->new_button(-text => "> 90 minutes", -command => sub { report(special=>'QUERY001'); })->g_grid(-column => 5, -row => 2, -columnspan => 2, -sticky => 'nsew');
$content->new_button(-text => "By Username", -command => sub { report(special=>'QUERY005'); })->g_grid(-column => 7, -row => 2, -columnspan => 3, -sticky => 'nsew');

# Second row of command buttons...
$content->new_ttk__label(-text => "Controls:")->g_grid(-column => 0, -row => 3, -columnspan => 1);
$content->new_button(-text => "Find Username", -command => sub { report(special=>'QUERY004'); })->g_grid(-column => 1, -row => 3, -columnspan => 2, -sticky => 'nsew');
$content->new_button(-text => "Reset Auditing", -command => \&ResetAuditing)->g_grid(-column => 3, -row => 3, -columnspan => 2, -sticky => 'nsew');
$content->new_button(-text => "Clear Screen", -command => sub { $output->delete('1.0','end'); })->g_grid(-column => 5, -row => 3, -columnspan => 2, -sticky => 'nsew');
$content->new_button(-text => "Quit", -command => sub { $window->g_destroy(); })->g_grid(-column => 7, -row => 3, -columnspan => 3, -sticky => 'nsew');

# Respond to the enter key...
$window->g_bind("<Return>", \&click);

# The F11 key (full-screen/windowed)...
$window->g_bind("<F11>" => sub { $override = ($override) ? 0 : 1; $window->g_wm_overrideredirect($override); if ($override) { $window->g_wm_state('zoomed'); } });

# And the scroll wheel on the mouse...
$input->g_bind('<MouseWheel>' => [ sub { my ($d) = @_; $output->m_yview('scroll', ($d < 0) ? 1 : -1, 'units'); }, Tkx::Ev("%D") ]);

# Set up text colors for special notices...
$output->tag_configure('red', -foreground => 'red', -font => 'Helvetica 12 bold');
$output->tag_configure('blue', -foreground => 'blue', -font => 'Helvetica 12 bold');
$output->tag_configure('green', -foreground => 'green', -font => 'Helvetica 12 bold');
$output->tag_configure('yellow', -foreground => 'yellow', -font => 'Helvetica 12 bold');

# Sort them into a workable order on the screen:
$window->g_grid_columnconfigure(0, -weight => 1);
$window->g_grid_rowconfigure(0, -weight => 1);
$content->g_grid_columnconfigure(0, -weight => 1);
$content->g_grid_columnconfigure(1, -weight => 1);
$content->g_grid_columnconfigure(2, -weight => 1);
$content->g_grid_columnconfigure(3, -weight => 1);
$content->g_grid_columnconfigure(4, -weight => 1);
$content->g_grid_columnconfigure(5, -weight => 1);
$content->g_grid_columnconfigure(6, -weight => 1);
$content->g_grid_columnconfigure(7, -weight => 1);
$content->g_grid_columnconfigure(8, -weight => 1);
$content->g_grid_rowconfigure(0, -weight => 1);

# If we don't have a username/password, prompt for one graphically...
sub createlogin() {
	$login = $window->new_toplevel();
	$login->g_wm_title('FSS - LDAP server login');
	$login->g_wm_attributes(-topmost => 1);
	$login->g_wm_resizable(0, 0);

	$l_content = $login->new_ttk__frame(-borderwidth => 5, -relief => 'sunken');
	$l_content->g_grid(-column => 0, -row => 0, -sticky => 'nsew');

	$l_content->new_ttk__label(-text => "\nUnable to log in. Please enter your LDAP credentials below.\n")->g_grid(-column => 0, -row => 0, -columnspan => 4);

#	$l_content->new_ttk__label(-text => "Base DN:")->g_grid(-column => 0, -row => 1);
	$l_server = $l_content->new_entry();
#	$l_server->g_grid(-column => 1, -row => 1, -columnspan => 3, -sticky => 'nsew');
	$l_server->m_insert('end', "dc=borgia,dc=com" || $ENV{BASEDN});

#	$l_content->new_ttk__label(-text => "User:")->g_grid(-column => 0, -row => 2);
	$l_user = $l_content->new_entry();
#	$l_user->g_grid(-column => 1, -row => 2, -columnspan => 3, -sticky => 'nsew');
	$l_user->m_insert('end', "uid=fss,ou=People" || $ENV{LDAPUSER});

	$l_content->new_ttk__label(-text => "Password:")->g_grid(-column => 0, -row => 3);
	$l_pass = $l_content->new_entry(-show => '*');
	$l_pass->g_grid(-column => 1, -row => 3, -columnspan => 3, -sticky => 'nsew');

	$l_content->new_button(-text => "OK", -default => 'active', -command => \&login)->g_grid(-column => 1, -row => 4, -sticky => 'nsew');
	$l_content->new_button(-text => "Quit", -command => sub { $window->g_destroy(); })->g_grid(-column => 2, -row => 4, -sticky => 'nsew');

	$login->g_bind("<Return>", \&login);
	$login->g_bind("<Escape>", sub { $window->g_destroy(); });

	$login->g_grab();
	$login->g_raise();
	if ($ENV{BASEDN} eq '') {
		$l_server->g_focus();
	} elsif ($ENV{LDAPUSER} eq '') {
		$l_user->g_focus();
	} else {
		$l_pass->g_focus();
	}
}

# If we don't have a username/password, prompt for one graphically...
sub extrainput {
	# Create a new popup window
	$popup = $window->new_toplevel();
	$popup->g_wm_title('FSS - More Data Required');
	$popup->g_wm_attributes(-topmost => 1);
	$popup->g_wm_resizable(0, 0);
	$popup->g_grab();

	# Grid to place everything in
	$p_content = $popup->new_ttk__frame(-borderwidth => 5, -relief => 'sunken');
	$p_content->g_grid(-column => 0, -row => 0, -sticky => 'nsew');

	# Show the prompt text at the top
	$p_message = $p_content->new_ttk__label(-text => "\n".$_[0]."\n")->g_grid(-column => 0, -row => 0, -columnspan => 4);

	# A text entry box...
	$p_entry = $p_content->new_entry();
	$p_entry->g_grid(-column => 0, -row => 1, -columnspan => 4, -sticky => 'nsew');

	# And our two buttons to cancel the operation or continue
	$p_content->new_button(-text => "OK", -default => 'active', -command => \&phasetwo)->g_grid(-column => 1, -row => 2, -sticky => 'nsew');
	$p_content->new_button(-text => "Cancel", -command => sub { $phase = ''; $popup->g_destroy(); })->g_grid(-column => 2, -row => 2, -sticky => 'nsew');

	# Focus the text entry box
	$p_entry->g_focus();

	# Set up keyboard shortcuts
	$popup->g_bind("<Return>", \&phasetwo);
	$popup->g_bind("<Escape>", sub { $phase = ''; $popup->g_destroy(); });

	# Print the user prompt to the main screen too...
	p($_[0]);
}

# Attempt to log in to LDAP. If we fail, send the user to a login popup...
sub login {
	if (defined($login)) {
		$ENV{BASEDN} = $l_server->m_get();
		$ENV{LDAPUSER} = $l_user->m_get();
		$binddn = "$ENV{LDAPUSER},$ENV{BASEDN}";
		$password = $l_pass->m_get();
	}

	$name = new Lingua::EN::NameParse(auto_clean=>1, force_case=>1, lc_prefix=>1, initials=>1, allow_reversed=>1, joint_names=>0, extended_titles=>0);
	$ldap = Net::LDAP->new($server, version => 3);
	$bind = $ldap->bind($binddn, password=>bindpw($password, $passwordfile));
	message($bind->code ? (2, "Invalid DN and/or password: $binddn") : (0, "Successful bind: $binddn"));

	if ($bind->is_error) {
		p($bind->error."\n");

		if (!defined($login)) {
			createlogin();
		}
	} else {
		undef $password; undef $passwordfile;
		if (defined($login)) {
			$login->g_destroy();
		}

		p(<<WELCOME);
This program expects pairs of information.  One part is a human fingerprint
while the other is a computer serial number.  It does not matter in which order
the data is entered; however, when a pair is received, the order is immediately
logged and processed.
An audible "beep" means that the person's fingerprint was not read properly or
the person has not been enrolled in the system.
===============================================================================
WELCOME
		$output->m_insert_end("Testing color...\n", 'blue');
		p("OK\n");
		p(<<ECHO) if $glb_echo eq 'normal';
Running in keyboard entry mode!
To enter a fingerprint: FSSusernameFSS
To enter a device: just:type:in:the:serial:number
To see status info of current input: <Enter>
ECHO
		p("\n");
		report();

		$input->g_focus();
		$window->g_raise();
	}
}

sub phasetwo {
	$_ = $p_entry->m_get();
	$p_entry->delete('0','end');
	p("Input: $_\n");

	if ($phase eq 'need_authorization') {
		# Bio input
		if ( /^FSS(.*?)FSS$/ ) {
			$authorizer = $1;
			message(0, "Got FSS Biometric input for authorizer: $authorizer");
			if ( grep { /^$authorizer$/ } @authorized ) {
				$ENV{LDAPOPERATION} = '&';
				%authorizer = getbio($authorizer);
				delete $ENV{LDAPOPERATION};
				if ( scalar keys %authorizer == 0 ) {
					message(2, "$authorizer not found in LDAP!", "Authorizer not found in LDAP!  Do not allow person to check-out any devices until this problem has been resolved.");
					clearinput(qw{authorizer bio localDevice});
				} elsif ( scalar keys %authorizer == 1 ) {
					%authorizer = %{$authorizer{0}};
					my $authorizedby = expanduid($authorizer{uid});
					message(2, "Transaction authorized by $authorizedby.");
				} elsif ( scalar keys %authorizer > 1 ) {
					message(2, "Multiple entries for authorizer=$authorizer found in LDAP!", "Multiple entries for authorizer found in LDAP!  Do not allow person to check-out any devices until this problem has been resolved.");
					clearinput(qw{authorizer bio localDevice});
				} else {
					message(1, "ERROR");
				}
			} else {
				message(2, "$authorizer not authorized", "You are not authorized to authorize this transaction.  Do not allow person to check-out any devices until this problem has been resolved.");
				clearinput(qw{authorizer bio localDevice});
			}
		# Anything else is not accepted
		} else {
			message(2, "Invalid authorization biometric input", "This is not a valid biometric input.  Do not allow person to check-out any devices until this problem has been resolved.");
			clearinput(qw{authorizer bio localDevice});
		}

		# Here it is!  Check it in or out.
		if ( !$auth || $authorizer ) {
			if ( $localDevice{CheckInTimeStamp} && $localDevice{CheckOutTimeStamp} ) {
				if ( Date_Cmp($localDevice{CheckInTimeStamp}, $localDevice{CheckOutTimeStamp}) > 0 ) {
					checkout(\%bio, \%localDevice);
				} elsif ( Date_Cmp($localDevice{CheckInTimeStamp}, $localDevice{CheckOutTimeStamp}) < 0 ) {
					checkin(\%bio, \%localDevice);
				} else {
					message(2, "Too fast!!  Try again!");
				}
			} elsif ( $localDevice{CheckInTimeStamp} && !$localDevice{CheckOutTimeStamp} ) {
				checkout(\%bio, \%localDevice);
			} elsif ( !$localDevice{CheckInTimeStamp} && $localDevice{CheckOutTimeStamp} ) {
				checkin(\%bio, \%localDevice);
			} else {
				checkout(\%bio, \%localDevice);
			}
			clearinput(qw{authorizer bio localDevice});
		}
	} elsif ($phase eq 'report_4') {
		if ( my @ul = Ul($_) ) {
			p("Best guess: ".join(', ', @ul)."\n");
		} else {
			p("No matches.\n");
		}
	} elsif ($phase eq 'report_5') {
		p(pl($_)."\n");
	}

	$popup->g_destroy();
	$window->g_raise();
	$input->g_focus();

	$phase = '';
}

# Prompt for the DN, username and password if any are missing
undef $login;
if (($binddn =~ /^,|,$/) || (($password eq '') && ($passwordfile eq ''))) {
	createlogin();
# If we already have a password, attempt to log in
} else {
	login();
}

# Hide the console window and start the main program loop
Win32::API->new('kernel32', 'FreeConsole', [], 'I')->Call();
$lastinput = '';
$phase = '';
MainLoop();

# Clean up...
closelog();

sub click {
	p("\n") if !$bio && !$localDevice;
	$_ = input();

	#return if ($_ eq '');

	# Still waiting for a matching pair
	if ( !($bio && $localDevice) ) {
		# No input, i.e. press Enter
		# Show status
		if ( /^\s*$/ || /^0+$/ || /^(S0+\d+)$/ || /^(QUERY\d+)$/ ) {
			if ( $bio ) {
				report(bio=>$bio);
			} elsif ( $localDevice ) {
				report(localDevice=>$localDevice);
			} elsif ( $1 ) {
				report(special=>$1);
			} else {
				report();
			}
			$lastinput = '';
			clearinput(qw{authorizer bio localDevice});
		# Exit the fss.sh while loop.
		# Complete exit.
		} elsif ( /^1+$/ ) {
			message(2, "Exit.");
			exit 1;
		# Clear auditing attributes for $localDevice
		} elsif ( /^D{10,}$/i ) {
			ResetAuditing();
		# Clear Screen
		} elsif ( /^L{1,}$/i ) {
			$output->delete('1.0','end');
		# Add device
		} elsif ( /^\+$/ ) {
		# Modify device
		} elsif ( /^\-$/ ) {
		# Bio input
		} elsif ( /^FSS(.*?)FSS$/ ) {
			# Discard duplicate entries
			next if $_ eq $lastinput; $lastinput = $_;
			$bio = $1;
			message(0, "Got FSS Biometric input: $bio");
			$ENV{LDAPOPERATION} = '&';
			%bio = getbio($bio);
			delete $ENV{LDAPOPERATION};
			if ( scalar keys %bio == 0 ) {
				message(2, "uid=$bio not found in LDAP!", "Person not found in LDAP!  Do not allow person to check-out any devices until this problem has been resolved.");
				$lastinput = '';
				clearinput(qw{bio});
			} elsif ( scalar keys %bio == 1 ) {
				%bio = %{$bio{0}};
				message(2, "$bio{description}: $bio{gecos}");
				p("  $pictureurl/$bio{'skyward-STUDENT-ID'}.JPG\n") if $pictures && -f "$picturedir/$bio{'skyward-STUDENT-ID'}.JPG";
			} elsif ( scalar keys %bio > 1 ) {
				message(2, "Multiple entries for uid=$bio found in LDAP!", "Multiple entries for person found in LDAP!  Do not allow person to check-out any devices until this problem has been resolved.");
				$lastinput = '';
				clearinput(qw{bio});
			} else {
				message(1, "ERROR");
			}
		# Anything else is expected to be a device
		} else {
			# Discard duplicate entries
			next if $_ eq $lastinput; $lastinput = $_;
			chomp($localDevice=$_);
			my $mac = eval {
				my $mac = Net::MAC->new(mac => $localDevice);
				$mac = $mac->convert(delimiter => ':');
				$mac->get_mac();
			} || $localDevice;
			message(0, "Got other input: $localDevice");
			$ENV{LDAPOPERATION} = '|';
			%localDevice = getdevice(localDeviceName=>$localDevice, localDeviceLANMAC=>$mac, localDeviceWLANMAC=>$mac, localDeviceSerialNumber=>$localDevice, localDeviceLocalSerialNumber=>$localDevice);
			delete $ENV{LDAPOPERATION};
			if ( scalar keys %localDevice == 0 ) {
				message(2, "$localDevice not found in LDAP!", "Device not found in LDAP!  Do not allow anyone to check-out this device until this problem has been resolved.");
				$lastinput = '';
				clearinput(qw{localDevice});
			} elsif ( scalar keys %localDevice == 1 ) {
				%localDevice = %{$localDevice{0}};
				message(2, "$localDevice{Type}: $localDevice{Name}");
				if ( $autocheckin && !$bio ) {
					if ( ($localDevice{CheckInTimeStamp} && $localDevice{CheckOutTimeStamp} && Date_Cmp($localDevice{CheckInTimeStamp}, $localDevice{CheckOutTimeStamp}) < 0 ) || ( !$localDevice{CheckInTimeStamp} && $localDevice{CheckOutTimeStamp} ) ) {
						$ENV{LDAPOPERATION} = '&';
						%bio = getbio('fss');
						%bio = %{$bio{0}};
						delete $ENV{LDAPOPERATION};
						checkin(\%bio, \%localDevice);
						$lastinput = '';
						clearinput(qw{localDevice});
					}
				}
			} elsif ( scalar keys %localDevice > 1 ) {
				message(2, "Multiple entries for device=$localDevice found in LDAP!", "Multiple entries for device found in LDAP!  Do not allow person to check-out any devices until this problem has been resolved.");
				$lastinput = '';
				clearinput(qw{localDevice});
			} else {
				message(1, "ERROR");
			}
		}
	}

	# Got a pair, get authorization
	# $bio && $localDevice == 1
	if ( $bio && $localDevice ) {
		# Shifted these to avoid a return statement in the middle of the function
		# (if we can avoid it, it is considered a good programming practice).
		if ( $auth ) {
			$phase = 'need_authorization';
			p("Please have an authorized person verify this transaction with a fingerprint:\n");
			extrainput('Please have an authorized person verify this transaction with a fingerprint:');

			# We'll run the next if-block in phasetwo(), after we
			# have the extra input.
			return;
		}

		# Here it is!  Check it in or out.
		if ( !$auth || $authorizer ) {
			if ( $localDevice{CheckInTimeStamp} && $localDevice{CheckOutTimeStamp} ) {
				if ( Date_Cmp($localDevice{CheckInTimeStamp}, $localDevice{CheckOutTimeStamp}) > 0 ) {
					checkout(\%bio, \%localDevice);
				} elsif ( Date_Cmp($localDevice{CheckInTimeStamp}, $localDevice{CheckOutTimeStamp}) < 0 ) {
					checkin(\%bio, \%localDevice);
				} else {
					message(2, "Too fast!!  Try again!");
				}
			} elsif ( $localDevice{CheckInTimeStamp} && !$localDevice{CheckOutTimeStamp} ) {
				checkout(\%bio, \%localDevice);
			} elsif ( !$localDevice{CheckInTimeStamp} && $localDevice{CheckOutTimeStamp} ) {
				checkin(\%bio, \%localDevice);
			} else {
				checkout(\%bio, \%localDevice);
			}
			clearinput(qw{authorizer bio localDevice});
		}
	}
}

# -----------------------------------------------------------------------

sub ResetAuditing {
	message(2, "Reset auditing:");
	resetdevice($localDevice);
	$lastinput = '';
	clearinput(qw{localDevice});
}

sub clearinput {
	foreach ( @_ ) {
		if ( /^authorizer$/ ) { $authorizer = ''; %authorizer = (); }
		if ( /^bio$/ ) { $bio = ''; %bio = (); }
		if ( /^localDevice$/ ) { $localDevice = ''; %localDevice = (); }
	}
}

sub report {
	my (%report) = @_;
	if ( $report{localDevice} ) {
		message(2, "Device Report: $localDevice{Name}");
		if ( $localDevice{CurrentUser} ) {
			my $currentuser = expanduid($localDevice{CurrentUser});
			my $howlong = howlong($localDevice{CheckOutTimeStamp}, 'now');
			my $checkedout = UnixDate(ParseDate($localDevice{CheckOutTimeStamp}), '%l');
			p("$localDevice{Name} is currently checked-out by $currentuser.  It has been checked-out for $howlong since $checkedout.\n");
		} else {
			p("$localDevice{Name} is not currently checked-out by anyone.\n");
			if ( $localDevice{CheckOutTimeStamp} && $localDevice{CheckInTimeStamp} ) {
				my $lastuser = expanduid($localDevice{LastUser}) || 'no one';
				my $checkedout = UnixDate(ParseDate($localDevice{CheckOutTimeStamp}), '%l') || 'an unknown date';
				my $howlong = howlong($localDevice{CheckOutTimeStamp}, $localDevice{CheckInTimeStamp});
				my $returnedby = expanduid($localDevice{ReturnedBy}) || $lastuser;
				p("$localDevice{Name} was last checked-out by $lastuser on $checkedout for $howlong and returned by $returnedby.\n");
			} else {
				p("$localDevice{Name} has not yet been checked-out by anyone.\n");
			}
		}
	} elsif ( $report{bio} ) {
		my $person = expanduid($bio{uid}) || $bio{uid};
		message(2, "Bio Report: $bio{gecos}");
		my %localDeviceCU = getdevice(localDeviceCurrentUser=>$bio{uid});
		if ( scalar keys %localDeviceCU == 0 ) {
			p("$person currently does not have anything checked-out.\n");
		} elsif ( scalar keys %localDeviceCU >= 1 ) {
			for ( 0..(scalar keys %localDeviceCU) - 1) {
				%_ = %{$localDeviceCU{$_}};
				my $howlong = howlong($_{CheckOutTimeStamp}, 'now');
				my $checkedout = UnixDate(ParseDate($_{CheckOutTimeStamp}), '%l');
				p("$person currently has $_{Name} checked-out which has been checked-out for $howlong since $checkedout.\n");
			}
		}
		my %localDevicelu = getdevice(localDeviceLastUser=>$bio{uid});
		if ( scalar keys %localDevicelu == 0 ) {
			p("$person has not had anything else checked-out.\n");
		} elsif ( scalar keys %localDevicelu >= 1 ) {
			for ( 0..(scalar keys %localDevicelu) - 1) {
				%_ = %{$localDevicelu{$_}};
				my $howlong = howlong($_{CheckOutTimeStamp}, $_{CheckInTimeStamp});
				my $checkedout = UnixDate(ParseDate($_{CheckOutTimeStamp}), '%l');
				my $returnedby = expanduid($_{ReturnedBy}) || $person;
				p("$_{Name} was last checked-out by $person on $checkedout for $howlong and it was returned by $returnedby.\n");
			}
		}
	} elsif ( $report{special} ) {
		if ( $report{special} =~ /^QUERY001$/ ) {
			p("A listing of computers currently checked out for more than 90 minutes and by whom\n");
			my $type = 'Laptop';
			my %localDeviceCO = getdevice(localDeviceType=>$type, localDeviceDescription=>"checkout");
			%_ = ();
			foreach ( keys %localDeviceCO ) {
				next unless $localDeviceCO{$_}{CurrentUser};
				my $err;
			        my ($y, $m, $k, $d, $H, $M, $S) = split /:/, DateCalc($localDeviceCO{$_}{CheckOutTimeStamp}, 'now', \$err, 1);
				my $secs = ($H*60*60)+($M*60)+($S);
				$_{$_} = $localDeviceCO{$_} if $secs >= ((1*60*60)+(30*60)+(0*60));
			}
			%localDeviceCO = %_;
			my $localDeviceCO = scalar keys %localDeviceCO;
			my $list = join '; ', map { "$localDeviceCO{$_}{Name}: ".expanduid($localDeviceCO{$_}{CurrentUser}) } keys %localDeviceCO;
			p("There ${\($localDeviceCO == 1 ? 'is' : 'are')} currently $localDeviceCO Cart ${\($localDeviceCO == 1 ? 'tablet' : 'tablets')} that have been checked-out for more than 90 minutes:\n$list\n");
		} elsif ( $report{special} =~ /^QUERY002$/ ) {
			p("A listing of computers currently checked out and by whom\n");
			my $type = 'Laptop';
			my %localDeviceCO = getdevice(localDeviceType=>$type, localDeviceDescription=>"checkout");
			%_ = ();
			foreach ( keys %localDeviceCO ) {
				next unless $localDeviceCO{$_}{CurrentUser};
				my $err;
				$_{$_} = $localDeviceCO{$_};
			}
			%localDeviceCO = %_;
			my $localDeviceCO = scalar keys %localDeviceCO;
			my $list = join '; ', map { "$localDeviceCO{$_}{Name}: ".expanduid($localDeviceCO{$_}{CurrentUser}) } keys %localDeviceCO;
			p("There ${\($localDeviceCO == 1 ? 'is' : 'are')} currently $localDeviceCO Cart ${\($localDeviceCO == 1 ? 'tablet' : 'tablets')} that have been checked-out:\n$list\n");
		} elsif ( $report{special} =~ /^QUERY003$/ ) {
			p("A listing of computers currently registered\n");
			my $type = 'Laptop';
			my %localDeviceCO = getdevice(localDeviceType=>$type, localDeviceDescription=>"checkout");
			my $localDeviceCO = scalar keys %localDeviceCO;
			my $list = join '; ', sort map { $localDeviceCO{$_}{Name} } keys %localDeviceCO;
			p("There ${\($localDeviceCO == 1 ? 'is' : 'are')} currently $localDeviceCO Cart ${\($localDeviceCO == 1 ? 'tablet' : 'tablets')} registered:\n$list\n");
		} elsif ( $report{special} =~ /^QUERY004$/ ) {
			$phase = 'report_4';
			extrainput("Enter user's name for search:");
		} elsif ( $report{special} =~ /^QUERY005$/ ) {
			$phase = 'report_5';
			extrainput("User's username:");
		} elsif ( $report{special} =~ /^QUERY101$/ ) {
			p("A complete listing of the tablet computers registered in the system\n");
		} elsif ( $report{special} =~ /^QUERY102$/ ) {
			p("A listing of computers currently checked out and by whom\n");
		} else {
			p("This report has not yet been defined.\n")
		}
	} else {
		message(2, "Complete Report:");
		# How many tablets are there total?
		{
			my $type = 'Laptop';
			my %localDeviceCO = getdevice(localDeviceType=>$type, localDeviceDescription=>"checkout");
			my $localDeviceCO = scalar keys %localDeviceCO;
			p("There ${\($localDeviceCO == 1 ? 'is' : 'are')} a total of $localDeviceCO Cart ${\($localDeviceCO == 1 ? 'tablet' : 'tablets')}.\n");
		}
		# How many tablets are currently checked-out?
		{
			my $type = 'Laptop';
			my %localDeviceCO = getdevice(localDeviceType=>$type, localDeviceDescription=>"checkout", localDeviceCurrentUser=>'*');
			my $localDeviceCO = scalar keys %localDeviceCO;
			local %_ = ();
			my $peopleco = scalar grep { !$_{$_}++ } map { $localDeviceCO{$_}{CurrentUser} } keys %localDeviceCO;
			p("There ${\($localDeviceCO == 1 ? 'is' : 'are')} currently $localDeviceCO Cart ${\($localDeviceCO == 1 ? 'tablet' : 'tablets')} checked-out by $peopleco ${\($peopleco == 1 ? 'person' : 'people')}.\n");
		}
		# How many tablets are available?
		{
			my $type = 'Laptop';
			my %localDeviceCO = getdevice(localDeviceType=>$type, localDeviceDescription=>"checkout", localDeviceCurrentUser=>'!*');
			my $localDeviceCO = scalar keys %localDeviceCO;
			p("There ${\($localDeviceCO == 1 ? 'is' : 'are')} currently $localDeviceCO Cart ${\($localDeviceCO == 1 ? 'tablet' : 'tablets')} available for check-out.\n");
		}
		# How many have been out for more than 1 week?
		{
			my $type = 'Laptop';
			my %localDeviceCO = getdevice(localDeviceType=>$type, localDeviceDescription=>"checkout");
			%_ = ();
			foreach ( keys %localDeviceCO ) {
				next unless $localDeviceCO{$_}{CurrentUser};
				my $err;
			        my ($y, $m, $k, $d, $H, $M, $S) = split /:/, DateCalc($localDeviceCO{$_}{CheckOutTimeStamp}, 'now', \$err, 1);
				$_{$_} = $localDeviceCO{$_} if $k >= 1;
			}
			%localDeviceCO = %_;
			my $localDeviceCO = scalar keys %localDeviceCO;
			my $list = join '; ', map { "$localDeviceCO{$_}{Name}: ".expanduid($localDeviceCO{$_}{CurrentUser}) } keys %localDeviceCO;
			p("There ${\($localDeviceCO == 1 ? 'is' : 'are')} currently $localDeviceCO Cart ${\($localDeviceCO == 1 ? 'tablet' : 'tablets')} that have been checked-out for more than one week: $list\n");
		}
		# Which is out for the longest and how long and by whom?
		{
			my $type = 'Laptop';
			my %localDeviceCO = getdevice(localDeviceType=>$type, localDeviceDescription=>"checkout");
			my $longest = -1;
			my $longests = -1;
			foreach ( keys %localDeviceCO ) {
				next unless $localDeviceCO{$_}{CurrentUser};
			        my $a = UnixDate(ParseDate($localDeviceCO{$_}{CheckOutTimeStamp}), "%o");
				my $b = UnixDate(ParseDate('now'), "%o");
				my $secs = $b - $a;
				do { $longest = $_; $longests = $secs } if $secs > $longests;
			}
			if ( $longest >= 0 ) {
				%localDeviceCO = %{$localDeviceCO{$longest}};
				my $currentuser = expanduid($localDeviceCO{CurrentUser}) || 'no one';
				my $checkedout = UnixDate(ParseDate($localDeviceCO{CheckOutTimeStamp}), '%l');
				my $howlong = howlong($localDeviceCO{CheckOutTimeStamp}, 'now');
				p("$localDeviceCO{Name} has been checked-out for the longest amount of time by $currentuser on $checkedout for $howlong.\n");
			} else {
				p("No devices are currently checked-out by anyone.\n");
			}
		}
		#   localDeviceLocation=Unknown
		#   $_{DateCalc(Out, now)}=name
		#   sort %_
	}
}

sub input {
	my $echo = defined $_[0] ? $_[0] : $glb_echo;

	$_ = $input->m_get();
	$input->delete('0','end');
	message(0, "STDIN: $_");

	return $_;
}

sub message {
	my ($type, $message1, $message2) = @_;
	$message2 = $message1 unless $message2;
	syslog($syslog, $message1);
	if ( $type == 0 ) {
	} elsif ( $type == 1 ) {
		die "$message2\n";
	} elsif ( $type >= 2 ) {
		p("$message2\n");
	}
}

sub p {
	my $color = '';
	my $initial_tab = '';
        my $subsequent_tab = '';

	if ($_[$#_] =~ /^(?:red|green|blue|yellow)$/) {
		$color = pop;

		if ($color eq 'red') {
			Win32::Sound::Play('SystemExclamation', SND_ASYNC);
		} elsif ($color eq 'green') {
			Win32::Sound::Play('SystemDefault', SND_ASYNC);
		} elsif ($color eq 'blue') {
			Win32::Sound::Play('SystemAsterisk', SND_ASYNC);
		} elsif ($color eq 'yellow') {
			Win32::Sound::Play('SystemQuestion', SND_ASYNC);
		}
	}

	$output->m_insert('end', join(' ', @_)."\n", $color);
	$output->m_yview('end');
}

sub bindpw {
	my ($password, $passwordfile) = @_;
	# use Term::ReadKey;
	if ( $passwordfile && -f $passwordfile && -r _ ) {
		chomp($password = qx{cat $passwordfile});
	#} elsif ( !$password ) {
	#	print "Enter LDAP Password: ";
	#	ReadMode 'noecho';
	#	do { chomp($password = ReadLine) } until defined $password;
	#	ReadMode 'normal';
	}
	return $password;
}

sub Ul {
	return unless $_[0] =~ / /;
	$name->parse(@_);
	my %names = ();
	my %name = $name->case_components;
	my $search = $ldap->search(
		base=>"ou=People,$ENV{BASEDN}",
		filter => "sn=$name{surname_1}",
	);
	for ( 0..($search->count - 1) ) {
		no warnings;
		my $entry = $search->entry($_);
		next unless $name{given_name_1} && $name{surname_1} && $entry->get_value('givenName') && $entry->get_value('sn');
		my $score = 0;
		eval {
			no warnings;
			$score = name_eq($name{given_name_1}, $name{surname_1}, $entry->get_value('givenName'), $entry->get_value('sn')) || 0;
		};
		$names{$score}{$entry->get_value('uid')} = $entry->get_value('gecos');
	}
	return unless keys %names >= 1;
	my @rank = sort { $b <=> $a } keys %names;
	return keys %{$names{$rank[0]}};
}

sub Ulreport {
	my $cols = shift;
	my $rand = rand();
	$rand =~ s/^\d+\.//;
	local $~ = "LIST$rand";
	my $format  = "format LIST$rand = \n"
		. '@>>> | @' . '<' x $cols . ' | @'. '<' x (65-$cols) . "\n"
		. '@_' . "\n"
		. ".\n";
	eval $format;
	die $@ if $@;
	write();
}

sub pl {
	chomp($_[0]);
	return "No username entered.\n" unless $_[0];
	my $search = $ldap->search(
		base=>"ou=People,$ENV{BASEDN}",
		filter => "uid=$_[0]",
	);
	return "Username not found.\n" unless $search->count == 1;
	my $entry = $search->entry(0);
	return $entry->get_value('userPassword');
}

sub getldap {
	my $base = shift @_;
	my %filter = ();
	if ( $#_ < 0 ) {
		%filter = ( uid => '*' );
	} elsif ( $#_ == 0 ) {
		%filter = ( uid => $_[0] );
	} elsif ( $#_ > 0 ) {
		%filter = @_;
	}
	$ENV{LDAPOPERATION} ||= '&';
	my $filter = "($ENV{LDAPOPERATION}".join('', map { $filter{$_} =~ s/^\!// ? "(!($_=$filter{$_}))" : "($_=$filter{$_})" } keys %filter).')';
	delete $ENV{LDAPOPERATION};
	my $search = $ldap->search(
		base=>"ou=$base,$ENV{BASEDN}",
		filter => "$filter",
	);
	#print "\n\n$filter\n\n";
	if ( $search->code ) {
		message(1, $search->error);
	}
	my %ldap = ();
	return %ldap if $search->count == 0;
	for my $i ( 0..$search->count ) {
		if ( my $entry = $search->entry($i) ) {
			$ldap{$i}{dn} = $entry->dn();
			foreach ( $entry->attributes ) {
				$ldap{$i}{$_} = $entry->get_value($_);
				if ( s/^localDevice// ) {
					$ldap{$i}{$_} = $entry->get_value("localDevice$_");
				} else {
					$ldap{$i}{$_} = $entry->get_value($_);
				}
			}
		} else {
			delete $ldap{$i};
		}
	}
	return %ldap;
}

sub getbio {
	return getldap('People', @_);
}

sub getdevice {
	return getldap('Devices', @_);
}

sub authorized {
	my ($config) = @_;
	return undef unless $config;
	my @config = ();
	return undef unless open CONFIG, $config;
	@config = <CONFIG>;
	close CONFIG;
	my @authorized = map { /^authorized\s*=\s*(.*)/; split /\s+/, $1 } grep { /^authorized\s*=\s*/ } @config;
	my @authgroup = map { /^authgroup\s*=\s*(.*)/; split /\s+/, $1 } grep { /^authgroup\s*=\s*/ } @config;
	foreach ( @authgroup ) {
		push @authorized, (split /\s+/, (getgrnam($_))[3]);
	}
	%_ = ();
	foreach ( @authorized ) {
		$_{$_}++;
	}
	return sort keys %_;
}

sub howlong {
	my $err;
	my ($y, $m, $k, $d, $H, $M, $S) = split /:/, DateCalc(ParseDate($_[0]), ParseDate($_[1]), \$err, 1);
	$y =~ s/^[+-]//;
	my @howlong = ();
	push @howlong, "$y year".($y>1?'s':'') if $y;
	push @howlong, "$m month".($m>1?'s':'') if $m;
	push @howlong, "$k week".($k>1?'s':'') if $k;
	push @howlong, "$d day".($d>1?'s':'') if $d;
	push @howlong, "$H hour".($H>1?'s':'') if $H;
	push @howlong, "$M minute".($M>1?'s':'') if $M;
	return $#howlong>=0 ? join ' ', @howlong : 'less than one minute';
}

sub expanduid {
	my ($bio) = @_;
	return undef unless $bio;
	my %bio = getbio($bio);
	if ( scalar keys %bio == 0 ) {
		message(2, "Person ($bio) not found in LDAP!");
		return undef;
	} elsif ( scalar keys %bio == 1 ) {
		%bio = %{$bio{0}};
		my $yr = (localtime())[5];
		$yr += 1900;
		$yr++ if (localtime())[4] >= 7;
		return $bio{gecos} unless $bio{'localStudentGradYr'};
		if ( $bio{'localStudentGradYr'} < $yr ) {
			return "$bio{gecos} (Graduated)";
		} elsif ( $bio{'localStudentGradYr'} == $yr ) {
			return "$bio{gecos} (Senior)";
		} elsif ( $bio{'localStudentGradYr'} == $yr + 1 ) {
			return "$bio{gecos} (Junior)";
		} elsif ( $bio{'localStudentGradYr'} == $yr + 2 ) {
			return "$bio{gecos} (Sophomore)";
		} elsif ( $bio{'localStudentGradYr'} == $yr + 3 ) {
			return "$bio{gecos} (Freshman)";
		} elsif ( $bio{'localStudentGradYr'} >= $yr + 4 ) {
			return "$bio{gecos} (Elementary)";
		}
	} else {
		message(2, "Multiple entries for person ($bio) found in LDAP!");
		return undef;
	}
}

sub resetdevice {
	my ($localDevice) = @_;
	$localDevice ||= '*';
	$ENV{LDAPOPERATION} = '|';
	my %localDeviceQ = getdevice(localDeviceName=>$localDevice, localDeviceLANMAC=>$localDevice, localDeviceWLANMAC=>$localDevice, localDeviceSerialNumber=>$localDevice, localDeviceLocalSerialNumber=>$localDevice);
	delete $ENV{LDAPOPERATION};
	for ( 0..(scalar keys %localDeviceQ) - 1 ) {
		next unless $localDeviceQ{$_}{dn};
		next unless $localDeviceQ{$_}{Location} && $localDeviceQ{$_}{Location} eq 'Unknown';
		next unless $localDeviceQ{$_}{Type} && $localDeviceQ{$_}{Type} =~ /^Laptop$|^Tablet$/;
		next unless $localDeviceQ{$_}{CurrentUser} || $localDeviceQ{$_}{LastUser} || $localDeviceQ{$_}{ReturnedBy} || $localDeviceQ{$_}{CheckInTimeStamp} || $localDeviceQ{$_}{CheckOutTimeStamp};
		my $entry = Net::LDAP::Entry->new;
		$entry->dn($localDeviceQ{$_}{dn});
		$entry->changetype('modify');
		$entry->delete('localDeviceCurrentUser') if $localDeviceQ{$_}{CurrentUser};
		$entry->delete('localDeviceLastUser') if $localDeviceQ{$_}{LastUser};
		$entry->delete('localDeviceReturnedBy') if $localDeviceQ{$_}{ReturnedBy};
		$entry->delete('localDeviceCheckInTimeStamp') if $localDeviceQ{$_}{CheckInTimeStamp};
		$entry->delete('localDeviceCheckOutTimeStamp') if $localDeviceQ{$_}{CheckOutTimeStamp};
		my $update = $entry->update($ldap);
		if ( $update->code ) {
			p("!!! FATAL ERROR (resetdevice)\n");
			message(1, $update->error);
		}
		message(2, "Reset: $localDeviceQ{$_}{Name}");
	}
}

sub checkout {
	my ($bio, $localDevice) = @_;
	my %bio = %{$bio};
	my %localDevice = %{$localDevice};
	my $search = $ldap->search(
		base=>"ou=Devices,$ENV{BASEDN}",
		filter => "localDeviceCurrentUser=$bio{uid}",
	);
	if ( $search->entry(0) && !$multiple ) {
		my $entry = $search->entry(0);
		message(2, "$bio{gecos} still has ".$entry->get_value('localDeviceName')." checked-out and is not allowed any more!");
		p("!!! Do NOT give anything to $bio{gecos}!\n", 'red');
		return undef;
	} else {
		$localDevice{CheckOutTimeStamp} = ParseDate('now');
		$localDevice{CurrentUser} = $bio{uid};
		my $entry = Net::LDAP::Entry->new;
		$entry->dn($localDevice{dn});
		$entry->changetype('modify');
		$entry->delete('localDeviceReturnedBy') if $localDevice{ReturnedBy};
		$entry->replace(
			localDeviceCurrentUser => $localDevice{CurrentUser},
			localDeviceCheckOutTimeStamp => $localDevice{CheckOutTimeStamp},
		);
		my $update = $entry->update($ldap);
		if ( $update->code ) {
			p("!!! FATAL ERROR (checkout): DO NOT GIVE ANYTHING TO ANYONE.  Suspend all further transactions until error is resolved.\n", 'red');
			message(1, $update->error);
		}
		message(2, "$localDevice{Name} checked out by $bio{gecos} at ".UnixDate($localDevice{CheckOutTimeStamp}, "%c"));
		p("!!! $localDevice{CurrentUser} must now receive $localDevice{Name}\n", 'yellow');
		return 1;
	}
}

sub checkin {
	my ($bio, $localDevice) = @_;
	my %bio = %{$bio};
	my %localDevice = %{$localDevice};
	message(2, "$bio{gecos} is returning $localDevice{Name} on behalf of ".expanduid($localDevice{CurrentUser})."!") if $bio{uid} ne $localDevice{CurrentUser};
	if ( $bio{uid} eq $localDevice{CurrentUser} || $behalf ) {
		$localDevice{CheckInTimeStamp} = ParseDate('now');
		$localDevice{CurrentUser} = $bio{uid};
		my $entry = Net::LDAP::Entry->new;
		$entry->dn($localDevice{dn});
		$entry->changetype('modify');
		$entry->delete('localDeviceCurrentUser') if $localDevice{CurrentUser};
		$entry->replace(
			localDeviceLastUser => $localDevice{CurrentUser},
			localDeviceReturnedBy => $bio{uid},
			localDeviceCheckInTimeStamp => $localDevice{CheckInTimeStamp},
		);
		my $update = $entry->update($ldap);
		if ( $update->code ) {
			p("!!! FATAL ERROR (checkin): Please log transaction on paper.  Suspend all further transactions until error is resolved.\n", 'red');
			message(1, $update->error);
		}
		message(2, "$localDevice{Name} returned by $bio{gecos} at ".UnixDate($localDevice{CheckInTimeStamp}, "%c"));
		p("!!! $bio{uid} must now return $localDevice{Name}.\n", 'green');
		return 1;
	} else {
		message(2, "$bio{gecos} is not authorized to return $localDevice{Name} on behalf of ".expanduid($localDevice{CurrentUser}).".  Transaction cancelled!!");
		return undef;
	}
}
